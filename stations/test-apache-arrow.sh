#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/test-apache-arrow.sh
# Purpose  : Run Apache Arrow tests, excluding arrow-ipc-read-write-test.
# Inputs   :
#   - NAME : component name (default: apache-arrow)
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

NAME="${NAME:-apache-arrow}"
BUILD_DIR="parts/$NAME/cpp/build"

section "test"
start_time=$(date +%s)

# Validate build directory
if [[ ! -d "$BUILD_DIR" ]]; then
  echo "[test] ERROR: Build directory '$BUILD_DIR' not found."
  exit 1
fi

cd "$BUILD_DIR"

log "Running tests with ctest (excluding arrow-ipc-read-write-test)"
ctest --output-on-failure -E arrow-ipc-read-write-test | tee "ctest-results-$(date '+%Y.%m.%d-%H.%M.%S').log"

section_complete "test" "$start_time"
