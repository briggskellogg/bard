#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
require_team
provisioning_arguments
require_xcode iphoneos
generate_project
wisp_archive="${1:?Usage: archive.sh NEW_ARCHIVE_PATH.xcarchive}"
[[ ! -e "$wisp_archive" ]] || { echo 'Archive path already exists; choose a new path.' >&2; exit 2; }
# Local signed archive only. This does not create accounts, change membership,
# accept agreements, or upload to App Store Connect. Provisioning assets may be
# created/downloaded only with WISP_ALLOW_PROVISIONING_UPDATES=1.
/usr/bin/xcodebuild -project "$wisp_ios/WispIOS.xcodeproj" -scheme WispIOS \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$wisp_build_root/DeviceDerivedData" -archivePath "$wisp_archive" \
  DEVELOPMENT_TEAM="$WISP_TEAM_ID" ${wisp_provisioning_arguments[@]+"${wisp_provisioning_arguments[@]}"} archive
