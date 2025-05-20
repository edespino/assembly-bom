#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/create-demo-cluster-cloudberry.sh
# Purpose  : Initialize a Cloudberry demo cluster
# --------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# Load shared functions
COMMON_SH="${SCRIPT_DIR}/../lib/common.sh"
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
EXT_DIR="parts/$NAME"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

section "create demo cluster"
start_time=$(date +%s)

# Validate source directory
if [[ ! -d "$EXT_DIR" ]]; then
  echo "[create-demo-cluster] ❌ ERROR: Directory '$EXT_DIR' not found"
  exit 1
fi

cd "$EXT_DIR"

# Try default path first
GP_PATH="/usr/local/cloudberry/greenplum_path.sh"

# Fallback to glob search if not found
if [[ ! -f "$GP_PATH" ]]; then
  GP_PATH=$(find /usr/local -type f -name greenplum_path.sh -path "*/cloudberry-db-*/greenplum_path.sh" 2>/dev/null | sort -r | head -n 1)
fi

if [[ -z "$GP_PATH" || ! -f "$GP_PATH" ]]; then
  echo "[create-demo-cluster] ❌ ERROR: greenplum_path.sh not found under /usr/local/cloudberry or cloudberry-db-*"
  exit 1
fi

log "Sourcing environment from $GP_PATH"
# shellcheck disable=SC1090
source "$GP_PATH"

export BLDWRAP_POSTGRES_CONF_ADDONS="fsync=off"
log "BLDWRAP_POSTGRES_CONF_ADDONS set to: $BLDWRAP_POSTGRES_CONF_ADDONS"

log "Running: make create-demo-cluster"
make create-demo-cluster

section_complete "create demo cluster" "$start_time"
