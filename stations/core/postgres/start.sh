#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/postgres/start.sh
# Purpose  : Start PostgreSQL server for postgres15, postgres16, etc.
# Inputs   :
#   - NAME: component name (e.g., postgres15, postgres16)
#   - BRANCH: branch from bom.yaml (e.g., REL_15_STABLE)
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

section "start"
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

# Set paths based on version
ENV_FILE="$HOME/pg${VERSION}-env.sh"
PGDATA_DIR="$HOME/pgdata${VERSION}"
LOGFILE="$PGDATA_DIR/logfile"

log "Component: $NAME"
log "PostgreSQL version: $VERSION"
log "Environment file: $ENV_FILE"
log "Data directory: $PGDATA_DIR"
echo ""

# Verify environment file exists
if [ ! -f "$ENV_FILE" ]; then
  log "ERROR: Environment file not found: $ENV_FILE"
  log "Run the initdb step first to create it"
  exit 1
fi

# Verify data directory exists
if [ ! -d "$PGDATA_DIR" ]; then
  log "ERROR: Data directory not found: $PGDATA_DIR"
  log "Run the initdb step first to initialize the database"
  exit 1
fi

# Change to home directory
cd "$HOME"
log "Working directory: $(pwd)"

# Source the environment file
log "Sourcing environment file: $ENV_FILE"
# shellcheck disable=SC1090
source "$ENV_FILE"

# Verify pg_ctl is accessible
if ! command -v pg_ctl &> /dev/null; then
  log "ERROR: pg_ctl not found in PATH after sourcing environment"
  log "PATH: $PATH"
  exit 1
fi

log "PostgreSQL binary location: $(which pg_ctl)"
echo ""

# Check if server is already running
if pg_ctl status -D "$PGDATA_DIR" &> /dev/null; then
  log "WARNING: PostgreSQL server is already running"
  pg_ctl status -D "$PGDATA_DIR"
  section_complete "start" "$start_time"
  exit 0
fi

# Start the PostgreSQL server
log "Starting PostgreSQL server..."
log "Command: pg_ctl -D $PGDATA_DIR -l $LOGFILE -s start"
echo ""

pg_ctl -D "$PGDATA_DIR" -l "$LOGFILE" -s start

echo ""
log "PostgreSQL server started successfully"
log "Data directory: $PGDATA_DIR"
log "Log file: $LOGFILE"
log ""
log "Server status:"
pg_ctl status -D "$PGDATA_DIR"
log ""
log "To connect to the database:"
log "  source $ENV_FILE"
log "  psql"
log ""
log "To view logs:"
log "  tail -f $LOGFILE"
log ""
log "To stop the server:"
log "  pg_ctl -D $PGDATA_DIR stop"

section_complete "start" "$start_time"
