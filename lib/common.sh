#!/usr/bin/env bash
set -Eeuo pipefail

log_step() {
  printf '\n[borealis_networking] %s\n' "$*"
}

log_info() {
  printf '[borealis_networking] %s\n' "$*"
}

log_warn() {
  printf '[borealis_networking][warn] %s\n' "$*" >&2
}

log_error() {
  printf '[borealis_networking][error] %s\n' "$*" >&2
}

is_command() {
  command -v "$1" >/dev/null 2>&1
}

run_sudo() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
    return
  fi

  if is_command sudo; then
    sudo "$@"
    return
  fi

  log_error "sudo is required to run: $*"
  exit 1
}

require_env_or_prompt() {
  local var_name="$1"
  local prompt_label="$2"
  local hidden="${3:-0}"

  if [[ -n "${!var_name:-}" ]]; then
    return
  fi

  if [[ "$hidden" == "1" ]]; then
    read -r -s -p "$prompt_label: " value
    printf '\n'
  else
    read -r -p "$prompt_label: " value
  fi

  if [[ -z "$value" ]]; then
    log_error "Missing value for $var_name"
    exit 1
  fi

  export "$var_name=$value"
}
