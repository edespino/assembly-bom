#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/warehouse-pg/unittest.sh
# Purpose  : Unittest script for the 'warehouse-pg'
# Inputs   :
#   - NAME           : name of the component (default: warehouse-pg)
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

NAME="${NAME:-warehouse-pg}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/$NAME}"
BUILD_DIR="$PARTS_DIR/$NAME"

section "unittest: $NAME"
start_time=$(date +%s)

# Ensure source tree exists
if [[ ! -d "$BUILD_DIR" ]]; then
  echo "[unittest] ERROR: Build directory '$BUILD_DIR' not found"
  exit 1
fi

cd "$BUILD_DIR"

# Load warehouse-pg environment
if [[ -f "$INSTALL_PREFIX/greenplum_path.sh" ]]; then
  log "Loading warehouse-pg environment from $INSTALL_PREFIX/greenplum_path.sh"
  source "$INSTALL_PREFIX/greenplum_path.sh"
else
  echo "[unittest-warehouse-pg] ERROR: greenplum_path.sh not found at $INSTALL_PREFIX"
  exit 1
fi

log "Running make unittest"
make unittest-check -C "$PARTS_DIR/$NAME" | tee "make-${NAME}-unittest-$(date '+%Y%m%d-%H%M%S').log"

section_complete "unittest: $NAME" "$start_time"
