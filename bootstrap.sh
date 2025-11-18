#!/bin/bash

# HelioNET bootstrap & deploy script
# 2025 @Orsiki

set -euo pipefail

########################################
# Colors & logging helpers
########################################
RESET="\e[0m"
COLOR_INFO="\e[36m"   # cyan
COLOR_OK="\e[32m"     # green
COLOR_WARN="\e[33m"   # yellow
COLOR_ERR="\e[31m"    # red

log_msg() {
  local stage="$1"
  local step="$2"
  local total="$3"
  local level="$4"
  shift 4
  local msg="$*"

  local tag=""
  local color="$COLOR_INFO"

  case "$level" in
    OK)
      tag="[OK]"
      color="$COLOR_OK"
      ;;
    WARN)
      tag="[WARN]"
      color="$COLOR_WARN"
      ;;
    ERROR)
      tag="[ERR]"
      color="$COLOR_ERR"
      ;;
    INFO|*)
      tag="[INFO]"
      color="$COLOR_INFO"
      ;;
  esac

  printf "%b[HelioNET | %s %s/%s] %s %s%b\n" \
    "$color" "$stage" "$step" "$total" "$tag" "$msg" "$RESET"
}

########################################
# Banner
########################################
printf "\e[36m"
cat << "EOF"
              ################
          #######################
       ######                 ######
     #####                       #####
    ####       ####     ####       ####
   ####      ######     #######     ####
  ###        ######     #######      ####
 ####        ######     #######       ####                                       @
####         ##################        ####   @@@         @@@                   @@@    @@@                    @@@@@         @@@    @@@@@@@@@@@ @@@@@@@@@@@@@@@
####         ##################         ###   @@@         @@@                   @@@     @                     @@@@@@        @@@    @@@@@@@@@@@  @@@@@@@@@@@@@@
###          ##################         ###   @@@         @@@                   @@@                           @@@ @@@       @@@    @@@@              @@@
###                                     ###   @@@         @@@      @@@@@@@@     @@@    @@@      @@@@@@@@@     @@@  @@@      @@@    @@@@              @@@
###          ######     ######          ###   @@@         @@@     @@@    @@@    @@@    @@@    @@@@    @@@@    @@@   @@@     @@@    @@@@              @@@
####         ######     #######         ###   @@@@@@@@@@@@@@@    @@@      @@@   @@@    @@@   @@@        @@@   @@@    @@@@   @@@    @@@@@@@@@@        @@@
####          #####     #####          ####   @@@         @@@   @@@@@@@@@@@@@@  @@@    @@@   @@@        @@@   @@@     @@@@  @@@    @@@@              @@@
 ####        #               #        ####    @@@         @@@   @@@             @@@    @@@   @@@        @@@   @@@       @@@ @@@    @@@@              @@@
  ####       ######     #######      ####     @@@         @@@    @@@            @@@    @@@   @@@@       @@@   @@@        @@@@@@    @@@@              @@@
   ####      ######     #######     ####      @@@         @@@    @@@@@    @@    @@@    @@@    @@@@    @@@@    @@@         @@@@@    @@@@@@@@@@@       @@@
    ####       ####     ####       ####       @@@         @@@       @@@@@@@@    @@@    @@@      @@@@@@@@      @@@          @@@@    @@@@@@@@@@@@      @@@
     ######       #     #        #####
        #####                 #####
          #######################
              ###############

EOF
printf "\e[0m\n"

log_msg "Init" 1 5 "INFO" "Starting HelioNET bootstrap..."
echo
echo "This script will install Docker and Docker Compose (if needed),"
echo "download the HelioNET docker environment, configure host cron,"
echo "and start the HelioNET containers."
echo

########################################
# Init: root check
########################################
log_msg "Init" 2 5 "INFO" "Verifying script is running as root..."
if (( EUID != 0 )); then
  log_msg "Init" 2 5 "ERROR" "This script must be run with root permissions. Please re-run with 'sudo'."
  exit 1
