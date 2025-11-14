#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/capsulecmdr/docker-helionet.git"
REPO_DIR="docker-helionet"

APP_REPO_URL="https://github.com/capsulecmdr/helionet.git"
APP_DIR="../helionet"

echo "[helionet] bootstrap starting"

########################################
# 0. Ensure docker is available
########################################
if ! command -v docker >/dev/null 2>&1; then
  echo "[helionet] ERROR: docker is not installed or not in PATH."
  exit 1
fi

# Prefer 'docker compose' but fall back to 'docker-compose'
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo "[helionet] ERROR: neither 'docker compose' nor 'docker-compose' is available."
  exit 1
fi

# Helper to run commands in the web container as the helios user
run_in_web() {
  # usage: run_in_web "command here"
  $COMPOSE_CMD exec -T -u helios web sh -lc "$*"
}

########################################
# 1. Are we already inside the repo?
########################################

IN_REPO=0

if [[ -d .git ]] || [[ -f docker-compose.yml ]] || [[ -f docker-compose.yaml ]]; then
  IN_REPO=1
fi

if [[ "$IN_REPO" -eq 0 ]]; then
  echo "[helionet] no existing docker-helionet checkout detected in: $(pwd)"

  if [[ -d "$REPO_DIR" ]]; then
    echo "[helionet] found existing '$REPO_DIR' directory, using that"
  else
    echo "[helionet] cloning $REPO_URL into '$REPO_DIR'..."
    git clone "$REPO_URL" "$REPO_DIR"
  fi

  cd "$REPO_DIR"
  echo "[helionet] now in repo directory: $(pwd)"
else
  echo "[helionet] repo detected in $(pwd)"
fi

########################################
# 2. Ensure docker-helionet .env exists
########################################

if [[ ! -f .env && -f .env.example ]]; then
  cp .env.example .env
  echo "[helionet] copied .env.example to .env (docker stack env)"
fi

if [[ ! -f .env ]]; then
  echo "[helionet] ERROR: .env not found and .env.example missing in docker-helionet."
  exit 1
fi

########################################
# 3. Generate DB password if placeholder is present
########################################

if grep -q "CHANGEME_DB_PASSWORD" .env; then
  echo "[helionet] generating random DB password"
  DB_PASS="$(openssl rand -base64 18 | tr -d '=+/')"
  sed -i "s/CHANGEME_DB_PASSWORD/${DB_PASS}/" .env
  echo "[helionet] DB password updated in .env"
else
  echo "[helionet] DB password already set, leaving docker-helionet .env as-is"
fi

########################################
# 4. Ensure application repo exists at ../helionet
########################################

if [[ -d "$APP_DIR/.git" ]]; then
  echo "[helionet] application repo already present at '$APP_DIR'"
else
  if [[ -d "$APP_DIR" ]]; then
    echo "[helionet] WARNING: '$APP_DIR' exists but is not a git repo. Skipping clone."
  else
    echo "[helionet] cloning helionet application into '$APP_DIR'..."
    git clone "$APP_REPO_URL" "$APP_DIR"
  fi
fi

########################################
# 5. Ensure application .env exists (Laravel)
########################################

APP_ENV_FILE="$APP_DIR/.env"
APP_ENV_EXAMPLE="$APP_DIR/.env.example"

if [[ ! -f "$APP_ENV_FILE" && -f "$APP_ENV_EXAMPLE" ]]; then
  cp "$APP_ENV_EXAMPLE" "$APP_ENV_FILE"
  echo "[helionet] copied app .env.example to .env"
fi

if [[ ! -f "$APP_ENV_FILE" ]]; then
  echo "[helionet] WARNING: app .env not found at '$APP_ENV_FILE'."
  echo "[helionet]          key:generate will fail until you create it."
fi

########################################
# 6. Sync DB_* values from docker .env into app .env
########################################

