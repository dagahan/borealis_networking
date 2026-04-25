#!/usr/bin/env bash
set -Eeuo pipefail

TAILSCALE_BIN="tailscale"


resolve_tailscale_bin() {
  local candidates=(
    "tailscale"
    "/opt/homebrew/bin/tailscale"
    "/usr/local/bin/tailscale"
    "/Applications/Tailscale.app/Contents/MacOS/tailscale"
  )

  for candidate in "${candidates[@]}"; do
    if [[ "$candidate" == "tailscale" ]]; then
      if is_command tailscale && tailscale version >/dev/null 2>&1; then
        TAILSCALE_BIN="tailscale"
        return
      fi
      continue
    fi

    if [[ -x "$candidate" ]] && "$candidate" version >/dev/null 2>&1; then
      TAILSCALE_BIN="$candidate"
      return
    fi
  done

  TAILSCALE_BIN="tailscale"
}


tailscale_ready() {
  "$TAILSCALE_BIN" version >/dev/null 2>&1
}


install_tailscale() {
  resolve_tailscale_bin
  if tailscale_ready; then
    log_info "Tailscale already installed"
    return
  fi

  if [[ "$OS_FAMILY" == "linux" ]]; then
    curl -fsSL https://tailscale.com/install.sh | run_sudo bash
    resolve_tailscale_bin
    return
  fi

  if ! is_command brew; then
    log_error "Homebrew is required on macOS. Install from https://brew.sh"
    exit 1
  fi

  if brew list --cask tailscale-app >/dev/null 2>&1; then
    if ! brew reinstall --cask tailscale-app; then
      log_warn "Could not reinstall tailscale-app cask. Trying formula fallback."
      brew install tailscale >/dev/null 2>&1 || true
    fi
  else
    if ! brew install --cask tailscale-app; then
      log_warn "Could not install tailscale-app cask. Trying formula fallback."
      brew install tailscale >/dev/null 2>&1 || true
    fi
  fi

  resolve_tailscale_bin
  if ! tailscale_ready; then
    log_error "Failed to install a usable Tailscale CLI on macOS"
    exit 1
  fi
}


ensure_tailscaled_running() {
  resolve_tailscale_bin

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

  if is_command open; then
    open -a Tailscale || true
  fi

  local timeout_seconds=40
  local interval_seconds=2
  local start_epoch
  start_epoch="$(date +%s)"

  while true; do
    if "$TAILSCALE_BIN" status --json >/dev/null 2>&1; then
      break
    fi

    local current_epoch
    local elapsed_seconds
    current_epoch="$(date +%s)"
    elapsed_seconds="$((current_epoch - start_epoch))"
    if ((elapsed_seconds >= timeout_seconds)); then
      log_error "Tailscale backend is not ready on macOS"
      exit 1
    fi

    sleep "$interval_seconds"
  done
}


tailscale_up_with_ssh() {
  local cmd=("$TAILSCALE_BIN" up --ssh)
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
    local fallback_cmd=("$TAILSCALE_BIN" up)
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
  resolve_tailscale_bin
  if [[ "$OS_FAMILY" == "linux" ]]; then
    status_json="$(run_sudo "$TAILSCALE_BIN" status --json)"
  else
    status_json="$("$TAILSCALE_BIN" status --json)"
  fi

  local ts_device_id
  local ts_name
  local ts_user

  ts_device_id="$(printf '%s' "$status_json" | jq -r '.Self.ID // empty')"
  ts_name="$(printf '%s' "$status_json" | jq -r '.Self.DNSName // .Self.HostName // empty')"
  ts_user="$(printf '%s' "$status_json" | jq -r '.Self.UserProfile.LoginName // empty')"

  printf '%s\n%s\n%s\n' "$ts_device_id" "$ts_name" "$ts_user"
}


wait_for_tailscale_identity() {
  local timeout_seconds=300
  local interval_seconds=5
  local start_epoch
  start_epoch="$(date +%s)"

  while true; do
    local ts_identity
    local ts_device_id
    local ts_name
    local ts_user
    ts_identity="$(collect_tailscale_identity)"
    ts_device_id="$(printf '%s\n' "$ts_identity" | sed -n '1p')"
    ts_name="$(printf '%s\n' "$ts_identity" | sed -n '2p')"
    ts_user="$(printf '%s\n' "$ts_identity" | sed -n '3p')"

    if [[ -n "$ts_device_id" && -n "$ts_name" && -n "$ts_user" ]]; then
      printf '%s\n%s\n%s\n' "$ts_device_id" "$ts_name" "$ts_user"
      return
    fi

    local current_epoch
    local elapsed_seconds
    current_epoch="$(date +%s)"
    elapsed_seconds="$((current_epoch - start_epoch))"
    if ((elapsed_seconds >= timeout_seconds)); then
      log_error "Tailscale identity is not ready. If device approval is enabled, approve this device and rerun installer."
      exit 1
    fi

    log_info "Waiting for device to become fully authenticated in tailnet..."
    sleep "$interval_seconds"
  done
}
