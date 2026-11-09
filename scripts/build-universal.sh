#!/bin/bash
# Developer convenience only. Users install the precompiled DMG.
set -euo pipefail
wisp_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$wisp_root"
wisp_sdk="${WISP_SDK_PATH:-$(/usr/bin/xcrun --sdk macosx --show-sdk-path)}"
wisp_output="${1:-$wisp_root/build/release}"
export CLANG_MODULE_CACHE_PATH="$wisp_root/.module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
wisp_release_bins=()
for wisp_arch in arm64 x86_64; do
  wisp_swift_args=(--build-system native --configuration release --product Wisp
    --triple "$wisp_arch-apple-macosx14.0" --sdk "$wisp_sdk"
    --scratch-path "$wisp_root/.build-$wisp_arch" --cache-path "$wisp_root/.build-cache"
    --config-path "$wisp_root/.build-config" --security-path "$wisp_root/.build-security")
  /usr/bin/xcrun swift build "${wisp_swift_args[@]}"
  # The native engine and llbuild use different output layouts. Resolve using
  # the same build arguments rather than accidentally packaging an old binary.
  wisp_bin="$(/usr/bin/xcrun swift build "${wisp_swift_args[@]}" --show-bin-path)"
  [[ -n "$wisp_bin" && -x "$wisp_bin/Wisp" ]] || { printf 'Missing %s build output: %s\n' "$wisp_arch" "$wisp_bin" >&2; exit 1; }
  wisp_release_bins+=("$(cd "$wisp_bin" && pwd -P)")
done
bash scripts/package-release.sh "${wisp_release_bins[0]}" "${wisp_release_bins[1]}" "$wisp_output"
