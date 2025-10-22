#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/postgres/configure.sh
# Purpose  : Generic configure script for PostgreSQL components (postgres15, postgres16, etc.)
# Inputs   :
#   - NAME: component name (e.g., postgres15, postgres16)
#   - BRANCH: branch from bom.yaml (e.g., REL_15_STABLE)
#   - CONFIGURE_FLAGS: passed from bom.yaml
#   - INSTALL_PREFIX: optional override (auto-generated from version if not set)
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
NAME="${NAME:-postgres}"
BUILD_DIR="$PARTS_DIR/${NAME}"

# Validate environment
if [[ ! -d "$BUILD_DIR" ]]; then
  echo "[configure] ERROR: Build directory '$BUILD_DIR' does not exist"
  exit 1
fi

cd "$BUILD_DIR"

section "configure"
start_time=$(date +%s)

# Extract version from NAME (postgres15 -> 15) OR from BRANCH (REL_15_STABLE -> 15)
VERSION=""

# Try extracting from NAME first (postgres15, postgres16, etc.)
if [[ "$NAME" =~ postgres([0-9]+) ]]; then
  VERSION="${BASH_REMATCH[1]}"
  log "Extracted version from NAME '$NAME': $VERSION"
# Fallback to extracting from BRANCH (REL_15_STABLE, REL_16_STABLE, etc.)
elif [[ -n "${BRANCH:-}" ]] && [[ "$BRANCH" =~ REL_([0-9]+) ]]; then
  VERSION="${BASH_REMATCH[1]}"
  log "Extracted version from BRANCH '$BRANCH': $VERSION"
else
  log "ERROR: Could not extract version from NAME='$NAME' or BRANCH='${BRANCH:-}'"
  log "Expected NAME format: postgresXX (e.g., postgres15)"
  log "Expected BRANCH format: REL_XX_STABLE (e.g., REL_15_STABLE)"
  exit 1
fi

# Set install prefix based on version
# Always use /usr/local/pgXX for PostgreSQL installations
INSTALL_PREFIX="/usr/local/pg${VERSION}"

log "Component: $NAME"
log "PostgreSQL version: $VERSION"
log "Install prefix: $INSTALL_PREFIX"

# Final configure command
CONFIGURE_CMD="./configure --prefix=${INSTALL_PREFIX} ${CONFIGURE_FLAGS:-}"

log "Running configure with:"
echo "  $CONFIGURE_CMD"
echo ""

# Run it
# shellcheck disable=SC2086
eval $CONFIGURE_CMD 2>&1 | tee "configure-$(date '+%Y%m%d-%H%M%S').log"

section_complete "configure" "$start_time"
