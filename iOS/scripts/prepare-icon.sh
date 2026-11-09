#!/bin/bash
set -euo pipefail
wisp_ios="$(cd "$(dirname "$0")/.." && pwd)"
bard_light_master="$wisp_ios/../Support/Brand/Bard/bard-iphone-icon-light.svg"
bard_dark_master="$wisp_ios/../Support/Brand/Bard/bard-iphone-icon-dark.svg"
wisp_icon="$wisp_ios/Resources/Assets.xcassets/AppIcon.appiconset/WispAppIcon.png"
wisp_dark_icon="$wisp_ios/Resources/Assets.xcassets/AppIcon.appiconset/WispAppIconDark.png"
command -v rsvg-convert >/dev/null || { echo 'librsvg rsvg-convert is required.' >&2; exit 2; }
rsvg-convert --width 1024 --height 1024 "$bard_light_master" -o "$wisp_icon"
rsvg-convert --width 1024 --height 1024 "$bard_dark_master" -o "$wisp_dark_icon"
python3 - "$wisp_icon" "$wisp_dark_icon" <<'PY'
from pathlib import Path
import struct,sys
for file in sys.argv[1:]:
    b=Path(file).read_bytes()
    assert b[:8]==b'\x89PNG\r\n\x1a\n'
    w,h,depth,colour=struct.unpack('>IIBB',b[16:26])
    assert (w,h)==(1024,1024) and colour==2 and depth==8, 'App icon must be 1024-square RGB with no alpha channel'
print('Verified opaque 1024x1024 RGB light and dark Bard phone icons from the approved vector compositions.')
PY
