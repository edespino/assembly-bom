#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/dependencies/doxygen/configure.sh
# Purpose  : Custom configure script for doxygen (uses CMake out-of-source build)
# Inputs   :
#   - NAME: component name (doxygen)
#   - CONFIGURE_FLAGS: passed from bom.yaml
#   - INSTALL_PREFIX: optional override (defaults to /usr/local/doxygen)
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

# Load shared environment
# shellcheck disable=SC1091
[ -f config/env.sh ] && . config/env.sh

# Setup
NAME="${NAME:-doxygen}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/doxygen}"
BUILD_DIR="$PARTS_DIR/${NAME}"

# Validate environment
if [[ ! -d "$BUILD_DIR" ]]; then
  echo "[configure] ERROR: Build directory '$BUILD_DIR' does not exist"
  exit 1
fi

cd "$BUILD_DIR"

section "configure"
start_time=$(date +%s)

log "Component: $NAME"
log "Clone root: $BUILD_DIR"
log "Install prefix: $INSTALL_PREFIX"
echo ""

# Create build directory
log "Creating build directory..."
mkdir -p build
cd build

log "Working directory: $(pwd)"
echo ""

# Configure doxygen with CMake (out-of-source build)
log "Configuring doxygen with CMake..."
log "Command: cmake -DCMAKE_INSTALL_PREFIX=${INSTALL_PREFIX} ${CONFIGURE_FLAGS:-} .."
echo ""

# shellcheck disable=SC2086
cmake -DCMAKE_INSTALL_PREFIX="${INSTALL_PREFIX}" ${CONFIGURE_FLAGS:-} .. 2>&1 | tee "$BUILD_DIR/configure-$(date '+%Y%m%d-%H%M%S').log"

section_complete "configure" "$start_time"
