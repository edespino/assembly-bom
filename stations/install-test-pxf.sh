#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/install-test-pxf.sh
# Purpose  : Install and test the 'cloudberry-pxf' extension.
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

section "install and test: $NAME"
start_time=$(date +%s)

# Validate source directory
if [[ ! -f "$PXF_DIR/Makefile" ]]; then
  echo "[install-test-pxf] ERROR: No Makefile found in $PXF_DIR"
  exit 1
fi
cd "$PXF_DIR"

# Load Cloudberry environment
if [[ -f "$CLOUDBERRY_PATH_SH" ]]; then
  source "$CLOUDBERRY_PATH_SH"
else
  echo "[install-test-pxf] ERROR: greenplum_path.sh not found at $CLOUDBERRY_PATH_SH"
  exit 1
fi

if [[ -f "$CLOUDBERRY_DEMO_ENV" ]]; then
  source "$CLOUDBERRY_DEMO_ENV"
else
  echo "[install-test-pxf] ERROR: gpdemo-env.sh not found at $CLOUDBERRY_DEMO_ENV"
  exit 1
fi

# Set required environment variables
export PXF_HOME="/usr/local/pxf"
export PXF_BASE="$HOME/pxf"
export PATH="$PXF_HOME/bin:$PATH"

# Prepare for ginkgo test acknowledgement
touch "$HOME/.ack-ginkgo-rc"
go install github.com/onsi/ginkgo/ginkgo@latest

log "Running make install (includes tests)"
make install 2>&1 | tee "make-${NAME}-install-$(date '+%Y%m%d-%H%M%S').log"

# Check for available extension version
if command -v psql >/dev/null 2>&1; then
  echo "[postgres-extension] Checking available extension version in template1..."
  psql -P pager=off template1 -c \
    "SELECT name, default_version FROM pg_available_extensions WHERE name = '$NAME'" \
    || echo "[postgres-extension] ⚠️ Extension '$NAME' not found in pg_available_extensions"
else
  echo "[postgres-extension] ⚠️ psql not found in PATH, skipping extension version check"
fi

section_complete "install-test-pxf" "$start_time"
