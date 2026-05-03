#!/usr/bin/env bash
set -Eeuo pipefail

TAILSCALE_BIN="tailscale"
TAILSCALE_AUTH_TIMEOUT_SECONDS=600


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


tailscale_status_json() {
  resolve_tailscale_bin
  if [[ "$OS_FAMILY" == "linux" ]]; then
    run_sudo "$TAILSCALE_BIN" status --json
    return
  fi
  "$TAILSCALE_BIN" status --json
}


collect_tailscale_auth_url() {
  local status_json
  status_json="$(tailscale_status_json 2>/dev/null || true)"
  if [[ -z "$status_json" ]]; then
    printf ''
    return
  fi
  printf '%s' "$status_json" | jq -r '.AuthURL // empty'
}


extract_auth_url_from_text() {
  local text="$1"
  printf '%s\n' "$text" | grep -Eo 'https://login\.tailscale\.com[^[:space:]\\"]*' | head -n 1 || true
}


open_tailscale_auth_url() {
  local auth_url="$1"
  if [[ -z "$auth_url" ]]; then
    return
  fi

  if [[ "$OS_FAMILY" == "macos" ]] && is_command open; then
    open "$auth_url" >/dev/null 2>&1 || true
    return
  fi

  if is_command xdg-open; then
    xdg-open "$auth_url" >/dev/null 2>&1 || true
  fi
}


tailscale_is_authenticated() {
  local ts_identity
  local ts_device_id
  local ts_name
  local ts_user

  ts_identity="$(collect_tailscale_identity 2>/dev/null || true)"
  ts_device_id="$(printf '%s\n' "$ts_identity" | sed -n '1p')"
  ts_name="$(printf '%s\n' "$ts_identity" | sed -n '2p')"
  ts_user="$(printf '%s\n' "$ts_identity" | sed -n '3p')"

  if [[ -n "$ts_device_id" && -n "$ts_name" && -n "$ts_user" ]]; then
    return 0
  fi

  return 1
}


print_tailscale_auth_url() {
  local auth_url="$1"
  if [[ -z "$auth_url" ]]; then
    return
  fi
  log_info "Open this URL to continue auth: $auth_url"
}


retry_tailscale_auth_command() {
  if [[ "$OS_FAMILY" == "linux" && "$(id -u)" -ne 0 ]]; then
    printf 'sudo %q up --ssh' "$TAILSCALE_BIN"
    return
  fi

  printf '%q up --ssh' "$TAILSCALE_BIN"
}


tailscale_wait_for_auth_completion() {
  local initial_auth_url="$1"
  local last_auth_url="$initial_auth_url"
  local interval_seconds=5
  local start_epoch
  start_epoch="$(date +%s)"

  while true; do
    if tailscale_is_authenticated; then
      log_info "Auth completed, continuing enrollment"
      return
    fi

    local current_auth_url
    current_auth_url="$(collect_tailscale_auth_url)"
    if [[ -n "$current_auth_url" && "$current_auth_url" != "$last_auth_url" ]]; then
      last_auth_url="$current_auth_url"
      print_tailscale_auth_url "$last_auth_url"
      open_tailscale_auth_url "$last_auth_url"
    fi

    local current_epoch
    local elapsed_seconds
    current_epoch="$(date +%s)"
    elapsed_seconds="$((current_epoch - start_epoch))"
    if ((elapsed_seconds >= TAILSCALE_AUTH_TIMEOUT_SECONDS)); then
      log_error "Tailscale auth timed out after ${TAILSCALE_AUTH_TIMEOUT_SECONDS}s"
      if [[ -n "$last_auth_url" ]]; then
        log_error "Complete login here: $last_auth_url"
      fi
      log_error "Retry command: $(retry_tailscale_auth_command)"
      exit 1
    fi

    log_info "Waiting for tailnet auth to complete..."
    sleep "$interval_seconds"
  done
}


install_tailscale() {
  resolve_tailscale_bin

  if [[ "$OS_FAMILY" == "linux" ]]; then
    if tailscale_ready; then
      log_info "Tailscale already installed"
      return
    fi

    curl -fsSL https://tailscale.com/install.sh | run_sudo bash
    resolve_tailscale_bin

    if ! tailscale_ready; then
      log_error "Failed to install a usable Tailscale CLI on Linux"
      exit 1
    fi
    return
  fi

  if ! is_command brew; then
    log_error "Homebrew is required on macOS. Install from https://brew.sh"
    exit 1
  fi

  if brew list --cask tailscale-app >/dev/null 2>&1; then
    log_info "Tailscale app already installed"
  else
    if ! brew install --cask tailscale-app; then
      log_error "Failed to install Tailscale app cask on macOS"
      exit 1
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
    if tailscale_status_json >/dev/null 2>&1; then
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
  local output=""

  if [[ "$OS_FAMILY" == "linux" ]]; then
    if output="$(run_sudo "${cmd[@]}" 2>&1)"; then
      printf '%s' "$output"
      return
    fi
  else
    if output="$("${cmd[@]}" 2>&1)"; then
      printf '%s' "$output"
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
          printf '%s' "$output"
          return
        fi
      else
        if output="$(bash -lc "$suggested" 2>&1)"; then
          printf '%s' "$output"
          return
        fi
      fi
    fi
  fi

  if grep -q "does not run in sandboxed Tailscale GUI builds" <<<"$output"; then
    log_warn "Current macOS Tailscale build does not support --ssh. Falling back without --ssh."
    local fallback_cmd=("$TAILSCALE_BIN" up)

    if [[ "$OS_FAMILY" == "linux" ]]; then
      if ! output="$(run_sudo "${fallback_cmd[@]}" 2>&1)"; then
        log_error "$output"
        exit 1
      fi
    else
      if ! output="$("${fallback_cmd[@]}" 2>&1)"; then
        log_error "$output"
        exit 1
      fi
    fi

    printf '%s' "$output"
    return
  fi

  log_error "$output"
  exit 1
}


ensure_tailscale_authenticated() {
  log_info "Checking Tailscale auth state"

  if tailscale_is_authenticated; then
    log_info "Auth completed, continuing enrollment"
    return
  fi

  local auth_url
  auth_url="$(collect_tailscale_auth_url)"
  if [[ -n "$auth_url" ]]; then
    print_tailscale_auth_url "$auth_url"
    open_tailscale_auth_url "$auth_url"
    tailscale_wait_for_auth_completion "$auth_url"
    return
  fi

  local up_output
  up_output="$(tailscale_up_with_ssh)"
  if [[ -n "$up_output" ]]; then
    printf '%s\n' "$up_output"
  fi

  auth_url="$(extract_auth_url_from_text "$up_output")"
  if [[ -z "$auth_url" ]]; then
    auth_url="$(collect_tailscale_auth_url)"
  fi

  print_tailscale_auth_url "$auth_url"
  open_tailscale_auth_url "$auth_url"
  tailscale_wait_for_auth_completion "$auth_url"
}


collect_tailscale_identity() {
  local status_json
  status_json="$(tailscale_status_json)"

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
