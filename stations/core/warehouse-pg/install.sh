#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/warehouse-pg/install.sh
# Purpose  : Specialized install script for the 'warehouse-pg' core component.
# Inputs   :
#   - NAME            : component name (default: warehouse-pg)
#   - INSTALL_PREFIX  : optional (defaults to /usr/local/warehouse-pg)
# Notes    : This script skips the contrib directory install (unlike cloudberry)
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

section "install: $NAME"
start_time=$(date +%s)

# Ensure source tree exists
if [[ ! -d "$BUILD_DIR" ]]; then
  echo "[install] ERROR: Build directory '$BUILD_DIR' not found"
  exit 1
fi

cd "$BUILD_DIR"

# Adjust permissions on prefix
if [[ -d "$INSTALL_PREFIX" ]]; then
    sudo chmod a+w "$INSTALL_PREFIX"
fi

# Setup Xerces-C environment
setup_xerces

# Core install
install_cmd=(make -j"$(nproc)" install --directory=".")
log "Running core install:"
printf '  %s\n' "${install_cmd[@]}"
"${install_cmd[@]}" | tee "make-install-$(date '+%Y.%m.%d-%H.%M.%S').log"

# Skip contrib install for warehouse-pg
log "Skipping contrib install for warehouse-pg component"

# Install Psycopg for system python3
log "Installing Psycopg for system python3..."
if [[ -f "$INSTALL_PREFIX/greenplum_path.sh" ]]; then
  # Source the greenplum environment to get pg_config in PATH
  source "$INSTALL_PREFIX/greenplum_path.sh"

  # Detect OS and use appropriate installation method
  OS_ID=""
  OS_VERSION_ID=""
  if [[ -f /etc/os-release ]]; then
    OS_ID=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    OS_VERSION_ID=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
  fi

  # Install Psycopg using appropriate method for the platform
  if [[ "$OS_ID" == "debian" && "$OS_VERSION_ID" == "12" ]]; then
    log "Detected Debian 12 - using apt-get for Psycopg installation"
    psycopg_cmd=(sudo apt-get install -y python3-psycopg2)
  else
    log "Using pip3 for Psycopg installation"
    psycopg_cmd=(sudo env PATH="$PATH" pip3 install psycopg2-binary)
  fi

  log "Running Psycopg install:"
  printf '  %s\n' "${psycopg_cmd[@]}"
  "${psycopg_cmd[@]}"

  log "Psycopg installation completed successfully"

  # Display versions of Python modules
  log ""
  log "🐍 Python Module Versions:"
  log "  ├─ psycopg2: $(python3 -c "import psycopg2; print(psycopg2.__version__)" 2>/dev/null || echo "❌ NOT FOUND")"
  log "  ├─ psutil:   $(python3 -c "import psutil; print(psutil.__version__)" 2>/dev/null || echo "❌ NOT FOUND")"
  log "  └─ yaml:     $(python3 -c "import yaml; print(yaml.__version__)" 2>/dev/null || echo "❌ NOT FOUND")"
  log ""
else
  log "WARNING: greenplum_path.sh not found at $INSTALL_PREFIX, skipping Psycopg install"
fi

# Post-install check - Load warehouse-pg environment
if [[ -f "$INSTALL_PREFIX/greenplum_path.sh" ]]; then
  log "Loading warehouse-pg environment from $INSTALL_PREFIX/greenplum_path.sh"
  source "$INSTALL_PREFIX/greenplum_path.sh"
  postgres --version
  postgres --gp-version
else
  log "ERROR: greenplum_path.sh not found at $INSTALL_PREFIX"
  exit 1
fi

section_complete "install" "$start_time"
