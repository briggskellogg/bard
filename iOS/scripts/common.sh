#!/bin/bash
set -euo pipefail
wisp_ios="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
wisp_build_root="${WISP_IOS_BUILD_DIR:-$wisp_ios/.build}"
require_xcode() {
  # Read-only checks. Never accept a license, run first-launch setup, or install
  # a platform automatically. The owner completes those steps in Xcode.
  /usr/bin/xcrun --sdk "$1" --show-sdk-path >/dev/null
}
require_team() {
  [[ "${WISP_TEAM_ID:-}" =~ ^[A-Z0-9]{10}$ ]] || {
    echo 'Set WISP_TEAM_ID to your actual Apple Developer team identifier before archiving or exporting.' >&2
    exit 2
  }
}
generate_project() {
  command -v xcodegen >/dev/null || { echo 'XcodeGen 2.44 or newer is required to regenerate the project.' >&2; exit 2; }
  xcodegen generate --spec "$wisp_ios/project.yml" --project "$wisp_ios"
}

provisioning_arguments() {
  # Opt in only when the owner has authorized Xcode-managed signing assets.
  # Defaults remain local-only and do not create/download provisioning assets.
  wisp_provisioning_arguments=()
  case "${WISP_ALLOW_PROVISIONING_UPDATES:-0}" in
    0) ;;
    1) wisp_provisioning_arguments=(-allowProvisioningUpdates) ;;
    *) echo 'WISP_ALLOW_PROVISIONING_UPDATES must be 0 or 1.' >&2; exit 2 ;;
  esac
}
