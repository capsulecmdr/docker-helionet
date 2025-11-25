#!/usr/bin/env bash
set -euo pipefail

IMAGE="ghcr.io/capsulecmdr/helionet:latest"
REPO_URL="https://github.com/capsulecmdr/helionet.git"
BRANCH="main"

if [[ -z "${GHCR_TOKEN:-}" ]]; then
    echo ""
    echo "[helionet] No GHCR_TOKEN found."
    echo "[helionet] Please enter your GHCR personal access token:"
    read -rsp "GHCR_TOKEN: " GHCR_TOKEN_INPUT
    echo ""

    if [[ -z "$GHCR_TOKEN_INPUT" ]]; then
        echo "[helionet] ERROR: GHCR_TOKEN cannot be empty."
        exit 1
    fi

    # Export for current session
    export GHCR_TOKEN="$GHCR_TOKEN_INPUT"

    echo "[helionet] GHCR_TOKEN saved."
else
    echo "[helionet] GHCR_TOKEN found in environment."
fi

echo "[helionet] Cleaning any previous build directory"
rm -rf helionet

echo "[helionet] Cloning ${REPO_URL}#${BRANCH}"
git clone --depth=1 --branch "${BRANCH}" "${REPO_URL}" helionet

echo "[helionet] Removing Git artifacts from cloned repo"
rm -rf helionet/.git

echo "[helionet] Logging into GHCR"
echo "${GHCR_TOKEN}" | docker login ghcr.io -u capsulecmdr --password-stdin

echo "[helionet] Building image ${IMAGE}"
docker build -t "${IMAGE}" .

echo "[helionet] Pushing image ${IMAGE}"
docker push "${IMAGE}"

echo "[helionet] Cleaning cloned repo"
rm -rf helionet

echo "[helionet] Done."
