#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/extensions/postgis/install-postgis.sh
# Purpose  : Install step for PostGIS extension
# Inputs   :
#   - NAME              : component name (should be "postgis")
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

NAME="${NAME:-postgis}"
CLOUDBERRY_DEMO_ENV="$PARTS_DIR/cloudberry/gpAux/gpdemo/gpdemo-env.sh"
start_time=$(date +%s)

section "install: $NAME"

# Load Cloudberry environment for extension detection
[ -f "${SCRIPT_DIR}/../../../config/cloudberry-env-loader.sh" ] && source "${SCRIPT_DIR}/../../../config/cloudberry-env-loader.sh"
if ! source_cloudberry_env /usr/local/cloudberry; then
  log "Warning: Failed to load Cloudberry environment, extension detection may be limited"
fi

if [[ -f "$CLOUDBERRY_DEMO_ENV" ]]; then
  source "$CLOUDBERRY_DEMO_ENV"
else
  log "Warning: gpdemo-env.sh not found at $CLOUDBERRY_DEMO_ENV, extension detection may be limited"
fi

# Navigate to PostGIS build directory
POSTGIS_BUILD_DIR="$PARTS_DIR/$NAME/postgis/build/postgis-3.3.2"
if [[ ! -d "$POSTGIS_BUILD_DIR" ]]; then
  echo "[install-postgis] ERROR: Directory '$POSTGIS_BUILD_DIR' not found"
  exit 1
fi
cd "$POSTGIS_BUILD_DIR"

log "Working directory: $POSTGIS_BUILD_DIR"

# Install with parallel jobs
NPROC=$(nproc 2>/dev/null || echo 4)
log "Using $NPROC parallel jobs"

INSTALL_LOG="install-$(date '+%Y%m%d-%H%M%S').log"
log "Running make install"
sudo make -j"$NPROC" install 2>&1 | tee "$INSTALL_LOG"

# Save PostGIS extensions for final summary
EXTENSIONS_MARKER="/tmp/claude_postgis_extensions.marker"
echo "# PostGIS Extensions Data" > "$EXTENSIONS_MARKER"

if command -v psql >/dev/null 2>&1; then
  # Try database query first
  if psql -q -P pager=off template1 -c \
    "SELECT
       name,
       default_version,
       installed_version,
       CASE WHEN installed_version IS NOT NULL THEN 'INSTALLED' ELSE 'AVAILABLE' END as status
     FROM pg_available_extensions
     WHERE name LIKE '%postgis%'
        OR name LIKE '%address%'
        OR name LIKE '%tiger%'
        OR name IN ('fuzzystrmatch')
     ORDER BY name;" >> "$EXTENSIONS_MARKER" 2>/dev/null; then
    log "Extensions detected via database query"
  else
    log "Database unavailable, using filesystem detection"
    # Fallback: detect extensions from control files
    EXTENSION_DIR="${GPHOME:-/usr/local/cloudberry}/share/postgresql/extension"
    if [[ -d "$EXTENSION_DIR" ]]; then
      echo "name|default_version|installed_version|status" >> "$EXTENSIONS_MARKER"
      find "$EXTENSION_DIR" -name "*.control" -exec basename {} .control \; | \
        grep -E '(postgis|address|tiger|fuzzystrmatch)' | sort | \
        while read -r ext; do
          echo "$ext|unknown|unknown|AVAILABLE" >> "$EXTENSIONS_MARKER"
        done
    fi
  fi
else
  echo "⚠️ psql not found in PATH, using filesystem detection" >&2
  # Fallback: detect extensions from control files
  EXTENSION_DIR="${GPHOME:-/usr/local/cloudberry}/share/postgresql/extension"
  if [[ -d "$EXTENSION_DIR" ]]; then
    echo "name|default_version|installed_version|status" >> "$EXTENSIONS_MARKER"
    find "$EXTENSION_DIR" -name "*.control" -exec basename {} .control \; | \
      grep -E '(postgis|address|tiger|fuzzystrmatch)' | sort | \
      while read -r ext; do
        echo "$ext|unknown|unknown|AVAILABLE" >> "$EXTENSIONS_MARKER"
      done
  fi
fi

section_complete "install: $NAME" "$start_time"