#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_PATH")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"
TMP_LIB_DIR=""
DEFAULT_SUPERMASTER_URL="http://100.119.27.108:8080"
CLI_SUPERMASTER_URL="$DEFAULT_SUPERMASTER_URL"
CLI_ROLE_REQUEST=""
CLI_NONINTERACTIVE="0"

print_help() {
  cat <<'EOF'
Usage: install.sh [options]

Options:
  -u, --supermaster-url <url>  Super-master URL (default: http://100.119.27.108:8080)
  -r, --role <master|slave>    Requested role
  -n, --non-interactive        Skip interactive input where possible
  -h, --help               Show this help
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -u|--supermaster-url)
        [[ $# -ge 2 ]] || { printf 'Missing value for --supermaster-url\n' >&2; exit 1; }
        CLI_SUPERMASTER_URL="$2"
        shift 2
        ;;
      -t|--api-token)
        shift
        if [[ $# -gt 0 ]]; then
          shift
        fi
        ;;
      -r|--role)
        [[ $# -ge 2 ]] || { printf 'Missing value for --role\n' >&2; exit 1; }
        CLI_ROLE_REQUEST="$2"
        shift 2
        ;;
      -n|--non-interactive)
        CLI_NONINTERACTIVE="1"
        shift
        ;;
      --)
        shift
        break
        ;;
      -h|--help)
        print_help
        exit 0
        ;;
      *)
        printf 'Unknown option: %s\n' "$1" >&2
        print_help >&2
        exit 1
        ;;
    esac
  done
}

export_cli_inputs() {
  if [[ -n "$CLI_SUPERMASTER_URL" ]]; then
    export BOREALIS_NETWORKING_SUPERMASTER_URL="$CLI_SUPERMASTER_URL"
  fi

  if [[ -n "$CLI_ROLE_REQUEST" ]]; then
    export BOREALIS_NETWORKING_ROLE_REQUEST="$CLI_ROLE_REQUEST"
  fi

  if [[ "$CLI_NONINTERACTIVE" == "1" ]]; then
    export BOREALIS_NETWORKING_NONINTERACTIVE="1"
  fi
}

bootstrap_libs() {
  if [[ -f "$LIB_DIR/common.sh" ]]; then
    return
  fi

  local base_url
  base_url="${BOREALIS_NETWORKING_INSTALL_BASE_URL:-https://raw.githubusercontent.com/dagahan/borealis_networking/release/1.3.0/lib}"
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

parse_args "$@"
export_cli_inputs
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

  log_step "Setting up local borealis networking config"
  setup_local_borealis_networking_dirs

  log_step "Refreshing SSH aliases"
  refresh_ssh_aliases

  log_info "Done. Use 'ssh <device-alias>' for tailnet SSH shortcuts."
}

main
