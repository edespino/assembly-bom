#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/warehouse-pg/build.sh
# Purpose  : Specialized build script for the 'warehouse-pg' core component.
# Inputs   :
#   - INSTALL_PREFIX : optional override (defaults to /usr/local/warehouse-pg)
#   - NAME           : component name (default: warehouse-pg)
# Notes    : This script skips the contrib directory build (unlike cloudberry)
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

# Load warehouse-pg-specific functions (symlinked to cloudberry/common.sh)
WAREHOUSE_PG_COMMON="${SCRIPT_DIR}/common.sh"
if [ -f "${WAREHOUSE_PG_COMMON}" ]; then
  # shellcheck disable=SC1090
  source "${WAREHOUSE_PG_COMMON}"
else
  echo "[$SCRIPT_NAME] Missing library: ${WAREHOUSE_PG_COMMON}" >&2
  exit 1
fi

# shellcheck disable=SC1091
[ -f config/env.sh ] && source config/env.sh

NAME="${NAME:-warehouse-pg}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/$NAME}"
BUILD_DIR="$PARTS_DIR/$NAME"

section "build"
start_time=$(date +%s)

# Verify build directory exists
if [[ ! -d "$BUILD_DIR" ]]; then
  echo "[build] ERROR: Build directory '$BUILD_DIR' not found."
  echo "[build] Did you skip the 'clone' step without preparing the repo?"
  exit 1
fi

cd "$BUILD_DIR"

# Print version if available
[[ -f VERSION ]] && log "Build version: $(<VERSION)"

# Setup Xerces-C environment
setup_xerces

# Build core
build_cmd=(make -j"$(nproc)" --directory=".")
log "Running core build:"
printf '  %s\n' "${build_cmd[@]}"
"${build_cmd[@]}" | tee "make-$(date '+%Y.%m.%d-%H.%M.%S').log"

# Skip contrib build for warehouse-pg
log "Skipping contrib build for warehouse-pg component"

# Build core again to ensure all final tasks have been performed.
build_cmd=(make --directory=".")
log "Running core build (2nd time):"
printf '  %s\n' "${build_cmd[@]}"
"${build_cmd[@]}" | tee -a "make-$(date '+%Y.%m.%d-%H.%M.%S').log"

section_complete "build" "$start_time"
