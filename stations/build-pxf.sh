#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/build-pxf.sh
# Purpose  : Build script for the 'cloudberry-pxf' extension.
# Inputs   :
#   - NAME           : name of the component (default: cloudberry-pxf)
#   - INSTALL_PREFIX : not used, but accepted for compatibility
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

# shellcheck disable=SC1091
[ -f config/env.sh ] && source config/env.sh

NAME="${NAME:-cloudberry-pxf}"
PXF_DIR="parts/$NAME"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLOUDBERRY_PATH_SH="/usr/local/cloudberry/greenplum_path.sh"
CLOUDBERRY_DEMO_ENV="$PROJECT_ROOT/parts/cloudberry/gpAux/gpdemo/gpdemo-env.sh"

section "build: $NAME"
start_time=$(date +%s)

# Validate PXF source directory
if [[ ! -f "$PXF_DIR/Makefile" ]]; then
  echo "[build-pxf] ERROR: No Makefile found in $PXF_DIR"
  exit 1
fi
cd "$PXF_DIR"

# Load Cloudberry environment
if [[ -f "$CLOUDBERRY_PATH_SH" ]]; then
  source "$CLOUDBERRY_PATH_SH"
else
  echo "[build-pxf] ERROR: greenplum_path.sh not found at $CLOUDBERRY_PATH_SH"
  exit 1
fi

if [[ -f "$CLOUDBERRY_DEMO_ENV" ]]; then
  source "$CLOUDBERRY_DEMO_ENV"
else
  echo "[build-pxf] ERROR: gpdemo-env.sh not found at $CLOUDBERRY_DEMO_ENV"
  exit 1
fi

# Set required environment variables for PXF
export PXF_HOME="/usr/local/pxf"
export PXF_BASE="$HOME/pxf"
export PATH="$PXF_HOME/bin:$PATH"

log "Building $NAME using make"
make 2>&1 | tee "make-${NAME}-build-$(date '+%Y%m%d-%H%M%S').log"

section_complete "build-pxf" "$start_time"

