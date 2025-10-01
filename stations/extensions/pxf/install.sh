#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/extensions/pxf/install-pxf.sh
# Purpose  : Install the 'pxf' extension and list installed extensions.
# Inputs   :
#   - NAME           : name of the component (default: pxf)
#   - INSTALL_PREFIX : not used, but accepted for compatibility
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

NAME="${NAME:-pxf}"
PXF_DIR="$PARTS_DIR/$NAME"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLOUDBERRY_DEMO_ENV="$PARTS_DIR/cloudberry/gpAux/gpdemo/gpdemo-env.sh"

section "install: $NAME"
start_time=$(date +%s)

# Validate source directory
if [[ ! -f "$PXF_DIR/Makefile" ]]; then
  echo "[install-pxf] ERROR: No Makefile found in $PXF_DIR"
  exit 1
fi
cd "$PXF_DIR"

# Load Cloudberry environment
[ -f "${SCRIPT_DIR}/../../../config/cloudberry-env-loader.sh" ] && source "${SCRIPT_DIR}/../../../config/cloudberry-env-loader.sh"
if ! source_cloudberry_env /usr/local/cloudberry; then
  echo "[install-pxf] ERROR: Failed to load Cloudberry environment"
  exit 1
fi

if [[ -f "$CLOUDBERRY_DEMO_ENV" ]]; then
  source "$CLOUDBERRY_DEMO_ENV"
else
  echo "[install-pxf] ERROR: gpdemo-env.sh not found at $CLOUDBERRY_DEMO_ENV"
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

# Save PXF extensions for final summary only
if command -v psql >/dev/null 2>&1; then
  # Write extensions to a marker file that the final summary can find
  EXTENSIONS_MARKER="/tmp/claude_pxf_extensions.marker"
  echo "# PXF Extensions Data" > "$EXTENSIONS_MARKER"
  psql -q -P pager=off template1 -c \
    "SELECT
       name,
       default_version,
       installed_version,
       CASE WHEN installed_version IS NOT NULL THEN 'INSTALLED' ELSE 'AVAILABLE' END as status
     FROM pg_available_extensions
     WHERE name LIKE '%pxf%'
     ORDER BY name;" >> "$EXTENSIONS_MARKER" 2>/dev/null
else
  echo "⚠️ psql not found in PATH, skipping PXF extension check"
fi

section_complete "install: $NAME" "$start_time"