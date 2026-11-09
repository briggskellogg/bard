#!/bin/bash
set -euo pipefail
bard_root="$(cd "$(dirname "$0")" && pwd)"
/bin/bash "$bard_root/scripts/build.sh"
/usr/bin/open -R "$bard_root/build/Bard.app"
