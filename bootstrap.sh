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
  echo "[helionet]        Please install Docker and try again."
  exit 1
fi

# Prefer 'docker compose' but fall back to 'docker-compose' if needed
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo "[helionet] ERROR: neither 'docker compose' nor 'docker-compose' is available."
  exit 1
fi

########################################
# 1. Are we already inside the repo?
########################################

IN_REPO=0

# Heuristics: .git or docker-compose.* or README.md with 'docker-helionet'
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
# 2. Ensure .env exists
########################################

if [[ ! -f .env && -f .env.example ]]; then
  cp .env.example .env
  echo "[helionet] copied .env.example to .env"
fi

if [[ ! -f .env ]]; then
  echo "[helionet] ERROR: .env not found and .env.example missing."
  echo "[helionet]        Make sure .env.example is committed to the repo."
  exit 1
fi

########################################
# 3. Generate DB password if placeholder is present
########################################

if grep -q "CHANGEME_DB_PASSWORD" .env; then
  echo "[helionet] generating random DB password"

  # 18 bytes base64, strip = + /
  DB_PASS="$(openssl rand -base64 18 | tr -d '=+/')"

  # Linux / GNU sed version (WSL, Ubuntu, etc.)
  sed -i "s/CHANGEME_DB_PASSWORD/${DB_PASS}/" .env

  echo "[helionet] DB password updated in .env"
else
  echo "[helionet] DB password already set, leaving .env as-is"
fi

########################################
# 4. Ensure application repo exists at ../helionet
########################################

if [[ -d "$APP_DIR/.git" ]]; then
  echo "[helionet] application repo already present at '$APP_DIR'"
else
  if [[ -d "$APP_DIR" ]]; then
    echo "[helionet] WARNING: '$APP_DIR' exists but is not a git repo."
    echo "[helionet]          Skipping automatic clone to avoid overwriting."
  else
    echo "[helionet] cloning helionet application into '$APP_DIR'..."
    git clone "$APP_REPO_URL" "$APP_DIR"
  fi
fi

########################################
# 5. Bring up the stack
########################################

echo "[helionet] pulling images..."
$COMPOSE_CMD pull

echo "[helionet] starting containers..."
$COMPOSE_CMD up -d

echo "[helionet] bootstrap complete"
echo "[helionet] Stack is up. Try opening: http://localhost:8080"
