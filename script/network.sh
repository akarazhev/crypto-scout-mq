#!/bin/bash
set -Eeuo pipefail

NETWORK_NAME="crypto-scout-bridge"

if podman network exists "$NETWORK_NAME" 2>/dev/null; then
  echo "[INFO] Network '$NETWORK_NAME' already exists."
else
  echo "[INFO] Creating network '$NETWORK_NAME'..."
  podman network create "$NETWORK_NAME"
fi

podman network inspect "$NETWORK_NAME"