#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/build-cloudberry.sh
# Purpose  : Specialized build script for the 'cloudberry' core component.
# Inputs   :
#   - INSTALL_PREFIX : optional override (defaults to /usr/local/cloudberry)
#   - NAME           : component name (default: cloudberry)
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

# Update LD_LIBRARY_PATH if using local Xerces-C
if [[ -d /opt/xerces-c ]]; then
  export LD_LIBRARY_PATH="${INSTALL_PREFIX}/lib:${LD_LIBRARY_PATH:-}"
fi

# Build core
build_cmd=(make -j"$(nproc)" --directory=".")
log "Running core build:"
printf '  %s\n' "${build_cmd[@]}"
"${build_cmd[@]}" | tee "make-$(date '+%Y.%m.%d-%H.%M.%S').log"

# Build contrib if available
if [[ -d contrib ]]; then
  contrib_cmd=(make -j"$(nproc)" --directory="contrib")
  log "Running contrib build:"
  printf '  %s\n' "${contrib_cmd[@]}"
  "${contrib_cmd[@]}" | tee "make-contrib-$(date '+%Y.%m.%d-%H.%M.%S').log"
else
  log "Skipping contrib build — 'contrib/' directory not found."
fi

# Build core again to ensure all final tasks have been performed.
build_cmd=(make --directory=".")
log "Running core build (2nd time):"
printf '  %s\n' "${build_cmd[@]}"
"${build_cmd[@]}" | tee -a "make-$(date '+%Y.%m.%d-%H.%M.%S').log"

section_complete "build" "$start_time"
