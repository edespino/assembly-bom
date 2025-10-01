#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/pax-test-cloudberry.sh
# Purpose  : Run PAX-specific tests for cloudberry
# --------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# Set test configuration and delegate to main installcheck script
export TEST_CONFIG_NAME="pax-test"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/installcheck-cloudberry.sh"