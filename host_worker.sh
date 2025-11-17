#!/bin/bash
set -euo pipefail

LOG_FILE="${1:-/tmp/host_worker.log}"

log_host_worker() {
  local level="$1"; shift
  local msg="$*"

  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  local env="${APP_ENV:-local}"

  # Laravel-style log line
  printf '[%s] %s.%s: %s {} []\n' "$ts" "$env" "$level" "$msg" >> "$LOG_FILE"
}

log_host_worker INFO "host-worker starting..."

log_host_worker INFO "host-worker finished"
