#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || "$(uname -s)" != "Darwin" ]]; then
  echo "Usage on macOS: bash scripts/qualify-ios.sh NEW_EVIDENCE_DIRECTORY" >&2
  exit 2
fi

mkdir -p "$1" "$1/screenshots"
evidence="$(cd -- "$1" && pwd -P)"
cd -- "$(dirname "$0")/.."
root="$PWD"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/cadence-ios.XXXXXXXX")"
device=""

cleanup() {
  local status=$?
  if [[ -n "$device" ]]; then
    xcrun simctl shutdown "$device" >/dev/null 2>&1 || true
    xcrun simctl delete "$device" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$scratch" || true
  exit "$status"
}
trap cleanup EXIT

{
  git rev-parse HEAD || true
  xcodebuild -version
  swift --version
  xcodegen --version
} > "$evidence/toolchain.txt"

# Generate Cadence.xcodeproj cleanly from ios/project.yml
(cd "$root/ios" && xcodegen generate)

# Run pure SwiftPM unit tests first
swift test --package-path "$root/ios/CadenceCore" --scratch-path "$scratch/core" \
  2>&1 | tee "$evidence/core-tests.log"

# Select newest available iPhone simulator runtime
xcrun simctl list runtimes -j > "$scratch/runtimes.json"
template="$(python3 - "$scratch/runtimes.json" <<'PY'
import json
import sys

rows = json.load(open(sys.argv[1]))["runtimes"]
choices = []
for row in rows:
    if not row.get("isAvailable") or ".iOS-" not in row["identifier"]:
        continue
    version = row["version"]
    for device in row.get("supportedDeviceTypes", []):
        if device["name"].startswith("iPhone"):
            choices.append((tuple(map(int, version.split("."))), device["identifier"], row["identifier"]))
if not choices:
    sys.exit("No available iPhone Simulator runtime found.")
_, kind, runtime = max(choices)
print(kind + "\t" + runtime)
PY
)"
IFS=$'\t' read -r device_type runtime <<< "$template"
printf 'Device type: %s\nRuntime: %s\n' "$device_type" "$runtime" > "$evidence/simulator.txt"

device="$(xcrun simctl create "Cadence Qualification" "$device_type" "$runtime")"
xcrun simctl bootstatus "$device" -b > "$evidence/boot.log" 2>&1

export TEST_RUNNER_CADENCE_SCREENSHOT_DIR="$evidence/screenshots"

xcodebuild test \
  -project "$root/ios/Cadence.xcodeproj" \
  -scheme Cadence \
  -configuration Debug \
  -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath "$scratch/derived" \
  -resultBundlePath "$evidence/CadenceUI.xcresult" \
  -parallel-testing-enabled NO \
  CODE_SIGNING_ALLOWED=NO \
  2>&1 | tee "$evidence/ios-tests.log"

xcrun xcresulttool get test-results summary --path "$evidence/CadenceUI.xcresult" \
  > "$evidence/test-summary.json" || true

# Export PNG attachments from xcresult as guaranteed fallback
xcrun xcresulttool export attachments \
  --path "$evidence/CadenceUI.xcresult" \
  --output-path "$evidence/screenshots-xcresult" || true
