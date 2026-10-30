#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/cloudberry/install.sh
# Purpose  : Specialized install script for the 'cloudberry' core component.
# Inputs   :
#   - NAME            : component name (default: cloudberry)
#   - INSTALL_PREFIX  : optional (defaults to /usr/local)
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

# Load Cloudberry-specific functions
CLOUDBERRY_COMMON="${SCRIPT_DIR}/common.sh"
if [ -f "${CLOUDBERRY_COMMON}" ]; then
  # shellcheck disable=SC1090
  source "${CLOUDBERRY_COMMON}"
else
  echo "[$SCRIPT_NAME] Missing library: ${CLOUDBERRY_COMMON}" >&2
  exit 1
fi

# shellcheck disable=SC1091
[ -f config/env.sh ] && source config/env.sh

NAME="${NAME:-cloudberry}"
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

# Contrib install
if [[ -d "contrib" ]]; then
  contrib_cmd=(make -j"$(nproc)" install --directory="contrib")
  log "Installing contrib:"
  printf '  %s\n' "${contrib_cmd[@]}"
  "${contrib_cmd[@]}" | tee "make-contrib-install-$(date '+%Y.%m.%d-%H.%M.%S').log"
else
  log "Skipping contrib install — directory not found."
fi

# Install PyGreSQL for system python3
log "Installing PyGreSQL for system python3..."
if [[ -f "$INSTALL_PREFIX/cloudberry-env.sh" ]]; then
  # Source the cloudberry environment to get pg_config in PATH
  source "$INSTALL_PREFIX/cloudberry-env.sh"

  # Detect OS and use appropriate installation method
  OS_ID=""
  OS_VERSION_ID=""
  if [[ -f /etc/os-release ]]; then
    OS_ID=$(grep -E '^ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
    OS_VERSION_ID=$(grep -E '^VERSION_ID=' /etc/os-release | cut -d= -f2 | tr -d '"')
  fi

  # Install PyGreSQL using appropriate method for the platform
  if [[ "$OS_ID" == "debian" && "$OS_VERSION_ID" == "12" ]]; then
    log "Detected Debian 12 - using apt-get for PyGreSQL installation"
    pygresql_cmd=(sudo apt-get install -y python3-pygresql)
  else
    log "Using pip3 for PyGreSQL installation"
    pygresql_cmd=(sudo env PATH="$PATH" pip3 install PyGreSQL)
  fi

  log "Running PyGreSQL install:"
  printf '  %s\n' "${pygresql_cmd[@]}"
  "${pygresql_cmd[@]}"

  log "PyGreSQL installation completed successfully"

  # Display versions of Python modules
  log ""
  log "🐍 Python Module Versions:"
  log "  ├─ pg:     $(python3 -c "import pg; print(pg.__version__)" 2>/dev/null || echo "❌ NOT FOUND")"
  log "  ├─ psutil: $(python3 -c "import psutil; print(psutil.__version__)" 2>/dev/null || echo "❌ NOT FOUND")"
  log "  └─ yaml:   $(python3 -c "import yaml; print(yaml.__version__)" 2>/dev/null || echo "❌ NOT FOUND")"
  log ""
else
  log "WARNING: cloudberry-env.sh not found at $INSTALL_PREFIX, skipping PyGreSQL install"
fi

# Post-install version check. --version is the PostgreSQL base (14.x here).
# --gp-version is the Cloudberry release. Do not treat the base version as
# the release version. EXPECTED_GP_VERSION and EXPECTED_GP_BUILD are optional
# and, when set, must appear in the --gp-version line.
POSTGRES_BIN="${INSTALL_PREFIX}/bin/postgres"
if [[ ! -x "$POSTGRES_BIN" ]]; then
  log "ERROR: postgres executable not found at $POSTGRES_BIN"
  exit 1
fi
pg_version="$("$POSTGRES_BIN" --version)"
gp_version="$("$POSTGRES_BIN" --gp-version)"
log "postgres --version: ${pg_version}"
log "postgres --gp-version: ${gp_version}"
if [[ -n "${EXPECTED_GP_VERSION:-}" && "$gp_version" != *"${EXPECTED_GP_VERSION}"* ]]; then
  log "ERROR: --gp-version does not contain EXPECTED_GP_VERSION=${EXPECTED_GP_VERSION}"
  exit 1
fi
if [[ -n "${EXPECTED_GP_BUILD:-}" && "$gp_version" != *"${EXPECTED_GP_BUILD}"* ]]; then
  log "ERROR: --gp-version does not contain EXPECTED_GP_BUILD=${EXPECTED_GP_BUILD}"
  exit 1
fi

section_complete "install" "$start_time"
