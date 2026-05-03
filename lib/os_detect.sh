#!/usr/bin/env bash
set -Eeuo pipefail

OS_FAMILY=""
PKG_MANAGER=""


detect_platform() {
  local uname_out
  uname_out="$(uname -s)"

  case "$uname_out" in
    Linux)
      OS_FAMILY="linux"
      detect_linux_package_manager
      ;;
    Darwin)
      OS_FAMILY="macos"
      PKG_MANAGER="brew"
      ;;
    *)
      log_error "Unsupported OS: $uname_out"
      exit 1
      ;;
  esac

  log_info "Detected platform: os=$OS_FAMILY pkg_manager=$PKG_MANAGER"
}


detect_linux_package_manager() {
  if is_command apt-get; then
    PKG_MANAGER="apt"
    return
  fi
  if is_command pacman; then
    PKG_MANAGER="pacman"
    return
  fi

  log_error "Unsupported Linux package manager. Need apt or pacman."
  exit 1
}
