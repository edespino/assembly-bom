#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/test-pg_filedump.sh
# Purpose  : Build script for the 'pg_filedump' extension.
# Inputs   :
#   - NAME           : name of the component (default: pg_filedump)
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

NAME="${NAME:-pg_filedump}"
PG_FILEDUMP_DIR="parts/$NAME"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLOUDBERRY_PATH_SH="/usr/local/cloudberry/greenplum_path.sh"
CLOUDBERRY_DEMO_ENV="$PROJECT_ROOT/parts/cloudberry/gpAux/gpdemo/gpdemo-env.sh"

section "test: $NAME"
start_time=$(date +%s)

cd "$PG_FILEDUMP_DIR"

# Load Cloudberry environment
if [[ -f "$CLOUDBERRY_PATH_SH" ]]; then
  source "$CLOUDBERRY_PATH_SH"
else
  echo "[test-pg_filedump] ERROR: greenplum_path.sh not found at $CLOUDBERRY_PATH_SH"
  exit 1
fi

if [[ -f "$CLOUDBERRY_DEMO_ENV" ]]; then
  source "$CLOUDBERRY_DEMO_ENV"
else
  echo "[test-pg_filedump] ERROR: gpdemo-env.sh not found at $CLOUDBERRY_DEMO_ENV"
  exit 1
fi

log "Running make installcheck"
make installcheck 2>&1 | tee "make-${NAME}-test-$(date '+%Y%m%d-%H%M%S').log"

section_complete "test-pg_filedump" "$start_time"

