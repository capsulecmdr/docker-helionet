#!/bin/bash
set -euo pipefail

# -----------------------------------
# Config
# -----------------------------------
LOG_FILE="${1:-/tmp/host_worker.log}"

# Fixed queue location (your Docker volume path)
QUEUE_DIR="/var/lib/docker/volumes/docker-helionet_app_storage/_data"
QUEUE_FILE="${QUEUE_DIR}/host_worker.queue"

# -----------------------------------
# Logging helper
# -----------------------------------
log_host_worker() {
  local level="$1"; shift
  local msg="$*"

  local ts
  ts=$(date '+%Y-%m-%d %H:%M:%S')
  local env="${APP_ENV:-local}"

  # Laravel-style log line
  printf '[%s] %s.%s: %s {} []\n' "$ts" "$env" "$level" "$msg" >> "$LOG_FILE"
}

# -----------------------------------
# Start
# -----------------------------------
#log_host_worker INFO "host-worker starting..."

# -----------------------------------
# Ensure queue directory & file exist
# -----------------------------------
if [[ ! -d "$QUEUE_DIR" ]]; then
  log_host_worker WARNING "Queue directory missing: ${QUEUE_DIR}"
  mkdir -p "$QUEUE_DIR"
  log_host_worker INFO "Created queue directory: ${QUEUE_DIR}"
fi

if [[ ! -f "$QUEUE_FILE" ]]; then
  log_host_worker WARNING "Queue file missing: ${QUEUE_FILE}"
  touch "$QUEUE_FILE"
  echo "{\"host\":\"$(hostname -f)\",\"ip\":\"$(curl -s ifconfig.me)\",\"cwd\":\"$(pwd)\"}" > "$QUEUE_FILE"
  log_host_worker INFO "Created new queue file: ${QUEUE_FILE}"
fi

# -----------------------------------
# Process queue file line-by-line
# -----------------------------------
if [[ ! -s "$QUEUE_FILE" ]]; then
  : #log_host_worker INFO "Queue file is empty; nothing to process."
else
  #log_host_worker INFO "Processing commands from queue file: ${QUEUE_FILE}"

  # Continue loop as long as file still has lines
  while IFS= read -r line || [[ -n "$line" ]]; do

    # Remove the processed line BEFORE running it,
    # so even if execution fails the command won't rerun.
    tmp_queue="$(mktemp)"
    tail -n +2 "$QUEUE_FILE" > "$tmp_queue"    # drop the first line
    mv "$tmp_queue" "$QUEUE_FILE"

    # Skip empty or commented lines
    if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi

    #log_host_worker INFO "Executing queued command: ${line}"

    set +e
    output=$(bash -c "$line" 2>&1)
    status=$?
    set -e

    if [[ $status -eq 0 ]]; then
      log_host_worker INFO "Command succeeded (exit ${status}): ${line} | output: ${output}"
    else
      log_host_worker ERROR "Command failed (exit ${status}): ${line} | output: ${output}"
    fi

  done < "$QUEUE_FILE"

  #log_host_worker INFO "Queue processing complete."
fi

# -----------------------------------
# Trim log file to max 100 lines
# -----------------------------------
MAX_LOG_LINES=1000

current_lines=$(wc -l < "$LOG_FILE" || echo 0)

if (( current_lines > MAX_LOG_LINES )); then
  #log_host_worker INFO "Log file exceeds ${MAX_LOG_LINES} lines (${current_lines}). Trimming..."

  # Use a temp file to avoid issues when tailing to itself
  tmp_log="$(mktemp)"
  tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "$tmp_log"
  mv "$tmp_log" "$LOG_FILE"

  log_host_worker INFO "Log file trimmed to ${MAX_LOG_LINES} lines."
fi

#log_host_worker INFO "host-worker finished"
