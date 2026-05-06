#!/usr/bin/env bash
set -Eeuo pipefail

BOREALIS_CLIENT_ROOT="$HOME/borealis_networking/borealis_client"
DEFAULT_CLIENT_SUPERMASTER_URL="http://100.119.27.108:8080"


client_fetch_bootstrap() {
  local machine_id
  local ts_identity
  local ts_device_id
  local ts_name
  local ts_user

  machine_id="$(resolve_machine_id)"
  ts_identity="$(wait_for_tailscale_identity)"
  ts_device_id="$(printf '%s\n' "$ts_identity" | sed -n '1p')"
  ts_name="$(printf '%s\n' "$ts_identity" | sed -n '2p')"
  ts_user="$(printf '%s\n' "$ts_identity" | sed -n '3p')"

  local payload
  payload="$(jq -n \
    --arg machine_id "$machine_id" \
    --arg tailscale_device_id "$ts_device_id" \
    --arg tailscale_name "$ts_name" \
    --arg tailscale_user_login "$ts_user" \
    '{
      machine_id: $machine_id,
      tailscale_device_id: $tailscale_device_id,
      tailscale_name: $tailscale_name,
      tailscale_user_login: $tailscale_user_login
    }')"

  local response
  response="$(curl -fsSL -X POST "${BOREALIS_NETWORKING_SUPERMASTER_URL%/}/installer/bootstrap" \
    -H "Content-Type: application/json" \
    -H "x-actor: installer" \
    --data "$payload")"

  local version
  local artifact_download_path
  version="$(printf '%s' "$response" | jq -r '.version // empty')"
  artifact_download_path="$(printf '%s' "$response" | jq -r '.artifact_download_path // empty')"

  if [[ -z "$version" || -z "$artifact_download_path" ]]; then
    log_error "Failed to fetch bootstrap payload"
    printf '%s\n' "$response" >&2
    exit 1
  fi

  printf '%s\n%s\n' "$version" "$artifact_download_path"
}


install_client_runtime() {
  mkdir -p "$BOREALIS_CLIENT_ROOT"

  local bootstrap_payload
  local target_version
  local artifact_download_path
  local client_supermaster_url

  bootstrap_payload="$(client_fetch_bootstrap)"
  target_version="$(printf '%s\n' "$bootstrap_payload" | sed -n '1p')"
  artifact_download_path="$(printf '%s\n' "$bootstrap_payload" | sed -n '2p')"
  client_supermaster_url="${BOREALIS_NETWORKING_CLIENT_SUPERMASTER_URL:-$DEFAULT_CLIENT_SUPERMASTER_URL}"

  local tar_path
  tar_path="$(mktemp -t borealis-client-XXXXXX.tar.gz)"

  curl -fsSL "${BOREALIS_NETWORKING_SUPERMASTER_URL%/}${artifact_download_path}" -o "$tar_path"

  local active_dir="$BOREALIS_CLIENT_ROOT/active"
  local previous_dir="$BOREALIS_CLIENT_ROOT/previous"
  local new_dir="$BOREALIS_CLIENT_ROOT/new"
  local env_file="$BOREALIS_CLIENT_ROOT/.env"

  rm -rf "$new_dir"
  mkdir -p "$new_dir"
  tar -xzf "$tar_path" -C "$new_dir"
  rm -f "$tar_path"

  if [[ -f "$env_file" ]]; then
    if grep -q '^BOREALIS_CLIENT_VERSION=' "$env_file"; then
      local tmp_file
      tmp_file="$(mktemp)"
      sed "s/^BOREALIS_CLIENT_VERSION=.*/BOREALIS_CLIENT_VERSION=$target_version/" "$env_file" > "$tmp_file"
      mv "$tmp_file" "$env_file"
    else
      printf '\nBOREALIS_CLIENT_VERSION=%s\n' "$target_version" >> "$env_file"
    fi
  else
    cat > "$env_file" <<ENV
BOREALIS_CLIENT_HOST=0.0.0.0
BOREALIS_CLIENT_PORT=9091
BOREALIS_CLIENT_MACHINE_ID=$(resolve_machine_id)
BOREALIS_CLIENT_DEVICE_ID=${BOREALIS_NETWORKING_DEVICE_ID:-$(resolve_machine_id)}
BOREALIS_CLIENT_ROOT=$BOREALIS_CLIENT_ROOT
BOREALIS_CLIENT_SUPERMASTER_URL=${client_supermaster_url}
BOREALIS_CLIENT_REQUEST_TIMEOUT_SECONDS=30
BOREALIS_CLIENT_VERIFY_PATH=/rollouts/verify-supermaster
BOREALIS_CLIENT_REPORT_PATH=/rollouts/client-report
BOREALIS_CLIENT_VERSION=$target_version
BOREALIS_CLIENT_SERVICE_NAME=borealis_client
BOREALIS_CLIENT_ARTIFACT_VERIFY_KEY=${BOREALIS_CLIENT_ARTIFACT_VERIFY_KEY:-}
BOREALIS_CLIENT_DESIRED_STATE_PATH=/proxy/desired-state
BOREALIS_CLIENT_PROXY_STATUS_PATH=/proxy/routes/status
BOREALIS_CLIENT_PROXY_PROBE_URL=https://1.1.1.1
BOREALIS_CLIENT_PROXY_DNS_SERVER_ADDRESS=1.1.1.1
BOREALIS_CLIENT_PROXY_WATCHDOG_INTERVAL_SECONDS=30
BOREALIS_CLIENT_PROXY_WATCHDOG_FAIL_THRESHOLD=3
BOREALIS_CLIENT_PROXY_TUN_FAIL_MODE=keep_blocking
BOREALIS_CLIENT_SING_BOX_BINARY_PATH=$BOREALIS_CLIENT_ROOT/bin/sing-box
BOREALIS_CLIENT_SHELL_LISTEN_HOST=127.0.0.1
BOREALIS_CLIENT_SHELL_SOCKS_PORT=10808
BOREALIS_CLIENT_SHELL_HTTP_PORT=10809
BOREALIS_CLIENT_TUN_INTERFACE_NAME=borealis-tun
BOREALIS_CLIENT_TUN_MTU=1500
ENV
  fi

  rm -rf "$previous_dir"
  if [[ -d "$active_dir" ]]; then
    mv "$active_dir" "$previous_dir"
  fi
  mv "$new_dir" "$active_dir"
  ln -sf "$env_file" "$active_dir/.env"

  if [[ -x "$active_dir/scripts/setup_node.sh" ]]; then
    BOREALIS_CLIENT_ROOT="$BOREALIS_CLIENT_ROOT" \
    BOREALIS_CLIENT_SERVICE_NAME="borealis_client" \
    BOREALIS_CLIENT_VERSION="$target_version" \
    "$active_dir/scripts/setup_node.sh" --root "$BOREALIS_CLIENT_ROOT" --version "$target_version"
  fi

  log_info "Installed borealis client runtime version $target_version"
}
