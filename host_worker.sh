#!/bin/bash
set -euo pipefail

LOG_FILE="${1:-/tmp/host_worker.log}"

echo "[$(date --iso-8601=seconds)] host_worker.sh starting..." >> "$LOG_FILE"

while true; do
    # === Your actual work goes here ===
    echo "[$(date --iso-8601=seconds)] Running host worker task..." >> "$LOG_FILE"
    
    # Example: call a PHP script, Docker command, etc.
    # php /opt/seat-helionet/artisan some:command >> "$LOG_FILE" 2>&1

    #sleep 30
done
