#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/configure-pg_jieba.sh
# Purpose  : Configure script for the pg_jieba PostgreSQL extension using CMake.
# Inputs   :
#   - CONFIGURE_FLAGS: Additional CMake flags passed from bom.yaml (optional)
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
[ -f config/env.sh ] && source config/env.sh

# Setup
NAME="${NAME:-pg_jieba}"
BUILD_DIR="parts/$NAME/build"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLOUDBERRY_PATH_SH="/usr/local/cloudberry/greenplum_path.sh"

# Prepare build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

section "configure"
start_time=$(date +%s)

# Load Cloudberry environment
if [[ -f "$CLOUDBERRY_PATH_SH" ]]; then
  source "$CLOUDBERRY_PATH_SH"
else
  echo "[configure-pg_jieba] ERROR: greenplum_path.sh not found at $CLOUDBERRY_PATH_SH" >&2
  exit 1
fi

# Ensure pg_config is available
if ! command -v pg_config > /dev/null; then
  echo "❌ Error: pg_config not found in PATH after sourcing environment." >&2
  exit 1
fi

# Derive PostgreSQL paths using pg_config
PG_INCLUDEDIR=$(pg_config --includedir)
PG_LIBDIR=$(pg_config --libdir)
PG_CFLAGS=$(pg_config --cflags)
PG_LDFLAGS=$(pg_config --ldflags)

# Build CMake command
CMAKE_CMD="cmake .. \\
  -DCMAKE_C_FLAGS=\"$PG_CFLAGS\" \\
  -DCMAKE_EXE_LINKER_FLAGS=\"$PG_LDFLAGS\" \\
  -DPostgreSQL_INCLUDE_DIR=\"$PG_INCLUDEDIR\" \\
  -DPostgreSQL_TYPE_INCLUDE_DIR=\"$PG_INCLUDEDIR/postgresql/server\" \\
  -DPostgreSQL_LIBRARY=\"$PG_LIBDIR/libpq.so\" \\
  ${CONFIGURE_FLAGS:-}"

log "Running cmake with:"
echo "  $CMAKE_CMD"
echo ""

# Execute
# shellcheck disable=SC2086
eval $CMAKE_CMD 2>&1 | tee "configure-$(date '+%Y%m%d-%H%M%S').log"

section_complete "configure" "$start_time"