fi
log_msg "Init" 2 5 "OK" "Root permissions confirmed."

########################################
# Init: choose install directory
########################################
DEFAULT_INSTALL_DIR="/opt/docker-helionet"
INSTALL_DIR=""

log_msg "Init" 3 5 "INFO" "Prompting for install directory..."
read -rp "> Install directory [${DEFAULT_INSTALL_DIR}]: " USER_INPUT
if [[ -z "$USER_INPUT" ]]; then
  INSTALL_DIR="$DEFAULT_INSTALL_DIR"
else
  INSTALL_DIR="$USER_INPUT"
fi

INSTALL_DIR="${INSTALL_DIR%/}"  # strip trailing slash

echo
echo "  Installing to: $INSTALL_DIR"

if [[ -d "$INSTALL_DIR" ]]; then
  echo "  Directory exists. Proceeding..."
else
  echo "  Directory does not exist. Creating..."
  mkdir -p "$INSTALL_DIR"
  echo "  Directory created."
fi

echo
read -r -p " Are you ready to continue? [Y/n]: " -n 1
echo
# Treat empty as "Yes"
if [[ -n "${REPLY:-}" && ! "$REPLY" =~ ^[Yy]$ ]]; then
  log_msg "Init" 4 5 "WARN" "Installation aborted by user."
  exit 1
fi
log_msg "Init" 4 5 "OK" "User confirmed installation. Proceeding..."

CURRENT_FQDN=$(hostname -f 2>/dev/null || hostname -s)
DEFAULT_DOMAIN="http://${CURRENT_FQDN}:8080"

log_msg "Init" 5 5 "INFO" "Prompting for HelioNET domain..."
echo "What domain or URL will you use to access HelioNET?"
echo "Examples:"
echo "  https://helionet.example.com"
echo "  http://192.168.1.50:8080"
echo "  http://localhost:8080"
echo
read -rp "> HelioNET URL [${DEFAULT_DOMAIN}]: " USER_DOMAIN
echo

# Use default if empty
if [[ -z "$USER_DOMAIN" ]]; then
  HELIONET_DOMAIN="$DEFAULT_DOMAIN"
else
  HELIONET_DOMAIN="$(echo "$USER_DOMAIN" | xargs)"  # trim whitespace
fi

log_msg "Init" 5 5 "OK" "Using HelioNET domain: $HELIONET_DOMAIN"

REPO_URL="https://github.com/capsulecmdr/docker-helionet.git"

########################################
# Deps: validate / install dependencies
########################################
log_msg "Deps" 1 3 "INFO" "Checking for curl..."
if ! command -v curl >/dev/null 2>&1; then
  echo "  curl not found. Installing via apt..."
  apt update && apt install -y curl
  echo "  curl installed."
  log_msg "Deps" 1 3 "OK" "curl installed."
else
  log_msg "Deps" 1 3 "OK" "curl already present."
fi

