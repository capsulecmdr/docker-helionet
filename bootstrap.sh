#!/usr/bin/env bash
set -euo pipefail

echo "[helionet] bootstrap starting"

# 1. Ensure .env exists
if [[ ! -f .env && -f .env.example ]]; then
  cp .env.example .env
  echo "[helionet] copied .env.example to .env"
fi

if [[ ! -f .env ]]; then
  echo "[helionet] ERROR: .env not found and .env.example missing."
  exit 1
fi

# 2. Generate DB password if placeholder present
if grep -q "CHANGEME_DB_PASSWORD" .env; then
  DB_PASS="$(openssl rand -base64 18 | tr -d '=+/')"
  sed -i "s/CHANGEME_DB_PASSWORD/${DB_PASS}/" .env
  echo "[helionet] generated random DB_PASSWORD"
fi

# 3. Generate APP_KEY if insecure
if grep -q "^APP_KEY=insecure" .env || ! grep -q "^APP_KEY=" .env; then
  APP_KEY=$(php -r "echo base64_encode(random_bytes(32));")
  sed -i "s|^APP_KEY=.*|APP_KEY=base64:${APP_KEY}|" .env
  echo "[helionet] generated APP_KEY"
fi

# 4. Bring up the stack
echo "[helionet] starting docker compose stack"
docker compose up -d

echo "[helionet] bootstrap complete. Visit ${APP_URL:-http://localhost:8080}"
