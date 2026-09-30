#!/bin/bash
set -euo pipefail
mkdir -p artifacts
xcodebuild -version | tee artifacts/xcode-version.txt
xcrun --sdk iphoneos --show-sdk-version > artifacts/ios-sdk.txt
python3 - <<'PY'
from pathlib import Path
version = Path('artifacts/ios-sdk.txt').read_text().strip()
if int(version.split('.')[0]) < 26:
    raise SystemExit('Select Xcode with iOS 26 SDK or newer before upload.')
PY
plutil -lint LinkAff.xcodeproj/project.pbxproj LinkAff/PrivacyInfo.xcprivacy
xcodebuild -list -project LinkAff.xcodeproj
xcrun simctl list devices available --json > artifacts/simulators.json
SIMULATOR_ID=$(python3 - <<'PY'
import json
from pathlib import Path
devices = json.loads(Path('artifacts/simulators.json').read_text())['devices']
for runtime, candidates in devices.items():
    if '.iOS-' not in runtime:
        continue
    for device in candidates:
        if device.get('isAvailable') and device['name'].startswith('iPhone'):
            print(device['udid'])
            raise SystemExit(0)
raise SystemExit('No available iPhone Simulator on this runner.')
PY
)
if ! xcrun simctl list devices booted | grep -q "$SIMULATOR_ID"; then
  xcrun simctl boot "$SIMULATOR_ID"
fi
xcrun simctl bootstatus "$SIMULATOR_ID" -b
xcodebuild -project LinkAff.xcodeproj -scheme LinkAff \
  -configuration Debug -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath artifacts/DerivedData -resultBundlePath artifacts/Tests.xcresult \
  CODE_SIGNING_ALLOWED=NO test 2>&1 | tee artifacts/build-test.log
python3 - <<'PY'
from pathlib import Path
import shutil
# Keep reports, not the many gigabytes of DerivedData, in the uploaded artifact.
folder = Path('artifacts/DerivedData')
if folder.exists():
    shutil.rmtree(folder)
PY
