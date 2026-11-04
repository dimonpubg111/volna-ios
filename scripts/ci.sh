#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
python3 - <<'PY'
from pathlib import Path
import hashlib, zipfile
archive = Path('winter-assets-2.2.zip')
assert hashlib.sha256(archive.read_bytes()).hexdigest() == '23a5ed2585744cd690d77e1b309fe5a4c02276502b3c1ab05b7bc0770f7c5fee', 'Winter asset checksum mismatch'
with zipfile.ZipFile(archive) as bundle:
    assert all(name.startswith('VOLNA/Assets.xcassets/') and '..' not in Path(name).parts for name in bundle.namelist())
    bundle.extractall('.')
PY
python3 scripts/generate_project.py
plutil -lint VOLNA/Info.plist VOLNA/PrivacyInfo.xcprivacy VOLNA.xcodeproj/project.pbxproj
xcodebuild -version
xcodebuild -list -project VOLNA.xcodeproj
DEVICE_ID=$(xcrun simctl list devices available -j | python3 -c 'import sys,json;d=json.load(sys.stdin);print(next(x["udid"] for k,v in d["devices"].items() if "iOS" in k for x in v if x["isAvailable"] and x["name"].startswith("iPhone")))')
xcodebuild test -project VOLNA.xcodeproj -scheme VOLNA -configuration Debug \
  -destination "platform=iOS Simulator,id=$DEVICE_ID" -derivedDataPath build/DerivedData \
  -resultBundlePath build/NativeTests.xcresult CODE_SIGNING_ALLOWED=NO \
  -parallel-testing-enabled NO
xcodebuild build -project VOLNA.xcodeproj -scheme VOLNA -configuration Release \
  -destination 'generic/platform=iOS' -derivedDataPath build/Device CODE_SIGNING_ALLOWED=NO
ditto -c -k --sequesterRsrc --keepParent build/DerivedData/Build/Products/Debug-iphonesimulator/VOLNA.app build/VOLNA-Simulator.app.zip
ditto -c -k --sequesterRsrc --keepParent build/Device/Build/Products/Release-iphoneos/VOLNA.app build/VOLNA-Device-UNSIGNED.app.zip
python3 scripts/package_unsigned_ipa.py build/Device/Build/Products/Release-iphoneos/VOLNA.app build/VOLNA-2.2-UNSIGNED.ipa
echo 'Simulator tests and unsigned device compilation completed. Device installation still requires Apple signing.'
