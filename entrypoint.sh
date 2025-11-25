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

ensure_horizon_admin_middleware() {
    local CONFIG_FILE="/var/www/html/config/horizon.php"

    # If the config hasn't been published yet, publish it once
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[HelioNET | Horizon] Config not found; publishing..."
        php artisan vendor:publish \
            --provider="Laravel\\Horizon\\HorizonServiceProvider" \
            --tag=config --force || true
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[HelioNET | Horizon] Config still missing; skipping middleware wiring."
        return
    fi

    echo "[HelioNET | Horizon] Ensuring 'admin' middleware is registered..."

    php <<'PHP'
<?php
$file = '/var/www/html/config/horizon.php';

if (!file_exists($file)) {
    exit(0);
}

$config = include $file;

// Default to existing middleware or ['web'] if missing
$middleware = $config['middleware'] ?? ['web'];

// If 'admin' is already present, do nothing (idempotent)
if (in_array('admin', $middleware, true)) {
    exit(0);
}

$middleware[] = 'admin';
$config['middleware'] = $middleware;

$export = "<?php\n\nreturn " . var_export($config, true) . ";\n";
file_put_contents($file, $export);
PHP
}

ensure_logviewer_apache_logs() {
    local CONFIG_FILE="/var/www/html/config/log-viewer.php"
    local PATTERN="/var/log/apache2/helionet-*.log"

    # If the config hasn't been published yet, publish it once
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[HelioNET | LogViewer] Config not found; publishing..."
        php artisan vendor:publish \
            --provider="Opcodes\\LogViewer\\LogViewerServiceProvider" \
            --tag=config --force || true
    fi

    if [ ! -f "$CONFIG_FILE" ]; then
        echo "[HelioNET | LogViewer] Config still missing; skipping Apache/middleware wiring."
        return
    fi

    echo "[HelioNET | LogViewer] Ensuring Apache pattern and admin middleware are registered..."

    php <<'PHP'
<?php
$file    = '/var/www/html/config/log-viewer.php';
$pattern = "/var/log/apache2/helionet-*.log";

if (!file_exists($file)) {
    exit(0);
}

$code = file_get_contents($file);
if ($code === false) {
    exit(0);
}

/**
 * 1) Ensure Apache include_files entry exists
 */
if (strpos($code, $pattern) === false) {
    $needle = "'include_files' => [";
    $pos    = strpos($code, $needle);

    if ($pos !== false) {
        $insert = $needle . "\n        '$pattern' => 'Apache (HelioNET)',";
        $code   = substr_replace($code, $insert, $pos, strlen($needle));
    }
}

/**
 * 2) Ensure middleware includes web, auth, admin
 *    We assume the default `'middleware' => ['web'],` and upgrade it.
 */
$search  = "'middleware' => ['web'],";
$replace = "'middleware' => ['web', 'auth', 'admin'],";

// Only replace if we haven't already upgraded
if (strpos($code, $replace) === false) {
    $code = str_replace($search, $replace, $code);
}

file_put_contents($file, $code);
PHP
}


# Only the web role should run bootstrap + log-viewer wiring
if [ "$ROLE" = "web" ]; then
    echo "[HelioNET | Entry] Web role detected; running package bootstrap..."
    run_bootstrap
    ensure_logviewer_apache_logs
    ensure_horizon_admin_middleware
else
    echo "[HelioNET | Entry] Non-web role ($ROLE); skipping bootstrap/log-viewer config."
fi

php artisan optimize:clear || true
# optional: re-cache if you want
php artisan config:cache || true
php artisan route:cache || true
php artisan view:cache  || true

echo "[HelioNET | Runtime] Starting: $*"
exec "$@"
