#!/bin/bash

# this script attempts to bootstrap and deploy a HelioNET environment.

# 2025 @Orsiki

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
# 
###########################

###########################
# 
###########################

###########################
# 
###########################

###########################
# 
###########################

###########################
# 
###########################