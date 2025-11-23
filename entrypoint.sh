#!/usr/bin/env bash
set -e

ROLE="${HELIONET_ROLE:-web}"  # default to web if not set
LOCK_FILE="/var/www/html/storage/packages/bootstrap.lock"

echo "[HelioNET | Entry] Container role: $ROLE"

run_bootstrap() {
    mkdir -p /var/www/html/storage/packages

    if [ -f "$LOCK_FILE" ]; then
        echo "[HelioNET | Packages] Lock file found, skipping bootstrap."
        return
    fi

    echo "[HelioNET | Packages] Running dynamic package bootstrap..."

    php /var/www/html/scripts/bootstrap-packages.php \
    /var/www/html/storage/packages/packages.jsonl \
    /var/www/html

    touch "$LOCK_FILE"
    echo "[HelioNET | Packages] Bootstrap complete; lock file created."
}

# Only the web role should ever run the bootstrap
if [ "$ROLE" = "web" ]; then
    echo "[HelioNET | Entry] Web role detected; running package bootstrap..."
    run_bootstrap
else
    echo "[HelioNET | Entry] Non-web role ($ROLE); skipping package bootstrap."
fi

echo "[HelioNET | Runtime] Starting: $*"
exec "$@"
