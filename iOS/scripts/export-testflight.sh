#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/common.sh"
require_team
provisioning_arguments
require_xcode iphoneos
wisp_archive="${1:?Usage: export-testflight.sh SIGNED_ARCHIVE.xcarchive NEW_EXPORT_DIRECTORY}"
wisp_export="${2:?Choose a new export directory}"
[[ -d "$wisp_archive" && ! -e "$wisp_export" ]] || { echo 'A signed archive and a new export directory are required.' >&2; exit 2; }
mkdir -p "$wisp_export"
wisp_options="$wisp_export/ExportOptions.generated.plist"
/usr/bin/python3 - "$wisp_options" "$WISP_TEAM_ID" <<'PY'
import pathlib,plistlib,sys
options={'method':'app-store-connect','destination':'export','signingStyle':'automatic',
         'teamID':sys.argv[2],'uploadSymbols':True,'manageAppVersionAndBuildNumber':False}
pathlib.Path(sys.argv[1]).write_bytes(plistlib.dumps(options))
PY
# destination=export produces local files only. Upload and TestFlight enrollment
# are separate actions after account, privacy, and signed-build verification.
/usr/bin/xcodebuild -exportArchive -archivePath "$wisp_archive" \
  -exportPath "$wisp_export" -exportOptionsPlist "$wisp_options" ${wisp_provisioning_arguments[@]+"${wisp_provisioning_arguments[@]}"}
