#!/bin/bash
# Apply only to a clean, already-signed staging bundle. No installed app, global
# icon cache, runtime Dock override, or system security setting is changed.
set -euo pipefail
[[ $# -eq 2 ]] || { echo 'Usage: package-custom-icon.sh APP_PATH STAGING_DIRECTORY' >&2; exit 2; }
wisp_custom_root="$(cd "$(dirname "$0")/.." && pwd)"
wisp_custom_app="$1"
wisp_custom_stage="$2"
wisp_custom_sdk="${WISP_SDK_PATH:-$(/usr/bin/xcrun --sdk macosx --show-sdk-path)}"
wisp_custom_tool="$wisp_custom_stage/wisp-custom-icon"
wisp_custom_manifest="$wisp_custom_stage/Wisp-signed-contents.json"

# Apple's full strict check must pass before Finder adds its supported custom
# icon metadata. The sideband component of --strict deliberately disallows
# FinderInfo/resource forks; normal signature and symlink checks remain valid.
/usr/bin/codesign --verify --deep --strict "$wisp_custom_app"
/usr/bin/xcrun swiftc -parse-as-library -swift-version 5 -sdk "$wisp_custom_sdk" \
  -module-cache-path "$wisp_custom_stage/custom-icon-module-cache" \
  "$wisp_custom_root/scripts/package-custom-icon.swift" -o "$wisp_custom_tool"
"$wisp_custom_tool" apply "$wisp_custom_app" "$wisp_custom_manifest"
/usr/bin/codesign --verify --deep "$wisp_custom_app"
/usr/bin/codesign --verify --deep --strict=symlinks "$wisp_custom_app"
"$wisp_custom_tool" verify "$wisp_custom_app" "$wisp_custom_manifest"
