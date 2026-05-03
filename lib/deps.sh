#!/usr/bin/env bash
set -Eeuo pipefail


install_base_dependencies() {
  if [[ "$OS_FAMILY" == "linux" ]]; then
    install_linux_dependencies
    return
  fi

  install_macos_dependencies
}


install_linux_dependencies() {
  case "$PKG_MANAGER" in
    apt)
      run_sudo apt-get update
      run_sudo apt-get install -y curl jq openssh-client sshfs ca-certificates
      ;;
    pacman)
      run_sudo pacman -Sy --noconfirm --needed curl jq openssh sshfs ca-certificates-utils
      ;;
    *)
      log_error "Unsupported package manager: $PKG_MANAGER"
      exit 1
      ;;
  esac
}


install_macos_dependencies() {
  if ! is_command brew; then
    log_error "Homebrew is required on macOS. Install from https://brew.sh"
    exit 1
  fi

  brew list jq >/dev/null 2>&1 || brew install jq
}
