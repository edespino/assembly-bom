#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/cloudberry/regress-test-pax.sh
# Purpose  : Run PAX storage regression tests for cloudberry
# --------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# Set test configuration and delegate to main installcheck script
export TEST_CONFIG_NAME="pax-regress"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/installcheck.sh"