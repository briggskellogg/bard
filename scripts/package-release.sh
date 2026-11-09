#!/bin/bash
# Package existing SwiftPM release binaries; this script never compiles or installs.
set -euo pipefail

wisp_fail() { printf 'Bard packaging: %s\n' "$*" >&2; exit 1; }

if [[ $# -lt 2 || $# -gt 3 ]]; then
  printf 'Usage: %s ARM64_RELEASE_BIN_DIR X86_64_RELEASE_BIN_DIR [OUTPUT_DIR]\n' "$0" >&2
  exit 2
fi
[[ "$(/usr/bin/uname -s)" == Darwin ]] || wisp_fail 'macOS is required.'

wisp_root="$(cd "$(dirname "$0")/.." && pwd)"
wisp_arm_bin="$(cd "$1" && pwd)"
wisp_intel_bin="$(cd "$2" && pwd)"
wisp_output="${3:-$wisp_root/build/release}"
[[ -x "$wisp_arm_bin/Wisp" ]] || wisp_fail 'The Apple Silicon Wisp binary is missing.'
[[ -x "$wisp_intel_bin/Wisp" ]] || wisp_fail 'The Intel Wisp binary is missing.'
[[ -f "$wisp_root/Support/Info.plist" ]] || wisp_fail 'Support/Info.plist is missing.'
wisp_logo="$wisp_root/Sources/Wisp/Resources/wisp-mark.png"
[[ -f "$wisp_logo" ]] || wisp_fail 'The Wisp icon is missing.'

/usr/bin/lipo "$wisp_arm_bin/Wisp" -verify_arch arm64
/usr/bin/lipo "$wisp_intel_bin/Wisp" -verify_arch x86_64
# WispCore is linked into each executable by SwiftPM; there is no separate library
# to ship. Refuse an unexpected dynamic WispCore dependency.
for wisp_binary in "$wisp_arm_bin/Wisp" "$wisp_intel_bin/Wisp"; do
  if /usr/bin/otool -L "$wisp_binary" | /usr/bin/grep -Eq 'WispCore[^[:space:]]*\.(dylib|framework)'; then
    wisp_fail 'An unexpected dynamic WispCore dependency needs separate packaging.'
  fi
done

wisp_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$wisp_root/Support/Info.plist")"
[[ "$wisp_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || wisp_fail 'The app version must use three numeric components.'
/bin/mkdir -p "$wisp_output"
wisp_output="$(cd "$wisp_output" && pwd)"
wisp_final_app="$wisp_output/Bard.app"
wisp_final_dmg="$wisp_output/Bard-$wisp_version-universal.dmg"
for wisp_destination in "$wisp_final_app" "$wisp_final_dmg"; do
  [[ ! -e "$wisp_destination" && ! -L "$wisp_destination" ]] || wisp_fail "Refusing to overwrite $wisp_destination"
done

wisp_stage="$(/usr/bin/mktemp -d "$wisp_output/.wisp-package.XXXXXX")"
wisp_mounted=false
wisp_cleanup() {
  if [[ "$wisp_mounted" == true ]]; then
    /usr/bin/hdiutil detach -quiet "$wisp_stage/mounted" || return
  fi
  /bin/rm -rf "$wisp_stage"
}
trap wisp_cleanup EXIT
wisp_app="$wisp_stage/Bard.app"
/bin/mkdir -p "$wisp_app/Contents/MacOS" "$wisp_app/Contents/Resources"
/usr/bin/lipo -create "$wisp_arm_bin/Wisp" "$wisp_intel_bin/Wisp" -output "$wisp_app/Contents/MacOS/Wisp"
/bin/chmod 755 "$wisp_app/Contents/MacOS/Wisp"
/usr/bin/ditto "$wisp_root/Support/Info.plist" "$wisp_app/Contents/Info.plist"
/usr/bin/ditto "$wisp_logo" "$wisp_app/Contents/Resources/wisp-mark.png"

# SwiftPM resource bundles must be present and identical in both builds.
shopt -s nullglob
wisp_arm_bundles=("$wisp_arm_bin"/*.bundle)
wisp_intel_bundles=("$wisp_intel_bin"/*.bundle)
[[ ${#wisp_arm_bundles[@]} -gt 0 ]] || wisp_fail 'The SwiftPM resource bundle is missing.'
[[ ${#wisp_arm_bundles[@]} -eq ${#wisp_intel_bundles[@]} ]] || wisp_fail 'The builds have different resource bundles.'
for wisp_bundle in "${wisp_arm_bundles[@]}"; do
  wisp_bundle_name="$(/usr/bin/basename "$wisp_bundle")"
  [[ -d "$wisp_bundle" && -d "$wisp_intel_bin/$wisp_bundle_name" ]] || wisp_fail "Missing resource bundle: $wisp_bundle_name"
  # Swift's native build engine creates a macOS Contents/Resources bundle;
  # llbuild creates a flat bundle. Ship the flat asset root expected by
  # WispResources, preserving the exact files in either build layout.
  wisp_arm_resources="$wisp_bundle"
  wisp_intel_resources="$wisp_intel_bin/$wisp_bundle_name"
  if [[ -d "$wisp_arm_resources/Contents/Resources" ]]; then wisp_arm_resources="$wisp_arm_resources/Contents/Resources"; fi
  if [[ -d "$wisp_intel_resources/Contents/Resources" ]]; then wisp_intel_resources="$wisp_intel_resources/Contents/Resources"; fi
  /usr/bin/diff -qr "$wisp_arm_resources" "$wisp_intel_resources" >/dev/null || wisp_fail "Resources differ between architectures: $wisp_bundle_name"
  /usr/bin/ditto "$wisp_arm_resources" "$wisp_app/Contents/Resources/$wisp_bundle_name"
  /usr/bin/diff -qr "$wisp_arm_resources" "$wisp_app/Contents/Resources/$wisp_bundle_name" >/dev/null || wisp_fail "Packaged resources differ: $wisp_bundle_name"
done

# Keep the original transparent wordless mark in the standard bundle icon.
# Finder metadata is applied after signing to bypass macOS 26's automatic tile.
/bin/bash "$wisp_root/scripts/package-icon.sh" "$wisp_app" "$wisp_stage"
/usr/bin/plutil -lint "$wisp_app/Contents/Info.plist" >/dev/null

# Ad-hoc signing is a local integrity signature, not Developer ID signing or
# Apple notarization. No certificate or credential is requested or modified.
/usr/bin/codesign --force --sign - "$wisp_app"
/usr/bin/codesign --verify --deep --strict "$wisp_app"
/bin/bash "$wisp_root/scripts/package-custom-icon.sh" "$wisp_app" "$wisp_stage"
wisp_archs="$(/usr/bin/lipo -archs "$wisp_app/Contents/MacOS/Wisp")"
[[ "$wisp_archs" == 'x86_64 arm64' || "$wisp_archs" == 'arm64 x86_64' ]] || wisp_fail "Unexpected architectures: $wisp_archs"

wisp_dmg_contents="$wisp_stage/disk"
/bin/mkdir -p "$wisp_dmg_contents"
/usr/bin/ditto "$wisp_app" "$wisp_dmg_contents/Bard.app"
"$wisp_stage/wisp-custom-icon" verify "$wisp_dmg_contents/Bard.app" "$wisp_stage/Wisp-signed-contents.json"
/bin/ln -s /Applications "$wisp_dmg_contents/Applications"
/bin/cat > "$wisp_dmg_contents/Install Bard.txt" <<'WISP_INSTALL'
Bard

Requires macOS 14 or later. Works on Apple Silicon and Intel Macs.

1. Drag Bard to Applications.
2. Eject this disk, then open Bard from Applications.

No Xcode or compilation is required.

Mixtape sync connects Bard to Music on this Mac automatically. When macOS asks,
allow Bard to control Music to keep the dedicated playlist up to date. The
mixtape starts empty; add the songs you want in Bard. If permission is denied,
enable Bard in System Settings > Privacy & Security > Automation, then retry.

This build is ad-hoc signed and has not been notarized by Apple. If macOS
blocks the first launch, open System Settings > Privacy & Security and use
Open Anyway for Bard, then confirm Open. Only do this for a copy you trust.
WISP_INSTALL
wisp_staged_dmg="$wisp_stage/Bard-$wisp_version-universal.dmg"
/usr/bin/hdiutil create -quiet -volname Bard -srcfolder "$wisp_dmg_contents" -fs HFS+ -format UDZO "$wisp_staged_dmg"
/usr/bin/hdiutil verify -quiet "$wisp_staged_dmg"

# Prove the disk image and a normal macOS copy preserve both signed Contents
# and the icon's resource fork. All checks use staging, never /Applications.
/bin/mkdir -p "$wisp_stage/mounted" "$wisp_stage/copied"
/usr/bin/hdiutil attach -quiet -readonly -nobrowse -mountpoint "$wisp_stage/mounted" "$wisp_staged_dmg"
wisp_mounted=true
"$wisp_stage/wisp-custom-icon" verify "$wisp_stage/mounted/Bard.app" "$wisp_stage/Wisp-signed-contents.json"
/usr/bin/ditto "$wisp_stage/mounted/Bard.app" "$wisp_stage/copied/Bard.app"
"$wisp_stage/wisp-custom-icon" verify "$wisp_stage/copied/Bard.app" "$wisp_stage/Wisp-signed-contents.json"
/usr/bin/codesign --verify --deep "$wisp_stage/copied/Bard.app"
/usr/bin/codesign --verify --deep --strict=symlinks "$wisp_stage/copied/Bard.app"
/usr/bin/hdiutil detach -quiet "$wisp_stage/mounted"
wisp_mounted=false

# Check again before publishing; all packaging and validation happened in staging.
for wisp_destination in "$wisp_final_app" "$wisp_final_dmg"; do
  [[ ! -e "$wisp_destination" && ! -L "$wisp_destination" ]] || wisp_fail "Refusing to overwrite $wisp_destination"
done
/bin/mv "$wisp_app" "$wisp_final_app"
/bin/mv "$wisp_staged_dmg" "$wisp_final_dmg"
printf 'App: %s\nDMG: %s\nArchitectures: %s\nSigning: ad-hoc; not notarized\nIcon: transparent per-app Finder metadata; signed contents and DMG copy verified\n' "$wisp_final_app" "$wisp_final_dmg" "$wisp_archs"
