#!/usr/bin/env bash
set -euo pipefail

mode="upload"
output=""
build_number=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    --export-only) mode="export-only"; shift ;;
    --build-number) build_number="$2"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$output" ]] || { echo "--output DIR required" >&2; exit 2; }
for var in APPLE_TEAM_ID ASC_KEY_ID ASC_ISSUER_ID; do
  [[ -n "${!var:-}" ]] || { echo "Missing $var" >&2; exit 1; }
done

repo="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$output"
work="$(mktemp -d "${TMPDIR:-/tmp}/cadence-tf.XXXXXXXX")"
trap 'rm -rf -- "$work"' EXIT

key_file="$work/AuthKey_${ASC_KEY_ID}.p8"
if [[ -n "${ASC_KEY_P8_BASE64:-}" ]]; then
  printf '%s' "$ASC_KEY_P8_BASE64" | base64 --decode > "$key_file"
elif [[ -n "${ASC_KEY_PATH:-}" ]]; then
  cp "$ASC_KEY_PATH" "$key_file"
else
  echo "Provide ASC_KEY_P8_BASE64 or ASC_KEY_PATH" >&2
  exit 1
fi
chmod 600 "$key_file"

cp -R "$repo/ios" "$work/ios"
if [[ -n "${CADENCE_DEFAULT_SERVER_URL:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CadenceDefaultServerURL ${CADENCE_DEFAULT_SERVER_URL}" \
    "$work/ios/Cadence/Info.plist"
fi

xcrun swift test --package-path "$work/ios/CadenceCore" --scratch-path "$work/swift-test"

(cd "$work/ios" && xcodegen generate)

archive="$work/Cadence.xcarchive"
archive_args=(
  -project "$work/ios/Cadence.xcodeproj"
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
if [[ -n "$build_number" ]]; then
  archive_args+=("CADENCE_IOS_BUILD_NUMBER=$build_number")
fi

xcodebuild archive "${archive_args[@]}"

archived_app="$archive/Products/Applications/Cadence.app"
python3 - "$archived_app/Info.plist" <<'PY'
import plistlib, sys
from pathlib import Path
app = plistlib.loads(Path(sys.argv[1]).read_bytes())
assert app["CFBundleIdentifier"] == "dev.jhinx.cadence"
assert app.get("ITSAppUsesNonExemptEncryption") is False
assert "arm64" in (app.get("UIRequiredDeviceCapabilities") or [])
PY

destination="upload"
[[ "$mode" == "export-only" ]] && destination="export"

cat > "$work/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>destination</key>
  <string>${destination}</string>
  <key>teamID</key>
  <string>${APPLE_TEAM_ID}</string>
  <key>signingStyle</key>
  <string>automatic</string>
</dict>
</plist>
EOF

mkdir -p "$work/export"
xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportOptionsPlist "$work/ExportOptions.plist" \
  -exportPath "$work/export" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$key_file" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"

if [[ "$mode" == "export-only" ]]; then
  find "$work/export" -name '*.ipa' -exec cp {} "$output/" \;
fi
printf '{"status":"ok","mode":"%s","bundle_id":"dev.jhinx.cadence"}\n' "$mode" > "$output/testflight-receipt.json"
