#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/installcheck-optimizer-off-cloudberry.sh
# Purpose  : Run installcheck with optimizer disabled for cloudberry
# --------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

# Set test configuration and delegate to main installcheck script
export TEST_CONFIG_NAME="optimizer-off"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${SCRIPT_DIR}/installcheck-cloudberry.sh"