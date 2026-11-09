#!/bin/bash
# Both Finder and Dock use the original transparent, wordless blue mark.
# Only resolution changes: no native tile, background, crop, or extra inset.
set -euo pipefail

[[ $# -eq 2 ]] || { echo 'Usage: package-icon.sh APP_PATH STAGING_DIRECTORY' >&2; exit 2; }
wisp_icon_root="$(cd "$(dirname "$0")/.." && pwd)"
wisp_icon_app="$1"
wisp_icon_stage="$2"
wisp_icon_name=Wisp
wisp_icon_source="$wisp_icon_root/Sources/Wisp/Resources/wisp-mark.png"
[[ -f "$wisp_icon_source" ]] || { echo 'The original Wisp mark is missing.' >&2; exit 1; }
[[ -f "$wisp_icon_app/Contents/Info.plist" ]] || { echo 'The staged app Info.plist is missing.' >&2; exit 1; }

wisp_iconset="$wisp_icon_stage/Wisp.iconset"
/bin/mkdir -p "$wisp_iconset" "$wisp_icon_app/Contents/Resources"
for wisp_icon_size in 16 32 128 256 512; do
  /usr/bin/sips -s format png -z "$wisp_icon_size" "$wisp_icon_size" "$wisp_icon_source" \
    --out "$wisp_iconset/icon_${wisp_icon_size}x${wisp_icon_size}.png" >/dev/null
  wisp_icon_retina=$((wisp_icon_size * 2))
  /usr/bin/sips -s format png -z "$wisp_icon_retina" "$wisp_icon_retina" "$wisp_icon_source" \
    --out "$wisp_iconset/icon_${wisp_icon_size}x${wisp_icon_size}@2x.png" >/dev/null
done
# Preserve the PNG payloads at every size. iconutil rewrites the 16/32-point
# entries into legacy ARGB chunks and discards their color profiles, changing
# the blue. Modern macOS supports these standard PNG-bearing ICNS chunk types.
wisp_icon_python="${WISP_PYTHON:-/Library/Developer/CommandLineTools/usr/bin/python3}"
[[ -x "$wisp_icon_python" ]] || wisp_icon_python=/usr/bin/python3
"$wisp_icon_python" - "$wisp_iconset" "$wisp_icon_app/Contents/Resources/$wisp_icon_name.icns" <<'PY_ICNS'
from pathlib import Path
import struct
import sys
source, destination = map(Path, sys.argv[1:])
renditions = [
    ("icp4", "icon_16x16.png"), ("ic11", "icon_16x16@2x.png"),
    ("icp5", "icon_32x32.png"), ("ic12", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"), ("ic13", "icon_128x128@2x.png"),
    ("ic08", "icon_256x256.png"), ("ic14", "icon_256x256@2x.png"),
    ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")
]
chunks = []
for kind, filename in renditions:
    png = (source / filename).read_bytes()
    if not png.startswith(b"\x89PNG\r\n\x1a\n"):
        raise SystemExit(f"Invalid icon rendition: {filename}")
    chunks.append(kind.encode("ascii") + struct.pack(">I", len(png) + 8) + png)
payload = b"".join(chunks)
destination.write_bytes(b"icns" + struct.pack(">I", len(payload) + 8) + payload)
PY_ICNS
[[ -s "$wisp_icon_app/Contents/Resources/$wisp_icon_name.icns" ]] || { echo 'The transparent Wisp icon was not generated.' >&2; exit 1; }

# A native icon catalog would override the classic alpha-bearing ICNS and add
# a Liquid Glass tile. Remove only the prior Wisp-generated icon artifacts.
/bin/rm -f "$wisp_icon_app/Contents/Resources/Assets.car" "$wisp_icon_app/Contents/Resources/Wisp-050.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleIconFile $wisp_icon_name" "$wisp_icon_app/Contents/Info.plist"
if /usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$wisp_icon_app/Contents/Info.plist" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c 'Delete :CFBundleIconName' "$wisp_icon_app/Contents/Info.plist"
fi
