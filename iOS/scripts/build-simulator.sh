#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
require_xcode iphonesimulator
generate_project
mkdir -p "$wisp_build_root"
/usr/bin/xcodebuild -project "$wisp_ios/WispIOS.xcodeproj" -scheme WispIOS \
  -configuration Debug -destination "${WISP_IOS_DESTINATION:-generic/platform=iOS Simulator}" \
  -derivedDataPath "$wisp_build_root/DerivedData" CODE_SIGNING_ALLOWED=NO build
