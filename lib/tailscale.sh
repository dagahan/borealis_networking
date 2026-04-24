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
  local output

  if [[ "${BOREALIS_NETWORKING_NONINTERACTIVE:-0}" == "1" ]]; then
    cmd+=(--accept-routes)
  fi

  if [[ "$OS_FAMILY" == "linux" ]]; then
    if output="$(run_sudo "${cmd[@]}" 2>&1)"; then
      return
    fi
  else
    if output="$("${cmd[@]}" 2>&1)"; then
      return
    fi
  fi

  if grep -q "requires mentioning all" <<<"$output"; then
    local suggested
    suggested="$(printf '%s\n' "$output" | sed -n 's/^[[:space:]]*//; s/^tailscale up /tailscale up /p' | tail -n 1)"
    if [[ -n "$suggested" ]]; then
      log_info "Applying existing Tailscale non-default flags: $suggested"
      if [[ "$OS_FAMILY" == "linux" ]]; then
        if output="$(run_sudo bash -lc "$suggested" 2>&1)"; then
          return
        fi
      else
        if output="$(bash -lc "$suggested" 2>&1)"; then
          return
        fi
      fi
    fi
  fi

  if grep -q "does not run in sandboxed Tailscale GUI builds" <<<"$output"; then
    log_warn "Current macOS Tailscale build does not support --ssh. Falling back without --ssh."
    local fallback_cmd=(tailscale up)
    if [[ "${BOREALIS_NETWORKING_NONINTERACTIVE:-0}" == "1" ]]; then
      fallback_cmd+=(--accept-routes)
    fi
    if [[ "$OS_FAMILY" == "linux" ]]; then
      run_sudo "${fallback_cmd[@]}"
    else
      "${fallback_cmd[@]}"
    fi
    return
  fi

  log_error "$output"
  exit 1
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
