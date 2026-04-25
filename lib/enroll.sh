#!/usr/bin/env bash
set -Eeuo pipefail


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
  require_env_or_prompt "BOREALIS_NETWORKING_SUPERMASTER_URL" "Super-master URL (e.g. https://nikiniki.com:8080)"
  require_env_or_prompt "BOREALIS_NETWORKING_API_TOKEN" "Super-master API token" 1

  local role
  role="${BOREALIS_NETWORKING_ROLE_REQUEST:-slave}"
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
    -H "x-api-token: $BOREALIS_NETWORKING_API_TOKEN" \
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

  local payload
  payload="$(jq -n \
    --arg enrollment_token "$enrollment_token" \
    --arg tailscale_device_id "$ts_device_id" \
    --arg tailscale_name "$ts_name" \
    --arg tailscale_user_login "$ts_user" \
    '{
      enrollment_token: $enrollment_token,
      tailscale_device_id: $tailscale_device_id,
      tailscale_name: $tailscale_name,
      tailscale_user_login: $tailscale_user_login
    }')"

  curl -fsSL -X POST "${BOREALIS_NETWORKING_SUPERMASTER_URL%/}/enroll/complete" \
    -H "Content-Type: application/json" \
    -H "x-api-token: $BOREALIS_NETWORKING_API_TOKEN" \
    -H "x-actor: installer" \
    --data "$payload" >/dev/null
}
