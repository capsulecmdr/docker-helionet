#!/usr/bin/env bash
set -euo pipefail

IMAGE="ghcr.io/capsulecmdr/helionet:latest"
REPO_URL="https://github.com/capsulecmdr/helionet.git"
BRANCH="main"

echo "[helionet] Cleaning any previous build directory"
rm -rf helionet

echo "[helionet] Cloning ${REPO_URL}#${BRANCH}"
git clone --depth=1 --branch "${BRANCH}" "${REPO_URL}" helionet

echo "[helionet] Logging into GHCR"
echo "${GHCR_TOKEN:?GHCR_TOKEN env var is required}" | docker login ghcr.io -u capsulecmdr --password-stdin

echo "[helionet] Building image ${IMAGE}"
docker build -t "${IMAGE}" .

echo "[helionet] Pushing image ${IMAGE}"
docker push "${IMAGE}"

echo "[helionet] Cleaning cloned repo"
rm -rf helionet

echo "[helionet] Done."
