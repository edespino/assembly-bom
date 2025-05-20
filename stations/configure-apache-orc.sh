#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/configure-apache-orc.sh
# Purpose  : Configure script for the Apache ORC C++ component using CMake.
# Inputs   :
#   - CONFIGURE_FLAGS: CMake flags passed from bom.yaml (mandatory)
#   - INSTALL_PREFIX: override default install path
# Notes    :
#   - Java components are explicitly disabled using -DBUILD_JAVA=OFF
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

# Setup
NAME="${NAME:-apache-orc}"
INSTALL_PREFIX="${INSTALL_PREFIX:-$HOME/assembly-bom/stage/$NAME}"
BUILD_DIR="parts/$NAME/build"

# Prepare build and install directories
mkdir -p "$BUILD_DIR"
mkdir -p "$INSTALL_PREFIX"
cd "$BUILD_DIR"

section "configure"
start_time=$(date +%s)

# Require CONFIGURE_FLAGS
if [[ -z "${CONFIGURE_FLAGS:-}" ]]; then
  echo "❌ Error: CONFIGURE_FLAGS must be provided externally (e.g., via bom.yaml)." >&2
  exit 1
fi

# Final CMake command with Java explicitly disabled
CMAKE_CMD="cmake .. $CONFIGURE_FLAGS"

log "Running cmake with:"
echo "  $CMAKE_CMD"
echo ""

# Run it
# shellcheck disable=SC2086
eval $CMAKE_CMD 2>&1 | tee "configure-$(date '+%Y%m%d-%H%M%S').log"

section_complete "configure" "$start_time"
