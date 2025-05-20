#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/make-apache-arrow.sh
# Purpose  : Install Apache Arrow from its CMake build directory.
# Inputs   :
#   - NAME : optional override (default: apache-arrow)
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

# Load shared environment
# shellcheck disable=SC1091
[ -f config/env.sh ] && . config/env.sh

NAME="${NAME:-apache-arrow}"
BUILD_DIR="parts/$NAME/cpp/build"

section "install"
start_time=$(date +%s)

# Validate build directory
if [[ ! -d "$BUILD_DIR" ]]; then
  echo "[install] ERROR: Build directory '$BUILD_DIR' not found."
  exit 1
fi

cd "$BUILD_DIR"

log "Component:       $NAME"
log "Install from:    $BUILD_DIR"
echo ""

install_cmd=(make -j"$(nproc)" install)
log "Running install command:"
printf '  %s\n' "${install_cmd[@]}"
"${install_cmd[@]}" | tee "make-install-$(date '+%Y.%m.%d-%H.%M.%S').log"

section_complete "install" "$start_time"
