#!/bin/bash
set -euo pipefail

# -----------------------------------
# Config
# -----------------------------------
LOG_FILE="${1:-/tmp/host_worker.log}"
WORKING_DIR="${2:-/tmp}"

# Fixed queue location (your Docker volume path)
QUEUE_DIR="/var/lib/docker/volumes/docker-helionet_app_storage/_data"
QUEUE_FILE="${QUEUE_DIR}/host_worker.queue"

# Simple lock file to prevent concurrent runs
LOCK_FILE="/tmp/host_worker.lock"

# Max log lines
MAX_LOG_LINES=1000

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
# Acquire lock (non-blocking)
# If already locked, exit silently
# -----------------------------------
if ( set -o noclobber; echo "$$" > "$LOCK_FILE" ) 2>/dev/null; then
  # We own the lock; ensure it is released on exit
  trap 'rm -f "$LOCK_FILE"' EXIT
else
  # Another instance is running; exit quietly
  exit 0
fi

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

  # Seed the queue with a default command showing host | ip | cwd
  printf 'echo "%s | %s | %s"\n' \
    "$(hostname -f 2>/dev/null || hostname)" \
    "$(curl -s ifconfig.me || echo unknown_ip)" \
    "$(pwd)" \
    > "$QUEUE_FILE"

  log_host_worker INFO "Created new queue file: ${QUEUE_FILE}"
fi

# -----------------------------------
# Process queue file line-by-line (FIFO)
# -----------------------------------
if [[ -s "$QUEUE_FILE" ]]; then
  #log_host_worker INFO "Processing commands from queue file: ${QUEUE_FILE}"

  while :; do
    # Stop if file is now empty
    if [[ ! -s "$QUEUE_FILE" ]]; then
      break
    fi

    # Read the first line only
    line="$(head -n 1 "$QUEUE_FILE" || true)"

    # Remove the first line from the queue file *before* executing
    tmp_queue="$(mktemp)"
    tail -n +2 "$QUEUE_FILE" > "$tmp_queue" 2>/dev/null || true
    mv "$tmp_queue" "$QUEUE_FILE"

    # Skip empty or commented lines
    if [[ -z "$line" ]] || [[ "$line" =~ ^[[:space:]]*# ]]; then
      continue
    fi

    #log_host_worker INFO "Executing queued command: ${line}"

    set +e
    output=$(bash -c "cd \"$WORKING_DIR\" && $line" 2>&1)
    status=$?
    set -e

    if [[ $status -eq 0 ]]; then
      log_host_worker INFO "Command succeeded (exit ${status}): ${line} | output: ${output}"
    else
      log_host_worker ERROR "Command failed (exit ${status}): ${line} | output: ${output}"
    fi

    # 3 second delay between commands
    sleep 3
  done

  #log_host_worker INFO "Queue processing complete."
else
  : #log_host_worker INFO "Queue file is empty; nothing to process."
fi

# -----------------------------------
# Trim log file to max N lines
# -----------------------------------
current_lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)

if (( current_lines > MAX_LOG_LINES )); then
  #log_host_worker INFO "Log file exceeds ${MAX_LOG_LINES} lines (${current_lines}). Trimming..."
  tmp_log="$(mktemp)"
  tail -n "$MAX_LOG_LINES" "$LOG_FILE" > "$tmp_log"
  mv "$tmp_log" "$LOG_FILE"
  log_host_worker INFO "Log file trimmed to ${MAX_LOG_LINES} lines."
fi

#log_host_worker INFO "host-worker finished"
