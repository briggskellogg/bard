#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
require_xcode iphoneos
generate_project
mkdir -p "$wisp_build_root"
/usr/bin/xcodebuild -project "$wisp_ios/WispIOS.xcodeproj" -scheme WispIOS \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$wisp_build_root/DeviceDerivedData" CODE_SIGNING_ALLOWED=NO build