if [[ -f "$APP_ENV_FILE" ]]; then
  echo "[helionet] syncing DB settings into app .env"

  # Helper: set or append a key=value in a .env file
  sync_env_key() {
    local key="$1"
    local value="$2"
    local file="$3"

    # Escape / and & for sed
    local esc_value
    esc_value=$(printf '%s\n' "$value" | sed 's/[\/&]/\\&/g')

    if grep -q "^${key}=" "$file"; then
      sed -i "s/^${key}=.*/${key}=${esc_value}/" "$file"
    else
      echo "${key}=${value}" >> "$file"
    fi
  }

  # Pull DB_* from docker-helionet/.env
  DOCKER_DB_HOST="$(grep '^DB_HOST=' .env | cut -d '=' -f2- || true)"
  DOCKER_DB_DATABASE="$(grep '^DB_DATABASE=' .env | cut -d '=' -f2- || true)"
  DOCKER_DB_USERNAME="$(grep '^DB_USERNAME=' .env | cut -d '=' -f2- || true)"
  DOCKER_DB_PASSWORD="$(grep '^DB_PASSWORD=' .env | cut -d '=' -f2- || true)"

  # Apply to app .env if values are present
  [[ -n "$DOCKER_DB_HOST" ]] && sync_env_key "DB_HOST" "$DOCKER_DB_HOST" "$APP_ENV_FILE"
  [[ -n "$DOCKER_DB_DATABASE" ]] && sync_env_key "DB_DATABASE" "$DOCKER_DB_DATABASE" "$APP_ENV_FILE"
  [[ -n "$DOCKER_DB_USERNAME" ]] && sync_env_key "DB_USERNAME" "$DOCKER_DB_USERNAME" "$APP_ENV_FILE"
  [[ -n "$DOCKER_DB_PASSWORD" ]] && sync_env_key "DB_PASSWORD" "$DOCKER_DB_PASSWORD" "$APP_ENV_FILE"

  echo "[helionet] DB_* values synced from docker-helionet/.env to app .env"
else
  echo "[helionet] WARNING: cannot sync DB settings; app .env not found."
fi

########################################
# 7. Bring up the stack cleanly
########################################

echo "[helionet] stopping any existing stack (if present)..."
$COMPOSE_CMD down --remove-orphans || true

echo "[helionet] pulling images..."
$COMPOSE_CMD pull

echo "[helionet] starting containers..."
$COMPOSE_CMD up -d

echo "[helionet] waiting for db container to be ready..."
until docker compose exec db mysqladmin ping -h"db" --silent; do
  sleep 1
done

########################################
# 8. App post-setup inside container
########################################

# 8a. Composer install (inside web container, as helios)
echo "[helionet] checking for vendor/autoload.php on host..."
if [[ ! -f "$APP_DIR/vendor/autoload.php" ]]; then
  echo "[helionet] vendor not found, attempting composer install in web container..."
  if $COMPOSE_CMD exec -T web sh -lc 'command -v composer >/dev/null 2>&1'; then
    run_in_web "cd /var/www/html && composer install --no-interaction --prefer-dist --optimize-autoloader"
    echo "[helionet] composer install complete"
  else
    echo "[helionet] WARNING: composer not found in web container."
    echo "[helionet]          Please run 'composer install' manually in ../helionet."
  fi
else
  echo "[helionet] vendor/autoload.php present on host, skipping composer install"
fi

# 8b. Ensure APP_KEY is set (and .env exists) inside the container
echo "[helionet] ensuring APP_KEY is set..."
if [[ -f "$APP_ENV_FILE" ]]; then
  # Make sure the container sees an .env (bind mount should, but belt & suspenders)
  run_in_web 'cd /var/www/html && [ -f .env ] || ( [ -f .env.example ] && cp .env.example .env )'

  if grep -q '^APP_KEY=$' "$APP_ENV_FILE" 2>/dev/null || ! grep -q '^APP_KEY=' "$APP_ENV_FILE" 2>/dev/null; then
    echo "[helionet] running php artisan key:generate in web container..."
    if ! run_in_web "cd /var/www/html && php artisan key:generate --force"; then
      echo "[helionet] WARNING: failed to run key:generate. Check container logs."
    fi
  else
    echo "[helionet] APP_KEY already set in app .env"
  fi
else
  echo "[helionet] WARNING: APP_KEY check skipped; app .env not present on host."
fi

# 8c. Migrations & queue tables, as helios
echo "[helionet] completing initial migrations..."
run_in_web "cd /var/www/html && php artisan config:clear"
#run_in_web "cd /var/www/html && php artisan queue:failed-table || true"
run_in_web "cd /var/www/html && php artisan migrate --force"

########################################
# 9. Start worker and scheduler containers
########################################

echo "[helionet] starting worker and scheduler containers..."
$COMPOSE_CMD up -d worker
$COMPOSE_CMD up -d scheduler

echo "[helionet] bootstrap complete"
echo "[helionet] Stack is up. Try opening: http://localhost:8080"
