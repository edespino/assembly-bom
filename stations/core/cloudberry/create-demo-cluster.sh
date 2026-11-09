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

# A prefix-tarball hit has no source tree. The installed script creates the cluster.
if [[ -x /usr/local/cloudberry/bin/gpdemo && ! -d "$EXT_DIR" ]]; then
  section "create demo cluster from installed gpdemo"
  start_time=$(date +%s)
  # shellcheck disable=SC1091
  source /usr/local/cloudberry/cloudberry-env.sh
  python3 -m pip install --user "PyGreSQL==5.2.5"
  export PORT_BASE="${PORT_BASE:-7000}"
  if [[ "${FSYNC_OFF:-0}" == "1" ]]; then
    export BLDWRAP_POSTGRES_CONF_ADDONS="fsync=off"
    log "BLDWRAP_POSTGRES_CONF_ADDONS set to: $BLDWRAP_POSTGRES_CONF_ADDONS"
  fi
  work=$(mktemp -d)
  cd "$work"
  /usr/local/cloudberry/bin/gpdemo
  if [[ "${FSYNC_OFF:-0}" == "1" ]]; then
    # shellcheck disable=SC1091
    source "$work/gpdemo-env.sh"
    fsync_value=$(psql -d postgres -tA -c "SHOW fsync;")
    log "SHOW fsync=${fsync_value}"
    [[ "$fsync_value" == "off" ]]
  fi
  section_complete "create demo cluster" "$start_time"
  exit 0
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

section "create demo cluster"
start_time=$(date +%s)

# Validate source directory
if [[ ! -d "$EXT_DIR" ]]; then
  echo "[create-demo-cluster] ❌ ERROR: Directory '$EXT_DIR' not found"
  exit 1
fi

cd "$EXT_DIR"

# A git clone has the Makefile here. A release extract has it one level down.
if [[ ! -f Makefile ]]; then
  mapfile -t release_trees < <(find . -mindepth 1 -maxdepth 1 -type d -name 'apache-cloudberry-[0-9]*' | sort)
  if [[ ${#release_trees[@]} -ne 1 ]]; then
    echo "[create-demo-cluster] ERROR: no Makefile, and expected one apache-cloudberry-<version> tree"
    printf '%s\n' "${release_trees[@]:-}"
    exit 1
  fi
  cd "${release_trees[0]}"
  log "Using extracted tree: $(pwd)"
fi

# Load Cloudberry environment with fallback
[ -f "${SCRIPT_DIR}/../../../config/cloudberry-env-loader.sh" ] && source "${SCRIPT_DIR}/../../../config/cloudberry-env-loader.sh"
if ! source_cloudberry_env /usr/local/cloudberry; then
  echo "[create-demo-cluster] ERROR: Failed to load Cloudberry environment" >&2
  exit 1
fi
python3 -m pip install --user "PyGreSQL==5.2.5"

# Default leaves fsync at the server default (on).
# ./assemble.sh --fsync-off sets FSYNC_OFF=1 for the fast demo cluster.
if [[ "${FSYNC_OFF:-0}" == "1" ]]; then
  export BLDWRAP_POSTGRES_CONF_ADDONS="fsync=off"
  log "BLDWRAP_POSTGRES_CONF_ADDONS set to: $BLDWRAP_POSTGRES_CONF_ADDONS"
else
  log "fsync left on (pass --fsync-off to disable it on the demo cluster)"
fi

log "Running: make create-demo-cluster"
make create-demo-cluster

section_complete "create demo cluster" "$start_time"
