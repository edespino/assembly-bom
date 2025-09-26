#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/install-cloudberry.sh
# Purpose  : Specialized install script for the 'cloudberry' core component.
# Inputs   :
#   - NAME            : component name (default: cloudberry)
#   - INSTALL_PREFIX  : optional (defaults to /usr/local)
#   - GP_ENV_PATH     : optional (if set, used for final `postgres` check)
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

# shellcheck disable=SC1091
[ -f config/env.sh ] && source config/env.sh

NAME="${NAME:-cloudberry}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/$NAME}"
BUILD_DIR="$PARTS_DIR/$NAME"
# GP_ENV_PATH will be determined by cloudberry-env-loader

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

# Set LD_LIBRARY_PATH if needed
if [[ -d /opt/xerces-c ]]; then
  export LD_LIBRARY_PATH="$INSTALL_PREFIX/lib:${LD_LIBRARY_PATH:-}"
fi

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

# Post-install check - Load Cloudberry environment
[ -f "${SCRIPT_DIR}/../../../config/cloudberry-env-loader.sh" ] && source "${SCRIPT_DIR}/../../../config/cloudberry-env-loader.sh"
if source_cloudberry_env "$INSTALL_PREFIX"; then
  postgres --version
  postgres --gp-version
else
  log "ERROR: Failed to load Cloudberry environment from $INSTALL_PREFIX"
  exit 1
fi

section_complete "install" "$start_time"
