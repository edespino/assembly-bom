#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/installcheck-cloudberry.sh
# Purpose  : Installcheck script for the 'cloudberry'
# Inputs   :
#   - NAME           : name of the component (default: cloudberry)
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

NAME="${NAME:-cloudberry}"
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/$NAME}"
BUILD_DIR="parts/$NAME"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLOUDBERRY_PATH_SH="/usr/local/cloudberry/greenplum_path.sh"
CLOUDBERRY_DEMO_ENV="$PROJECT_ROOT/parts/cloudberry/gpAux/gpdemo/gpdemo-env.sh"

# Test configuration - can be overridden by environment
TEST_CONFIG_NAME="${TEST_CONFIG_NAME:-default}"

section "installcheck: $NAME"
start_time=$(date +%s)

# Ensure source tree exists
if [[ ! -d "$BUILD_DIR" ]]; then
  echo "[installcheck] ERROR: Build directory '$BUILD_DIR' not found"
  exit 1
fi

cd "$BUILD_DIR"

# Load Cloudberry environment
if [[ -f "$CLOUDBERRY_PATH_SH" ]]; then
  # shellcheck disable=SC1090
  source "$CLOUDBERRY_PATH_SH"
else
  echo "[installcheck-cloudberry] ERROR: greenplum_path.sh not found at $CLOUDBERRY_PATH_SH"
  exit 1
fi

# Load demo cluster environment if available
if [[ -f "$CLOUDBERRY_DEMO_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$CLOUDBERRY_DEMO_ENV"
  log "Loaded demo cluster environment from $CLOUDBERRY_DEMO_ENV"
else
  log "WARNING: Demo cluster environment not found at $CLOUDBERRY_DEMO_ENV"
  log "Some installcheck tests may require a running cluster"
fi

# Parse test configuration from bom.yaml
log "Reading test configuration: $TEST_CONFIG_NAME"
BOM_FILE="$PROJECT_ROOT/bom.yaml"

if [[ -f "$BOM_FILE" ]]; then
  # Extract test config using yq (assuming yq v4+ is available)
  if command -v yq >/dev/null 2>&1; then
    TEST_PGOPTIONS=$(yq eval ".products.cloudberry.components.core[] | select(.name == \"$NAME\") | .test_configs[] | select(.name == \"$TEST_CONFIG_NAME\") | .pgoptions" "$BOM_FILE" 2>/dev/null || echo "")
    TEST_TARGET=$(yq eval ".products.cloudberry.components.core[] | select(.name == \"$NAME\") | .test_configs[] | select(.name == \"$TEST_CONFIG_NAME\") | .target" "$BOM_FILE" 2>/dev/null || echo "installcheck")
    TEST_DIRECTORY=$(yq eval ".products.cloudberry.components.core[] | select(.name == \"$NAME\") | .test_configs[] | select(.name == \"$TEST_CONFIG_NAME\") | .directory" "$BOM_FILE" 2>/dev/null || echo "")
    TEST_DESCRIPTION=$(yq eval ".products.cloudberry.components.core[] | select(.name == \"$NAME\") | .test_configs[] | select(.name == \"$TEST_CONFIG_NAME\") | .description" "$BOM_FILE" 2>/dev/null || echo "")
  else
    log "WARNING: yq not found, using default test configuration"
    TEST_PGOPTIONS=""
    TEST_TARGET="installcheck"
    TEST_DIRECTORY=""
    TEST_DESCRIPTION="Default installcheck tests"
  fi
else
  log "WARNING: bom.yaml not found, using default test configuration"
  TEST_PGOPTIONS=""
  TEST_TARGET="installcheck"
  TEST_DIRECTORY=""
  TEST_DESCRIPTION="Default installcheck tests"
fi

# Clean up yq output (remove quotes and "null" values)
TEST_PGOPTIONS=$(echo "$TEST_PGOPTIONS" | sed 's/^"//;s/"$//;s/^null$//')
TEST_TARGET=$(echo "$TEST_TARGET" | sed 's/^"//;s/"$//;s/^null$/installcheck/')
TEST_DIRECTORY=$(echo "$TEST_DIRECTORY" | sed 's/^"//;s/"$//;s/^null$//')
TEST_DESCRIPTION=$(echo "$TEST_DESCRIPTION" | sed 's/^"//;s/"$//;s/^null$//')

# Validate test configuration exists
if [[ -z "$TEST_TARGET" || "$TEST_TARGET" == "installcheck" && "$TEST_CONFIG_NAME" != "default" ]]; then
  # Check if the config name exists in bom.yaml
  CONFIG_EXISTS=$(yq eval ".products.cloudberry.components.core[] | select(.name == \"$NAME\") | .test_configs[] | select(.name == \"$TEST_CONFIG_NAME\") | .name" "$BOM_FILE" 2>/dev/null || echo "")
  if [[ -z "$CONFIG_EXISTS" ]]; then
    echo "[installcheck-cloudberry] ERROR: Test configuration '$TEST_CONFIG_NAME' not found"
    echo "[installcheck-cloudberry] Available configurations:"
    yq eval ".products.cloudberry.components.core[] | select(.name == \"$NAME\") | .test_configs[].name" "$BOM_FILE" 2>/dev/null | sed 's/^/  - /' || echo "  (none)"
    exit 1
  fi
fi

# Ensure we have a valid target
if [[ -z "$TEST_TARGET" ]]; then
  TEST_TARGET="installcheck"
  log "WARNING: No target specified, defaulting to 'installcheck'"
fi

# Determine test directory
if [[ -n "$TEST_DIRECTORY" ]]; then
  FULL_TEST_DIR="$HOME/assembly-bom/parts/$NAME/$TEST_DIRECTORY"
else
  FULL_TEST_DIR="$HOME/assembly-bom/parts/$NAME"
fi

# Log test configuration
log "Test Configuration: $TEST_CONFIG_NAME"
log "Description: $TEST_DESCRIPTION"
log "Target: $TEST_TARGET"
log "Directory: $FULL_TEST_DIR"
log "PGOPTIONS: $TEST_PGOPTIONS"

# Run the test
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
LOG_FILE="make-${NAME}-${TEST_CONFIG_NAME}-${TIMESTAMP}.log"

if [[ -n "$TEST_PGOPTIONS" ]]; then
  log "Running: make $TEST_TARGET PGOPTIONS='$TEST_PGOPTIONS' -C $FULL_TEST_DIR"
  make "$TEST_TARGET" PGOPTIONS="$TEST_PGOPTIONS" -C "$FULL_TEST_DIR" | tee "$LOG_FILE"
else
  log "Running: make $TEST_TARGET -C $FULL_TEST_DIR"
  make "$TEST_TARGET" -C "$FULL_TEST_DIR" | tee "$LOG_FILE"
fi

section_complete "installcheck: $NAME" "$start_time"