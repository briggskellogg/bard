#!/bin/bash
# Run only when the owner has authorized uploading this exact frozen build.
# Uploads to App Store Connect; it does not publish an App Store release.
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
require_team
provisioning_arguments
require_xcode iphoneos
wisp_archive="${1:?Usage: upload-testflight.sh ARCHIVE.xcarchive NEW_UPLOAD_DIRECTORY}"
wisp_upload="${2:?Choose a new upload-evidence directory}"
[[ -d "$wisp_archive" && ! -e "$wisp_upload" ]] || { echo 'An archive and a new upload directory are required.' >&2; exit 2; }
mkdir -p "$wisp_upload"
wisp_options="$wisp_upload/ExportOptions.generated.plist"
/usr/bin/python3 - "$wisp_options" "$WISP_TEAM_ID" <<'PY'
import pathlib,plistlib,sys
options={'method':'app-store-connect','destination':'upload','signingStyle':'automatic',
         'teamID':sys.argv[2],'uploadSymbols':True,'manageAppVersionAndBuildNumber':False}
pathlib.Path(sys.argv[1]).write_bytes(plistlib.dumps(options))
PY
/usr/bin/xcodebuild -exportArchive -archivePath "$wisp_archive" \
  -exportPath "$wisp_upload" -exportOptionsPlist "$wisp_options" \
  ${wisp_provisioning_arguments[@]+"${wisp_provisioning_arguments[@]}"}
