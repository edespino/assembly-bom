#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/unittest-cloudberry.sh
# Purpose  : Unittest script for the 'cloudberry'
# Inputs   :
#   - NAME           : name of the component (default: cloudberry)
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

NAME="${NAME:-cloudberry}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/$NAME}"
BUILD_DIR="parts/$NAME"
CLOUDBERRY_PATH_SH="/usr/local/cloudberry/greenplum_path.sh"

section "unittest: $NAME"
start_time=$(date +%s)

# Ensure source tree exists
if [[ ! -d "$BUILD_DIR" ]]; then
  echo "[install] ERROR: Build directory '$BUILD_DIR' not found"
  exit 1
fi

cd "$BUILD_DIR"

# Load Cloudberry environment
if [[ -f "$CLOUDBERRY_PATH_SH" ]]; then
  # shellcheck disable=SC1090
  source "$CLOUDBERRY_PATH_SH"
else
  echo "[unittest-cloudberry] ERROR: greenplum_path.sh not found at $CLOUDBERRY_PATH_SH"
  exit 1
fi

log "Running make unittest"
make unittest-check -C "$HOME/assembly-bom/parts/$NAME" | tee "make-${NAME}-unittest-$(date '+%Y%m%d-%H%M%S').log"

section_complete "unittest: $NAME" "$start_time"
