#!/usr/bin/env bash
set -Eeuo pipefail


install_tailscale() {
  if is_command tailscale; then
    log_info "Tailscale already installed"
    return
  fi

  if [[ "$OS_FAMILY" == "linux" ]]; then
    curl -fsSL https://tailscale.com/install.sh | run_sudo bash
    return
  fi

  brew install tailscale
}


ensure_tailscaled_running() {
  if [[ "$OS_FAMILY" == "linux" ]]; then
    if is_command systemctl; then
      run_sudo systemctl enable --now tailscaled
      return
    fi

    if is_command service; then
      run_sudo service tailscaled start
      return
    fi

    log_error "Could not start tailscaled (no systemctl/service found)."
    exit 1
  fi

  if ! pgrep -x tailscaled >/dev/null 2>&1; then
    if is_command open; then
      open -a Tailscale || true
    fi
  fi
}


tailscale_up_with_ssh() {
  local cmd=(tailscale up --ssh)

  if [[ "${NETWORKING_NONINTERACTIVE:-0}" == "1" ]]; then
    cmd+=(--accept-routes)
  fi

  if [[ "$OS_FAMILY" == "linux" ]]; then
    run_sudo "${cmd[@]}"
    return
  fi

  "${cmd[@]}"
}


collect_tailscale_identity() {
  local status_json
  if [[ "$OS_FAMILY" == "linux" ]]; then
    status_json="$(run_sudo tailscale status --json)"
  else
    status_json="$(tailscale status --json)"
  fi

  local ts_device_id
  local ts_name
  local ts_user

  ts_device_id="$(printf '%s' "$status_json" | jq -r '.Self.ID // empty')"
  ts_name="$(printf '%s' "$status_json" | jq -r '.Self.DNSName // .Self.HostName // empty')"
  ts_user="$(printf '%s' "$status_json" | jq -r '.Self.UserProfile.LoginName // empty')"

  printf '%s\n%s\n%s\n' "$ts_device_id" "$ts_name" "$ts_user"
}
