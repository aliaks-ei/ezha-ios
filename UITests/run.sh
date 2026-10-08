#!/bin/bash
# Runs the UI harness on the Simulator and exports the screenshots. No Xcode window opens.
# Usage: UITests/run.sh [xcodebuild args], e.g. UITests/run.sh -only-testing:EZHAUITests/LibraryUITests
# Env: DEVICE (Simulator name, default "EZHA iPhone 17 Pro").
set -euo pipefail
cd "$(dirname "$0")"
DEVICE="${DEVICE:-EZHA iPhone 17 Pro}"
DESTINATION="${DESTINATION:-platform=iOS Simulator,name=$DEVICE}"
OUT="$PWD/.output"
rm -rf "$OUT"
mkdir -p "$OUT"
xcodegen generate --quiet
status=0
xcodebuild test -project EZHAUITests.xcodeproj -scheme EZHAUITests \
  -destination "$DESTINATION" \
  -derivedDataPath /tmp/ezha-uitests-dd -resultBundlePath "$OUT/result.xcresult" "$@" \
  > "$OUT/xcodebuild.log" 2>&1 || status=$?
grep -E "error:|Test Case .*(passed|failed)|\*\* TEST" "$OUT/xcodebuild.log" | sed 's/^.*Test Case/Test Case/' || true
if [ -d "$OUT/result.xcresult" ]; then
  xcrun xcresulttool export attachments --path "$OUT/result.xcresult" --output-path "$OUT/screenshots" > /dev/null
  # Rename "<uuid>.png" to the attachment name, e.g. "402-library-dark.png".
  python3 - "$OUT/screenshots" <<'PY'
import json, os, re, sys
folder = sys.argv[1]
for test in json.load(open(os.path.join(folder, "manifest.json"))):
    for a in test["attachments"]:
        name = re.sub(r"_\d+_[0-9A-F-]{36}", "", a["suggestedHumanReadableName"])
        os.rename(os.path.join(folder, a["exportedFileName"]), os.path.join(folder, name))
PY
  echo "Screenshots: $OUT/screenshots"
fi
echo "Full log: $OUT/xcodebuild.log"
exit $status
