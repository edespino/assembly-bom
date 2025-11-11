#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/postgres14/installcheck.sh
# Purpose  : Run installcheck for PostgreSQL 14
# Inputs   :
#   - NAME: component name (e.g., postgres14)
#   - BRANCH: branch from bom.yaml (e.g., REL_14_STABLE)
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
NAME="${NAME:-postgres14}"

section "installcheck"
start_time=$(date +%s)

# Extract version from NAME (postgres14 -> 14) OR from BRANCH (REL_14_STABLE -> 14)
VERSION=""

# Try extracting from NAME first (postgres14, postgres15, etc.)
if [[ "$NAME" =~ postgres([0-9]+) ]]; then
  VERSION="${BASH_REMATCH[1]}"
  log "Extracted version from NAME '$NAME': $VERSION"
# Fallback to extracting from BRANCH (REL_14_STABLE, REL_15_STABLE, etc.)
elif [[ -n "${BRANCH:-}" ]] && [[ "$BRANCH" =~ REL_([0-9]+) ]]; then
  VERSION="${BASH_REMATCH[1]}"
  log "Extracted version from BRANCH '$BRANCH': $VERSION"
else
  log "ERROR: Could not extract version from NAME='$NAME' or BRANCH='${BRANCH:-}'"
  log "Expected NAME format: postgresXX (e.g., postgres14)"
  log "Expected BRANCH format: REL_XX_STABLE (e.g., REL_14_STABLE)"
  exit 1
fi

# Set paths based on version
ENV_FILE="$HOME/pg${VERSION}-env.sh"
PGDATA_DIR="$HOME/pgdata${VERSION}"
BUILD_DIR="$PARTS_DIR/$NAME"

log "Component: $NAME"
log "PostgreSQL version: $VERSION"
log "Environment file: $ENV_FILE"
log "Data directory: $PGDATA_DIR"
log "Build directory: $BUILD_DIR"
echo ""

# Verify environment file exists
if [ ! -f "$ENV_FILE" ]; then
  log "ERROR: Environment file not found: $ENV_FILE"
  log "Run the initdb step first to create it"
  exit 1
fi

# Verify build directory exists
if [ ! -d "$BUILD_DIR" ]; then
  log "ERROR: Build directory not found: $BUILD_DIR"
  log "Run the clone and build steps first"
  exit 1
fi

# Source the environment file
log "Sourcing environment file: $ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

# Verify pg_config is accessible
if ! command -v pg_config &> /dev/null; then
  log "ERROR: pg_config not found in PATH after sourcing environment"
  log "PATH: $PATH"
  exit 1
fi

log "PostgreSQL binary location: $(which pg_config)"
log "PostgreSQL version: $(pg_config --version)"
echo ""

# Set PGPORT if not already set
export PGPORT="${PGPORT:-5432}"
log "PGPORT: $PGPORT"
echo ""

# Change to build directory
cd "$BUILD_DIR"
log "Working directory: $(pwd)"
echo ""

# Check if server is running
log "Checking if PostgreSQL server is running..."
if ! pg_ctl status -D "$PGDATA_DIR" &> /dev/null; then
  log "ERROR: PostgreSQL server is not running"
  log "Start the server first with: ./assemble.sh --run --component $NAME --steps start"
  exit 1
fi

log "PostgreSQL server is running"
pg_ctl status -D "$PGDATA_DIR"
echo ""

# Run installcheck
log "Running make installcheck..."
log "Command: make installcheck"
echo ""

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOG_FILE="make-${NAME}-installcheck-${TIMESTAMP}.log"

make installcheck 2>&1 | tee "$LOG_FILE"

echo ""
log "Installcheck completed successfully"
log "Log file: $LOG_FILE"

section_complete "installcheck" "$start_time"
