#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/build-install-pg_jieba.sh
# Purpose  : Build and install the pg_jieba PostgreSQL extension.
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

# Load shared environment
# shellcheck disable=SC1091
[ -f config/env.sh ] && . config/env.sh

NAME="${NAME:-pg_jieba}"
BUILD_DIR="parts/$NAME/build"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLOUDBERRY_PATH_SH="/usr/local/cloudberry/greenplum_path.sh"
CLOUDBERRY_DEMO_ENV="$PROJECT_ROOT/parts/cloudberry/gpAux/gpdemo/gpdemo-env.sh"

# Load Cloudberry environment
if [[ -f "$CLOUDBERRY_PATH_SH" ]]; then
  source "$CLOUDBERRY_PATH_SH"
else
  echo "[build-install-pg_jieba] ERROR: greenplum_path.sh not found at $CLOUDBERRY_PATH_SH" >&2
  exit 1
fi

section "build and install"
start_time=$(date +%s)

# Verify build directory exists
if [[ ! -d "$BUILD_DIR" ]]; then
  echo "[build-install] ERROR: Build directory '$BUILD_DIR' not found."
  echo "[build-install] Did you run the configure script?"
  exit 1
fi

cd "$BUILD_DIR"

log "Running make"
make 2>&1 | tee "make-${NAME}-build-$(date '+%Y%m%d-%H%M%S').log"

log "Running make install"
make install 2>&1 | tee "make-${NAME}-install-$(date '+%Y%m%d-%H%M%S').log"

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

section_complete "build and install" "$start_time"
