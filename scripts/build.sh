#!/bin/bash
set -euo pipefail

wisp_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Bard's app target must be built on macOS 14 or later."
  echo "The portable core tests can run on Linux with: swift test"
  exit 1
fi
wisp_os_major="$(/usr/bin/sw_vers -productVersion | /usr/bin/cut -d. -f1)"
if (( wisp_os_major < 14 )); then
  echo "Bard requires macOS 14 or later."
  exit 1
fi

# A Mac can have Xcode installed while its active command-line tools point at
# a missing or unfinished installation. Use a working Xcode for this process
# without changing the user's global xcode-select setting.
wisp_check_tools() {
  /usr/bin/xcrun --find swift || return
  /usr/bin/xcrun --sdk macosx --show-sdk-path || return
  /usr/bin/xcrun swift --version || return
}

wisp_tools_ready=false
wisp_found_xcode=""
if wisp_tools_error="$(wisp_check_tools 2>&1)"; then
  wisp_tools_ready=true
elif [[ -z "${DEVELOPER_DIR:-}" ]]; then
  for wisp_candidate in "/Library/Developer/CommandLineTools" \
                        "/Applications/Xcode.app/Contents/Developer" \
                        "$HOME/Applications/Xcode.app/Contents/Developer" \
                        /Applications/Xcode*.app/Contents/Developer; do
    [[ -d "$wisp_candidate" ]] || continue
    wisp_found_xcode="$wisp_candidate"
    if wisp_candidate_error="$(DEVELOPER_DIR="$wisp_candidate" wisp_check_tools 2>&1)"; then
      export DEVELOPER_DIR="$wisp_candidate"
      wisp_tools_ready=true
      break
    fi
    wisp_tools_error="$wisp_candidate_error"
  done
fi

if [[ "$wisp_tools_ready" != true ]]; then
  echo "Bard could not start Apple's build tools."
  if [[ -n "${DEVELOPER_DIR:-}" ]]; then
    printf 'The requested developer tools are at: %s\n' "$DEVELOPER_DIR"
    echo "Open that Xcode installation and finish any setup prompts."
    echo "If that path is no longer correct, remove or correct DEVELOPER_DIR before retrying."
  elif [[ -n "$wisp_found_xcode" ]]; then
    printf 'Xcode was found at: %s\n' "${wisp_found_xcode%/Contents/Developer}"
    echo "Open Xcode once and finish any setup prompts, then run Install.command again."
  else
    echo "Install Xcode 15 or later and open it once to finish setup."
    echo "For Command Line Tools instead, run: xcode-select --install"
  fi
  printf '\nApple reported:\n%s\n' "$wisp_tools_error"
  exit 1
fi
if [[ -n "${DEVELOPER_DIR:-}" ]]; then
  printf 'Using developer tools: %s\n' "$DEVELOPER_DIR"
fi

cd "$wisp_root"
echo "Building Bard for this Mac…"
wisp_sdk="${WISP_SDK_PATH:-$(/usr/bin/xcrun --sdk macosx --show-sdk-path)}"
export CLANG_MODULE_CACHE_PATH="$wisp_root/.module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
/usr/bin/xcrun swift build --build-system native --sdk "$wisp_sdk" --configuration release --product Wisp \
  --cache-path .build-cache --config-path .build-config --security-path .build-security
wisp_bin="$(/usr/bin/xcrun swift build --build-system native --sdk "$wisp_sdk" --configuration release --product Wisp --show-bin-path)"
test -x "$wisp_bin/Wisp"

mkdir -p "$wisp_root/build"
wisp_stage="$(mktemp -d "$wisp_root/build/Wisp-stage.XXXXXX")"
trap 'rm -rf "$wisp_stage"' EXIT
wisp_app="$wisp_stage/Bard.app"
mkdir -p "$wisp_app/Contents/MacOS" "$wisp_app/Contents/Resources"
/usr/bin/ditto "$wisp_bin/Wisp" "$wisp_app/Contents/MacOS/Wisp"
/usr/bin/ditto "$wisp_root/Support/Info.plist" "$wisp_app/Contents/Info.plist"
/usr/bin/ditto "$wisp_root/Sources/Wisp/Resources/wisp-mark.png" "$wisp_app/Contents/Resources/wisp-mark.png"
for wisp_bundle in "$wisp_bin"/*.bundle; do
  if [[ -d "$wisp_bundle" ]]; then
    /usr/bin/ditto "$wisp_bundle" "$wisp_app/Contents/Resources/$(basename "$wisp_bundle")"
  fi
done

# Use the same original wordless, transparent icon as the universal release.
/bin/bash "$wisp_root/scripts/package-icon.sh" "$wisp_app" "$wisp_stage"
/usr/bin/plutil -lint "$wisp_app/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$wisp_app"
/usr/bin/codesign --verify --deep --strict "$wisp_app"
/bin/bash "$wisp_root/scripts/package-custom-icon.sh" "$wisp_app" "$wisp_stage"

if [[ -d "$wisp_root/build/Bard.app" ]]; then
  mv "$wisp_root/build/Bard.app" "$wisp_root/build/Bard-previous-$(date +%Y%m%d-%H%M%S)-$$.app"
fi
mv "$wisp_app" "$wisp_root/build/Bard.app"
echo "Built: $wisp_root/build/Bard.app"
