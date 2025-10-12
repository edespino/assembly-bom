#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/generic/install.sh
# Purpose  : Default install script for components using `make install`.
# Inputs   :
#   - NAME : component name (required)
# --------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# Load shared functions
COMMON_SH="${SCRIPT_DIR}/../../lib/common.sh"
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

# Required input
NAME="${NAME:?Component name (NAME) must be provided}"
BUILD_DIR="$PARTS_DIR/$NAME"

section "install"
start_time=$(date +%s)

# Validate build directory
if [[ ! -d "$BUILD_DIR" ]]; then
  echo "[install] ERROR: Build directory '$BUILD_DIR' not found."
  exit 1
fi

cd "$BUILD_DIR"

log "Component:       $NAME"
log "Build directory: $BUILD_DIR"

# Find the actual source directory (handle extracted tarballs)
if [ ! -f "./Makefile" ]; then
  # Look for Makefile in subdirectories (common for tarballs)
  SUBDIR=$(find . -maxdepth 2 -name "Makefile" -type f | head -1 | xargs dirname)
  if [ -n "$SUBDIR" ] && [ -f "$SUBDIR/Makefile" ]; then
    log "Found Makefile in: $SUBDIR"
    cd "$SUBDIR" || exit 1
  else
    echo "[install] ERROR: No Makefile found in $BUILD_DIR"
    exit 1
  fi
fi

echo ""

# Perform install
install_cmd=(sudo make -j"$(nproc)" install)
log "Running install command:"
printf '  %s\n' "${install_cmd[@]}"
"${install_cmd[@]}" | tee "$BUILD_DIR/make-install-$(date '+%Y.%m.%d-%H.%M.%S').log"

section_complete "install" "$start_time"
