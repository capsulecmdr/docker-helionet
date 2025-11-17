#!/bin/bash

# this script attempts to bootstrap and deploy a HelioNET environment.

# 2025 @Orsiki

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

set -euo pipefail

echo "================================"
echo "      HelioNET Bootstrap"
echo "================================"
echo
echo "This script will install Docker and Docker Compose, download all required components and dependencies, configure scheduled tasks, and start the HelioNET environment."

echo


# Variables
DEFAULT_INSTALL_DIR="/opt/docker-helionet"
INSTALL_DIR=""

REPO_URL="https://github.com/capsulecmdr/docker-helionet.git"
REPO_DIR="docker-helionet"



###########################
# 1. setup installation
###########################
echo "Where would you like to install HelioNET?"
read -rp "> Install directory [${DEFAULT_INSTALL_DIR}]: " USER_INPUT

# Determine final path
if [[ -z "$USER_INPUT" ]]; then
  INSTALL_DIR="$DEFAULT_INSTALL_DIR"
else
  INSTALL_DIR="$USER_INPUT"
fi

# Strip possible trailing slash for consistency
INSTALL_DIR="${INSTALL_DIR%/}"

echo -e "\n  Installing to: $INSTALL_DIR"

# Check if directory exists
if [[ -d "$INSTALL_DIR" ]]; then
  echo "  Directory exists. Proceeding..."
else
  echo "  Directory does not exist."
  read -rp "  > Would you like to create it? [y/N]: " CREATE_DIR
  CREATE_DIR="${CREATE_DIR,,}"  # lowercase

  if [[ "$CREATE_DIR" == "y" || "$CREATE_DIR" == "yes" ]]; then
    echo "  Creating directory..."
    sudo mkdir -p "$INSTALL_DIR"
    echo "  Directory created."
  else
    echo "  Install aborted. Directory does not exist."
    exit 1
  fi
fi

# At this point $INSTALL_DIR exists
echo -e "\n# Proceeding with installation in: $INSTALL_DIR"
echo

# ensure user is ready to continue
read -rp " Are you ready to continue? [Y/n]: " -n 1

if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    echo -e "\n !Aborting installation!"
    exit 1
fi

# validate root permissions
if (( $EUID != 0 )); then

    echo -e "\n This script must be run with root permissions. Please re-run with 'sudo'."
    exit
fi

###########################
# 2. Validate Dependencies
###########################
# Have curl?
if ! [ -x "$(command -v curl)" ]; then

    echo -e "\n curl is not installed. Installing..."

    apt update && apt install -y curl
    
    echo -e "\n curl installed"
fi

# Have docker?
if ! [ -x "$(command -v docker)" ]; then

    echo -e "\n Docker is not installed. Installing..."

    sh <(curl -fsSL get.docker.com)

    echo -e "\n Docker installed"
fi


###########################
# setup host cron job
###########################
CRON_JOB="* * * * * $INSTALL_DIR/host_worker.sh $INSTALL_DIR/log/host_worker.log >> $INSTALL_DIR/log/host_worker.log 2>&1"

existing_cron=$(crontab -l 2>/dev/null || true)

# Check if the cron job already exists
if echo "$existing_cron" | grep -Fq "$CRON_JOB"; then
    echo -e "\n  Cron job already exists. No changes made."
else
    echo -e "\n  Adding cron job..."
    # Append the new job and install it
    (echo "$existing_cron"; echo "$CRON_JOB") | crontab -
    echo -e "\n  Cron job added successfully."
fi

if [[ ! -f "$INSTALL_DIR/log" ]]; then
    echo -e "\n  Creating log directory..."
    mkdir -p "$INSTALL_DIR/log"
    echo -e "\n  Log directory created."
fi

if [[ ! -f "$INSTALL_DIR/log/host_worker.log" ]]; then
    echo -e "\n  Creating host_worker.log file..."
    touch "$INSTALL_DIR/log/host_worker.log"
    echo -e "\n  host_worker.log file created."
fi


###########################
# setup docker compose command
###########################

# Prefer 'docker compose' but fall back to 'docker-compose'
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
else
  echo "[helionet] ERROR: neither 'docker compose' nor 'docker-compose' is available."
  exit 1
fi

###########################
# Helper: run a command in the web container
###########################
run_in_web() {
  # usage: run_in_web "command here"
  $COMPOSE_CMD exec -T web sh -lc "$*"
}

########################################
# 1. Ensure we are in docker-helionet repo
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
#    and generate secrets on first run
########################################
if [[ ! -f .env ]]; then
  if [[ ! -f .env.example ]]; then
    echo "[helionet] ERROR: .env.example missing — cannot auto-create .env"
    exit 1
  fi

  echo "[helionet] creating .env from .env.example..."
  cp .env.example .env

  #
  # 2a. Generate DB password
  #
  DB_PASS="$(openssl rand -base64 18 | tr -d '=+/')"
  if grep -q "CHANGEME_DB_PASSWORD" .env; then
    sed -i "s/CHANGEME_DB_PASSWORD/${DB_PASS}/" .env
  else
    # Fallback: if no placeholder, force-set DB_PASSWORD line
    if grep -q "^DB_PASSWORD=" .env; then
      sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/" .env
    else
      echo "DB_PASSWORD=${DB_PASS}" >> .env
    fi
  fi
  echo "[helionet] generated DB_PASSWORD"

  #
  # 2b. Generate secure APP_KEY
  #
  APP_KEY="base64:$(openssl rand -base64 32)"
  esc_key=$(printf '%s\n' "$APP_KEY" | sed 's/[\/&]/\\&/g')

  if grep -q "^APP_KEY=" .env; then
    sed -i "s/^APP_KEY=.*/APP_KEY=${esc_key}/" .env
  else
    echo "APP_KEY=${APP_KEY}" >> .env
  fi
  echo "[helionet] generated APP_KEY"

else
  echo "[helionet] existing .env found — skipping env generation"
fi

########################################
# 3. Start / restart the stack
########################################
echo "[helionet] stopping any existing stack (if present)..."
$COMPOSE_CMD down --remove-orphans || true

echo "[helionet] pulling images..."
$COMPOSE_CMD pull

echo "[helionet] starting core containers (web, db, redis)..."
$COMPOSE_CMD up -d web db redis

########################################
# 4. Run migrations inside the web container
########################################
echo "[helionet] running migrations in web container..."
# Clear cached config in case APP_KEY / DB_ vars changed
run_in_web "cd /var/www/html && php artisan config:clear || true"
# In production, migrate MUST use --force (non-interactive)
run_in_web "cd /var/www/html && php artisan migrate --force || true"

########################################
# 5. Ensure worker and scheduler containers are up
########################################
echo "[helionet] starting worker and scheduler containers..."
$COMPOSE_CMD up -d worker
$COMPOSE_CMD up -d scheduler

echo "[helionet] bootstrap complete"
echo "[helionet] Stack is up. Try opening: http://localhost:8080"