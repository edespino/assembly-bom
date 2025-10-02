#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/cloudberry/create-demo-cluster.sh
# Purpose  : Initialize a Cloudberry demo cluster
# --------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# Load shared functions
COMMON_SH="${SCRIPT_DIR}/../../../lib/common.sh"
if [ -f "${COMMON_SH}" ]; then
  # shellcheck disable=SC1090
  source "${COMMON_SH}"
else
  echo "[$SCRIPT_NAME] Missing library: ${COMMON_SH}" >&2
  exit 1
fi

# shellcheck disable=SC1091
[ -f config/env.sh ] && source config/env.sh

NAME="${NAME:?Component NAME is required}"
EXT_DIR="$PARTS_DIR/$NAME"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

section "create demo cluster"
start_time=$(date +%s)

# Validate source directory
if [[ ! -d "$EXT_DIR" ]]; then
  echo "[create-demo-cluster] ❌ ERROR: Directory '$EXT_DIR' not found"
  exit 1
fi

cd "$EXT_DIR"

# Load Cloudberry environment with fallback
[ -f "${SCRIPT_DIR}/../../../config/cloudberry-env-loader.sh" ] && source "${SCRIPT_DIR}/../../../config/cloudberry-env-loader.sh"
if ! source_cloudberry_env /usr/local/cloudberry; then
  echo "[create-demo-cluster] ERROR: Failed to load Cloudberry environment"
  exit 1
fi

export BLDWRAP_POSTGRES_CONF_ADDONS="fsync=off"
log "BLDWRAP_POSTGRES_CONF_ADDONS set to: $BLDWRAP_POSTGRES_CONF_ADDONS"

log "Running: make create-demo-cluster"
make create-demo-cluster

section_complete "create demo cluster" "$start_time"
