#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/postgres/initdb.sh
# Purpose  : Initialize PostgreSQL database cluster for postgres15, postgres16, etc.
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

section "initdb"
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
INSTALL_PREFIX="/usr/local/pg${VERSION}"
ENV_FILE="$HOME/pg${VERSION}-env.sh"
PGDATA_DIR="$HOME/pgdata${VERSION}"

log "Component: $NAME"
log "PostgreSQL version: $VERSION"
log "Install prefix: $INSTALL_PREFIX"
log "Environment file: $ENV_FILE"
log "Data directory: $PGDATA_DIR"
echo ""

# Create environment file
log "Creating environment file: $ENV_FILE"
cat > "$ENV_FILE" << EOF
# PostgreSQL ${VERSION} Environment
# Source this file: source $ENV_FILE

export PATH=${INSTALL_PREFIX}/bin:\$PATH
export PGDATA=${PGDATA_DIR}
export PGHOST=localhost
export PGDATABASE=postgres
EOF

log "Environment file created successfully"
log "Contents:"
cat "$ENV_FILE" | sed 's/^/  /'
echo ""

# Source the environment file
log "Sourcing environment file..."
# shellcheck disable=SC1090
source "$ENV_FILE"

# Verify binaries are accessible
if ! command -v initdb &> /dev/null; then
  log "ERROR: initdb not found in PATH after sourcing environment"
  log "PATH: $PATH"
  exit 1
fi

log "PostgreSQL binary location: $(which initdb)"
log "PostgreSQL version: $(postgres --version)"
echo ""

# Check if PGDATA already exists
if [ -d "$PGDATA_DIR" ]; then
  log "WARNING: Data directory already exists: $PGDATA_DIR"
  log "Skipping initdb. To reinitialize, remove the directory first:"
  log "  rm -rf $PGDATA_DIR"
  section_complete "initdb" "$start_time"
  exit 0
fi

# Create parent directory if needed
mkdir -p "$(dirname "$PGDATA_DIR")"

# Initialize the database
log "Initializing PostgreSQL database cluster..."
log "Command: initdb"
log "Data directory: $PGDATA_DIR"
echo ""

initdb 2>&1 | tee "$HOME/initdb-pg${VERSION}-$(date '+%Y%m%d-%H%M%S').log"

echo ""
log "Database cluster initialized successfully"
log ""
log "To use this PostgreSQL installation:"
log "  source $ENV_FILE"
log ""
log "To start the server:"
log "  pg_ctl -l \$PGDATA/logfile start"
log ""
log "To stop the server:"
log "  pg_ctl stop"

section_complete "initdb" "$start_time"
