#!/usr/bin/env bash
set -Eeuo pipefail

DEFAULT_SUPERMASTER_URL="http://193.124.182.91"
BOREALIS_NETWORKING_STATE_DIR="$HOME/borealis_networking/borealis_client/state"


resolve_machine_id() {
  if [[ "$OS_FAMILY" == "linux" && -f /etc/machine-id ]]; then
    cat /etc/machine-id
    return
  fi

  if [[ "$OS_FAMILY" == "macos" ]]; then
    ioreg -rd1 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformUUID/{print $(NF-1)}'
    return
  fi

  hostname
}


resolve_hostname() {
  hostname
}


resolve_os_name() {
  local uname_out
  uname_out="$(uname -s | tr '[:upper:]' '[:lower:]')"
  printf '%s' "$uname_out"
}


resolve_arch() {
  uname -m
}


enroll_start() {
  export BOREALIS_NETWORKING_SUPERMASTER_URL="${BOREALIS_NETWORKING_SUPERMASTER_URL:-$DEFAULT_SUPERMASTER_URL}"

  local role
  role="${BOREALIS_NETWORKING_ROLE_REQUEST:-}"
  if [[ -z "$role" ]]; then
    while true; do
      printf 'Role for this device (master/slave): ' >/dev/tty
      read -r role </dev/tty
      role="$(printf '%s' "$role" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz')"
      if [[ "$role" == "master" || "$role" == "slave" ]]; then
        break
      fi
      printf 'Invalid — enter master or slave\n' >/dev/tty
      role=""
    done
  fi
  if [[ "$role" != "master" && "$role" != "slave" ]]; then
    log_error "BOREALIS_NETWORKING_ROLE_REQUEST must be master or slave"
    exit 1
  fi

  local machine_id
  local hostname_value
  local os_name
  local arch_value

  machine_id="$(resolve_machine_id)"
  hostname_value="$(resolve_hostname)"
  os_name="$(resolve_os_name)"
  arch_value="$(resolve_arch)"

  local payload
  payload="$(jq -n \
    --arg machine_id "$machine_id" \
    --arg hostname "$hostname_value" \
    --arg os_name "$os_name" \
    --arg arch "$arch_value" \
    --arg requested_role "$role" \
    '{machine_id: $machine_id, hostname: $hostname, os_name: $os_name, arch: $arch, requested_role: $requested_role}')"

  local response
  response="$(curl -fsSL -X POST "${BOREALIS_NETWORKING_SUPERMASTER_URL%/}/enroll/start" \
    -H "Content-Type: application/json" \
    -H "x-actor: installer" \
    --data "$payload")"

  local enrollment_token
  enrollment_token="$(printf '%s' "$response" | jq -r '.enrollment_token // empty')"

  if [[ -z "$enrollment_token" ]]; then
    log_error "Failed to get enrollment token from super-master"
    printf '%s\n' "$response" >&2
    exit 1
  fi

  printf '%s' "$enrollment_token"
}


enroll_complete() {
  local enrollment_token="$1"

  local ts_identity
  local ts_device_id
  local ts_name
  local ts_user

  ts_identity="$(wait_for_tailscale_identity)"
  ts_device_id="$(printf '%s\n' "$ts_identity" | sed -n '1p')"
  ts_name="$(printf '%s\n' "$ts_identity" | sed -n '2p')"
  ts_user="$(printf '%s\n' "$ts_identity" | sed -n '3p')"
  capture_sudo_credentials

  local payload
  payload="$(jq -n \
    --arg enrollment_token "$enrollment_token" \
    --arg tailscale_device_id "$ts_device_id" \
    --arg tailscale_name "$ts_name" \
    --arg tailscale_user_login "$ts_user" \
    --arg sudo_username "${BOREALIS_NETWORKING_SUDO_USERNAME:-}" \
    --arg sudo_password "${BOREALIS_NETWORKING_SUDO_PASSWORD:-}" \
    '{
      enrollment_token: $enrollment_token,
      tailscale_device_id: $tailscale_device_id,
      tailscale_name: $tailscale_name,
      tailscale_user_login: $tailscale_user_login,
      sudo_username: (if $sudo_username | length > 0 then $sudo_username else null end),
      sudo_password: (if $sudo_password | length > 0 then $sudo_password else null end)
    }')"

  local response
  response="$(curl -fsSL -X POST "${BOREALIS_NETWORKING_SUPERMASTER_URL%/}/enroll/complete" \
    -H "Content-Type: application/json" \
    -H "x-actor: installer" \
    --data "$payload")"

  local assigned_role
  local device_id
  assigned_role="$(printf '%s' "$response" | jq -r '.assigned_role // empty')"
  device_id="$(printf '%s' "$response" | jq -r '.id // empty')"
  if [[ -z "$assigned_role" ]]; then
    log_error "Failed to resolve assigned role from enrollment response"
    printf '%s\n' "$response" >&2
    exit 1
  fi

  export BOREALIS_NETWORKING_ASSIGNED_ROLE="$assigned_role"
  export BOREALIS_NETWORKING_DEVICE_ID="$device_id"
  mkdir -p "$BOREALIS_NETWORKING_STATE_DIR"
  printf '%s\n' "$assigned_role" > "$BOREALIS_NETWORKING_STATE_DIR/assigned_role"
  printf '%s\n' "$device_id" > "$BOREALIS_NETWORKING_STATE_DIR/device_id"
}


capture_sudo_credentials() {
  if [[ -z "${BOREALIS_NETWORKING_SUDO_USERNAME:-}" ]]; then
    local default_username
    default_username="$(id -un)"
    printf 'Device sudo username [%s]: ' "$default_username" >/dev/tty
    read -r BOREALIS_NETWORKING_SUDO_USERNAME </dev/tty
    BOREALIS_NETWORKING_SUDO_USERNAME="${BOREALIS_NETWORKING_SUDO_USERNAME:-$default_username}"
    export BOREALIS_NETWORKING_SUDO_USERNAME
  fi

  if [[ -z "${BOREALIS_NETWORKING_SUDO_PASSWORD:-}" ]]; then
    printf 'Sudo password for %s: ' "$BOREALIS_NETWORKING_SUDO_USERNAME" >/dev/tty
    stty -echo </dev/tty
    read -r BOREALIS_NETWORKING_SUDO_PASSWORD </dev/tty
    stty echo </dev/tty
    printf '\n' >/dev/tty
    export BOREALIS_NETWORKING_SUDO_PASSWORD
  fi
}
