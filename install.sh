#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
TMP_LIB_DIR=""

bootstrap_libs() {
  if [[ -f "$LIB_DIR/common.sh" ]]; then
    return
  fi

  local base_url
  base_url="${NETWORKING_INSTALL_BASE_URL:-https://raw.githubusercontent.com/dagahan/networking/main/lib}"
  TMP_LIB_DIR="$(mktemp -d)"
  LIB_DIR="$TMP_LIB_DIR"

  for file in common.sh os_detect.sh deps.sh tailscale.sh enroll.sh ssh_alias.sh; do
    curl -fsSL "$base_url/$file" -o "$LIB_DIR/$file"
  done
}

cleanup() {
  if [[ -n "$TMP_LIB_DIR" && -d "$TMP_LIB_DIR" ]]; then
    rm -rf "$TMP_LIB_DIR"
  fi
}

trap cleanup EXIT

bootstrap_libs

# shellcheck source=/dev/null
source "$LIB_DIR/common.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/os_detect.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/deps.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/tailscale.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/enroll.sh"
# shellcheck source=/dev/null
source "$LIB_DIR/ssh_alias.sh"

main() {
  log_step "Detecting platform"
  detect_platform

  log_step "Installing installer dependencies"
  install_base_dependencies

  log_step "Installing Tailscale"
  install_tailscale

  log_step "Ensuring tailscaled is running"
  ensure_tailscaled_running

  log_step "Joining tailnet (interactive auth required)"
  tailscale_up_with_ssh

  log_step "Starting enrollment with super-master"
  enrollment_token="$(enroll_start)"

  log_step "Completing enrollment"
  enroll_complete "$enrollment_token"

  log_step "Setting up local networking config"
  setup_local_networking_dirs

  log_step "Refreshing SSH aliases"
  refresh_ssh_aliases

  log_info "Done. Use 'ssh <device-alias>' for tailnet SSH shortcuts."
}

main "$@"
