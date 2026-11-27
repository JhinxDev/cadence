#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
# shellcheck source=scripts/lib/testflight_common.sh
source "$repo/scripts/lib/testflight_common.sh"

usage_text=$(cat <<'EOF'
Usage: deploy-testflight-ios.sh --output DIR [--export-only] [--build-number N] [--prune-stale-api-dev-certs]

Archive and export/upload Cadence via Xcode Cloud Signing and App Store Connect API keys.
Requires APPLE_TEAM_ID, ASC_KEY_ID, ASC_ISSUER_ID, and either ASC_KEY_PATH or ASC_KEY_P8_BASE64.
Optional CADENCE_DEFAULT_SERVER_URL embeds an HTTPS default origin in Info.plist before signing.
EOF
)

tf_parse_common_args "$usage_text" "$@"
tf_validate_common_env "$0"

commit=$(git -C "$repo" rev-parse HEAD)
tree=$(git -C "$repo" rev-parse 'HEAD^{tree}')
sdk_version=$(xcrun --sdk iphoneos --show-sdk-version)
xcode_version=$(xcodebuild -version | tr '\n' ' ' | sed 's/ *$//')

server_origin=${CADENCE_DEFAULT_SERVER_URL:-}
unset CADENCE_DEFAULT_SERVER_URL

tf_prepare_empty_output_dir

work=$(mktemp -d "${TMPDIR:-/tmp}/cadence-ios-testflight.XXXXXXXX")
before_serials="$work/dev-serials-before.txt"
after_serials="$work/dev-serials-after.txt"
pre_cleanup_summary="$work/cert-pre-cleanup.json"
cleanup_summary="$work/cert-cleanup.json"
cleanup_done=0
key_file=""

on_exit() {
    local rc=$?
    trap - EXIT
    if [[ $cleanup_done -eq 0 && -n ${key_file:-} && -f ${key_file:-} && -f $before_serials ]]; then
        tf_cleanup_ephemeral_dev_certs \
            "$repo" \
            "$ASC_KEY_ID" \
            "$ASC_ISSUER_ID" \
            "$key_file" \
            "$before_serials" \
            "$after_serials" \
            "$prune_stale_api_dev_certs" \
            "$cleanup_summary" || true
    fi
    rm -rf -- "$work"
    exit "$rc"
}
trap on_exit EXIT

key_file=$(tf_stage_asc_key "$work" "$ASC_KEY_ID")
unset ASC_KEY_P8_BASE64 ASC_KEY_PATH

mkdir -p "$work/source"
cp -R "$repo/ios" "$work/source/ios"
source_dir="$work/source/ios"

tf_inject_server_origin "$source_dir/Cadence/Info.plist" "$server_origin"

xcrun swift test --package-path "$source_dir/CadenceCore" --scratch-path "$work/swift-test"

(cd "$source_dir" && xcodegen generate)

tf_prune_stale_api_dev_certs "$repo" "$ASC_KEY_ID" "$ASC_ISSUER_ID" "$key_file" "$pre_cleanup_summary" "$prune_stale_api_dev_certs" || true
tf_snapshot_apple_dev_serials "$repo" "$before_serials"

archive="$work/Cadence.xcarchive"
archive_args=(
    -project "$source_dir/Cadence.xcodeproj"
    -scheme Cadence
    -configuration Release
    -sdk iphoneos
    -destination 'generic/platform=iOS'
    -archivePath "$archive"
    -derivedDataPath "$work/DerivedData"
    ARCHS=arm64
    "DEVELOPMENT_TEAM=$APPLE_TEAM_ID"
    CODE_SIGN_STYLE=Automatic
    -allowProvisioningUpdates
    -authenticationKeyPath "$key_file"
    -authenticationKeyID "$ASC_KEY_ID"
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"
)
if [[ -n $build_number ]]; then
    archive_args+=("CADENCE_IOS_BUILD_NUMBER=$build_number")
fi

xcodebuild archive "${archive_args[@]}"

archived_app="$archive/Products/Applications/Cadence.app"
[[ -x "$archived_app/Cadence" ]] || fail "Archived Cadence executable missing."
[[ $(xcrun lipo -archs "$archived_app/Cadence") == arm64 ]] || fail "Cadence is not arm64."

python3 - "$archived_app/Info.plist" <<'PY'
import plistlib
import sys
from pathlib import Path

app = plistlib.loads(Path(sys.argv[1]).read_bytes())
assert app["CFBundleIdentifier"] == "dev.jhinx.cadence"
assert app.get("ITSAppUsesNonExemptEncryption") is False, "ITSAppUsesNonExemptEncryption must be false"
assert "arm64" in (app.get("UIRequiredDeviceCapabilities") or []), "Info.plist must require arm64"
PY

destination="upload"
if [[ $mode == export-only ]]; then
    destination="export"
fi

export_plist="$work/ExportOptions.plist"
tf_write_export_options "$export_plist" "$destination" "$APPLE_TEAM_ID"

export_dir="$work/export"
mkdir -p "$export_dir"
xcodebuild -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$export_plist" \
    -exportPath "$export_dir" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$key_file" \
    -authenticationKeyID "$ASC_KEY_ID" \
    -authenticationKeyIssuerID "$ASC_ISSUER_ID"

ipa_file=""
ipa_sha256=""
if [[ $mode == export-only ]]; then
    exported_ipa=$(find "$export_dir" -maxdepth 2 -name '*.ipa' -print -quit)
    [[ -n $exported_ipa && -f $exported_ipa ]] || fail "Exported IPA not found in $export_dir."
    ipa_name=$(basename "$exported_ipa")
    cp "$exported_ipa" "$output/$ipa_name"
    ipa_file="$ipa_name"
    ipa_sha256=$(digest "$output/$ipa_name")
fi

tf_cleanup_ephemeral_dev_certs \
    "$repo" \
    "$ASC_KEY_ID" \
    "$ASC_ISSUER_ID" \
    "$key_file" \
    "$before_serials" \
    "$after_serials" \
    "$prune_stale_api_dev_certs" \
    "$cleanup_summary" || true
cleanup_done=1
certs_revoked=$(tf_read_revoked_count "$pre_cleanup_summary" "$cleanup_summary")

CADENCE_DEFAULT_SERVER_URL="$server_origin" python3 - \
    "$archived_app/Info.plist" \
    "$output/testflight-receipt.json" \
    "$commit" \
    "$tree" \
    "$mode" \
    "$xcode_version" \
    "$sdk_version" \
    "$ipa_file" \
    "$ipa_sha256" \
    "$certs_revoked" <<'PY'
import json
import os
import plistlib
import sys
from pathlib import Path

plist_path, receipt_path, commit, tree, mode, xcode_version, sdk_version, ipa_file, ipa_sha256, certs_revoked = sys.argv[1:]
app = plistlib.loads(Path(plist_path).read_bytes())
receipt = {
    "status": "ok",
    "mode": mode,
    "bundle_id": app["CFBundleIdentifier"],
    "version": app.get("CFBundleShortVersionString"),
    "build_number": app.get("CFBundleVersion"),
    "default_server_url": os.environ.get("CADENCE_DEFAULT_SERVER_URL") or None,
    "commit": commit,
    "tree": tree,
    "xcode": xcode_version,
    "sdk": sdk_version,
    "ipa_file": ipa_file or None,
    "ipa_sha256": ipa_sha256 or None,
    "ephemeral_dev_certs_revoked": int(certs_revoked),
}
Path(receipt_path).write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
PY
