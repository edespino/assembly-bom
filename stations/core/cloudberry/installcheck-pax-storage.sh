#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/cloudberry/installcheck-pax-storage.sh
# Purpose  : Run PAX storage installcheck tests for cloudberry
# --------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# Set test configuration and delegate to main installcheck script
export TEST_CONFIG_NAME="pax-storage"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/installcheck.sh"