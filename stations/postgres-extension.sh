#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/postgres-extension.sh
# Purpose  : Generic build/install/test for simple PostgreSQL extensions
# Inputs   :
#   - NAME                        : name of the component (required)
#   - INSTALL_PREFIX              : defaults to /usr/local if unset
#   - DISABLE_EXTENSION_TESTS     : skips installcheck if set true/1
#   - USE_PGXS                    : set to 1 to build using PGXS infrastructure
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

NAME="${NAME:?Component NAME is required}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local}"
USE_PGXS="${USE_PGXS:-}"
EXT_DIR="parts/$NAME"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLOUDBERRY_DEMO_ENV="$PROJECT_ROOT/parts/cloudberry/gpAux/gpdemo/gpdemo-env.sh"

section "build/install PostgreSQL extension: $NAME"
start_time=$(date +%s)

# Validate source directory
if [[ ! -f "$EXT_DIR/Makefile" ]]; then
  echo "[postgres-extension] ERROR: No Makefile found in $EXT_DIR"
  exit 1
fi

cd "$EXT_DIR"

# Load environment for core system
if [[ -f /usr/local/cloudberry/greenplum_path.sh ]]; then
  # shellcheck disable=SC1091
  source /usr/local/cloudberry/greenplum_path.sh
else
  echo "[postgres-extension] ERROR: greenplum_path.sh not found"
  exit 1
fi

# Build and install
if [[ -n "$USE_PGXS" ]]; then
  log "Building and installing extension with USE_PGXS=$USE_PGXS"
  make USE_PGXS="$USE_PGXS" 2>&1 | tee "make-${NAME}-build-$(date '+%Y%m%d-%H%M%S').log"
  make USE_PGXS="$USE_PGXS" install 2>&1 | tee "make-${NAME}-install-$(date '+%Y%m%d-%H%M%S').log"
else
  log "Building and installing extension using in-tree build"
  make 2>&1 | tee "make-${NAME}-build-$(date '+%Y%m%d-%H%M%S').log"
  make install 2>&1 | tee "make-${NAME}-install-$(date '+%Y%m%d-%H%M%S').log"
fi

# Check for available extension version (requires cloudberry demo env)
if [[ -f "$CLOUDBERRY_DEMO_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$CLOUDBERRY_DEMO_ENV"
  if command -v psql >/dev/null 2>&1; then
    echo "[postgres-extension] Checking available extension version in template1..."
    psql -P pager=off template1 -c \
      "SELECT name, default_version FROM pg_available_extensions WHERE name = '$NAME'" \
      || echo "[postgres-extension] ⚠️ Extension '$NAME' not found in pg_available_extensions"
  else
    echo "[postgres-extension] ⚠️ psql not found in PATH, skipping extension version check"
  fi
else
  log "Skipping extension version check — $CLOUDBERRY_DEMO_ENV not found"
fi

# Normalize boolean value for test skipping
case "${DISABLE_EXTENSION_TESTS:-false}" in
  1 | true | TRUE | True) SKIP_TESTS=true ;;
  *)                      SKIP_TESTS=false ;;
esac

# Optionally run installcheck
if [[ "$SKIP_TESTS" == false ]]; then
  if [[ -f "$CLOUDBERRY_DEMO_ENV" ]]; then
    # shellcheck disable=SC1090
    source "$CLOUDBERRY_DEMO_ENV"
    log "Running installcheck for $NAME"
    if [[ -n "$USE_PGXS" ]]; then
      make USE_PGXS="$USE_PGXS" installcheck
    else
      make installcheck
    fi
  else
    log "Skipping installcheck — $CLOUDBERRY_DEMO_ENV not found"
  fi
else
  log "Extension tests disabled via DISABLE_EXTENSION_TESTS=${DISABLE_EXTENSION_TESTS:-unset}"
fi

section_complete "postgres-extension" "$start_time"

