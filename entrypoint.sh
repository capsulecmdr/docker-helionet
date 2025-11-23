#!/usr/bin/env bash
set -e

echo "[HelioNET | Packages] Running dynamic package bootstrap..."

# Ensure storage directory exists
mkdir -p /var/www/html/storage/packages

# Run the file-only dynamic loader
php /var/www/html/scripts/bootstrap-packages.php \
    /var/www/html/storage/packages/packages.jsonl \
    /var/www/html

echo "[HelioNET | Packages] Bootstrap complete."

# Optional: do runtime artisan stuff here if you want
# (Only if your codebase is stable enough that artisan can boot)
# php artisan migrate --force || true
# php artisan config:cache || true
# php artisan route:cache || true

echo "[HelioNET | Runtime] Starting supervisord..."
exec "$@"