log_msg "Deps" 2 3 "INFO" "Checking for Docker..."
if ! command -v docker >/dev/null 2>&1; then
  echo "  Docker not found. Installing via get.docker.com..."
  sh <(curl -fsSL https://get.docker.com)
  echo "  Docker installed."
  log_msg "Deps" 2 3 "OK" "Docker installed."
else
  log_msg "Deps" 2 3 "OK" "Docker already present."
fi

log_msg "Deps" 3 3 "INFO" "Checking for git..."
if ! command -v git >/dev/null 2>&1; then
  echo "  git not found. Installing via apt..."
  apt update && apt install -y git
  echo "  git installed."
  log_msg "Deps" 3 3 "OK" "git installed."
else
  log_msg "Deps" 3 3 "OK" "git already present."
fi

########################################
# Repo: ensure docker-helionet checkout
########################################
log_msg "Repo" 1 2 "INFO" "Ensuring HelioNET docker repository exists..."

if [[ -d "$INSTALL_DIR/.git" && ( -f "$INSTALL_DIR/docker-compose.yml" || -f "$INSTALL_DIR/docker-compose.yaml" ) ]]; then
  echo "  Existing docker-helionet repo detected at $INSTALL_DIR"
else
  if [[ -d "$INSTALL_DIR" && -n "$(ls -A "$INSTALL_DIR" 2>/dev/null || true)" && ! -d "$INSTALL_DIR/.git" ]]; then
    log_msg "Repo" 1 2 "ERROR" "$INSTALL_DIR is not empty and not a git repo. Refusing to overwrite."
    echo "  Please choose an empty directory or an existing docker-helionet checkout."
    exit 1
  fi

  echo "  Cloning $REPO_URL into $INSTALL_DIR..."
  rm -rf "$INSTALL_DIR"
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone "$REPO_URL" "$INSTALL_DIR"
  echo "  Clone complete."
fi

cd "$INSTALL_DIR"

#set execute permission for host_worker.sh
chmod +x ./host_worker.sh

#remove unnecessary files
rm -f build_and_push.sh
rm -f bootstrap.sh

echo "  Now in repo directory: $(pwd)"
log_msg "Repo" 1 2 "OK" "Repository ready in $INSTALL_DIR."

########################################
# Env: ensure .env exists & secrets
########################################
log_msg "Env" 1 2 "INFO" "Ensuring .env configuration is present..."

if [[ ! -f .env ]]; then
  if [[ ! -f .env.example ]]; then
    log_msg "Env" 1 2 "ERROR" ".env.example missing — cannot auto-create .env."
    exit 1
  fi

  echo "  Creating .env from .env.example..."
  cp .env.example .env

  DB_PASS="$(openssl rand -base64 18 | tr -d '=+/')"
  if grep -q "CHANGEME_DB_PASSWORD" .env; then
    sed -i "s/CHANGEME_DB_PASSWORD/${DB_PASS}/" .env
  else
    if grep -q "^DB_PASSWORD=" .env; then
      sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/" .env
    else
      echo "DB_PASSWORD=${DB_PASS}" >> .env
    fi
  fi
  echo "  Generated DB_PASSWORD."

  APP_KEY="base64:$(openssl rand -base64 32)"
  esc_key=$(printf '%s\n' "$APP_KEY" | sed 's/[\/&]/\\&/g')

  if grep -q "^APP_KEY=" .env; then
    sed -i "s/^APP_KEY=.*/APP_KEY=${esc_key}/" .env
  else
    echo "APP_KEY=${APP_KEY}" >> .env
  fi
  echo "  Generated APP_KEY."

  #
  # Set APP_URL in .env
  #
  if grep -q "^APP_URL=" .env; then
    # escape slashes for sed
    esc_domain=$(printf '%s\n' "$HELIONET_DOMAIN" | sed 's/[\/&]/\\&/g')
    sed -i "s/^APP_URL=.*/APP_URL=${esc_domain}/" .env
  else
    echo "APP_URL=${HELIONET_DOMAIN}" >> .env
  fi

  echo "  Set APP_URL=${HELIONET_DOMAIN}"

  log_msg "Env" 2 2 "OK" ".env created and secrets generated."
else
  log_msg "Env" 2 2 "OK" "Existing .env found — skipping env generation."

  # Always ensure APP_URL is correct
  esc_domain=$(printf '%s\n' "$HELIONET_DOMAIN" | sed 's/[\/&]/\\&/g')

  if grep -q "^APP_URL=" .env; then
    sed -i "s/^APP_URL=.*/APP_URL=${esc_domain}/" .env
  else
    echo "APP_URL=${HELIONET_DOMAIN}" >> .env
  fi

  log_msg "Env" 2 2 "OK" "Updated APP_URL=${HELIONET_DOMAIN}"
fi

########################################
# Docker: setup compose command
########################################
log_msg "Docker" 1 3 "INFO" "Detecting Docker Compose command..."

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  log_msg "Docker" 1 3 "ERROR" "Neither 'docker compose' nor 'docker-compose' is available."
  exit 1
fi
log_msg "Docker" 1 3 "OK" "Using '$COMPOSE_CMD'."

########################################
# Helper: run a command in the web container
########################################
run_in_web() {
  # usage: run_in_web "command here"
  $COMPOSE_CMD exec -T web sh -lc "$*"
}

########################################
# Docker: restart stack & migrate
########################################
log_msg "Docker" 2 3 "INFO" "Stopping any existing stack and pulling images..."
$COMPOSE_CMD down --remove-orphans || true
$COMPOSE_CMD pull
log_msg "Docker" 2 3 "OK" "Images pulled and old stack (if any) stopped."

log_msg "Docker" 3 3 "INFO" "Starting core containers (web, db, redis)..."
$COMPOSE_CMD up -d web db redis
log_msg "Docker" 3 3 "OK" "Core containers started."

log_msg "Workers" 1 1 "INFO" "Running Laravel config clear and migrations..."
run_in_web "cd /var/www/html && php artisan config:clear || true"
run_in_web "cd /var/www/html && php artisan migrate --force || true"
log_msg "Workers" 1 1 "OK" "Migrations completed."

########################################
# Workers: worker & scheduler containers
########################################
log_msg "Stack" 1 2 "INFO" "Starting worker and scheduler containers..."
$COMPOSE_CMD up -d worker
$COMPOSE_CMD up -d scheduler
log_msg "Stack" 1 2 "OK" "Worker and scheduler containers started."

########################################
# Cron: host cron job for host_worker.sh
########################################
LOG_DIR="/var/lib/docker/volumes/docker-helionet_app_storage/_data/logs" # TODO: Need to put a check in place to find the correct volume name dynamically
LOG_FILE="$LOG_DIR/host_worker.log"
HOST_WORKER_SCRIPT="$INSTALL_DIR/host_worker.sh"
CRON_JOB="* * * * * $HOST_WORKER_SCRIPT $LOG_FILE $INSTALL_DIR >> $LOG_FILE 2>&1"

log_msg "Cron" 1 3 "INFO" "Ensuring log directory exists at $LOG_DIR..."
if [[ ! -d "$LOG_DIR" ]]; then
  mkdir -p "$LOG_DIR"
  echo "  Created log directory: $LOG_DIR"
fi
log_msg "Cron" 1 3 "OK" "Log directory ready."

log_msg "Cron" 2 3 "INFO" "Ensuring host_worker log file exists..."
if [[ ! -f "$LOG_FILE" ]]; then
  touch "$LOG_FILE"
  echo "  Created log file: $LOG_FILE"
fi
log_msg "Cron" 2 3 "OK" "Log file ready."

log_msg "Cron" 3 3 "INFO" "Ensuring host_worker cron job exists..."
existing_cron=$(crontab -l 2>/dev/null || true)
if echo "$existing_cron" | grep -Fq "$CRON_JOB"; then
  echo "  Cron job already present. No changes made."
  log_msg "Cron" 3 3 "OK" "Cron job already configured."
else
  echo "  Adding cron job for host_worker.sh..."
  (echo "$existing_cron"; echo "$CRON_JOB") | crontab -
  echo "  Cron job added."
  log_msg "Cron" 3 3 "OK" "Cron job configured."
fi

if [[ ! -x "$HOST_WORKER_SCRIPT" ]]; then
  log_msg "Cron" 3 3 "WARN" "$HOST_WORKER_SCRIPT is not executable or does not exist. Cron job may fail until this is resolved."
fi

########################################
# Done
########################################
log_msg "Done" 1 1 "OK" "Bootstrap complete. HelioNET stack should be up."
echo "Open: ${HELIONET_DOMAIN}"
echo "Install directory: $INSTALL_DIR"