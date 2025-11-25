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

    # touch "$LOCK_FILE"
    # echo "[HelioNET | Packages] Bootstrap complete; lock file created."
}

ensure_logviewer_apache_logs() {
    local CONFIG_FILE="/var/www/html/config/log-viewer.php"

    # If the config hasn't been published yet, publish it once
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[HelioNET | LogViewer] Config not found; publishing..."
        php artisan vendor:publish \
            --provider="Opcodes\\LogViewer\\LogViewerServiceProvider" \
            --tag=config --force || true
    fi

    echo "[HelioNET | LogViewer] Ensuring Apache log pattern is registered..."

    # Run a small inline PHP script to update config/log-viewer.php idempotently
    php <<'PHP'
<?php
$file = '/var/www/html/config/log-viewer.php';
if (!file_exists($file)) {
    // Nothing to do
    exit(0);
}

$cfg = include $file;
$pattern = '/var/log/apache2/helionet-*.log';

if (!isset($cfg['include_files']) || !is_array($cfg['include_files'])) {
    $cfg['include_files'] = [];
}

$found = false;
foreach ($cfg['include_files'] as $key => $value) {
    // handle both numeric array entries and "path => label" entries
    if ($key === $pattern || $value === $pattern) {
        $found = true;
        break;
    }
}

if (!$found) {
    // Add with a nice label for the UI
    $cfg['include_files'][$pattern] = 'Apache (HelioNET)';
    file_put_contents(
        $file,
        "<?php\n\nreturn " . var_export($cfg, true) . ";\n"
    );
}
PHP
}

# Only the web role should run bootstrap + log-viewer wiring
if [ "$ROLE" = "web" ]; then
    echo "[HelioNET | Entry] Web role detected; running package bootstrap..."
    run_bootstrap
    ensure_logviewer_apache_logs
else
    echo "[HelioNET | Entry] Non-web role ($ROLE); skipping bootstrap/log-viewer config."
fi

echo "[HelioNET | Runtime] Starting: $*"
exec "$@"
