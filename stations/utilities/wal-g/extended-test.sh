#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/utilities/wal-g/extended-test.sh
# Purpose  : Extended integration test suite for wal-g with Cloudberry
#            Runs native wal-g tests adapted for local gpdemo cluster
# Inputs   :
#   - NAME           : name of the component (default: wal-g)
#   - TEST_SUITE     : specific test to run (optional, runs all if not set)
# --------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# Load shared functions
COMMON_SH="${SCRIPT_DIR}/../../../lib/common.sh"
if [ -f "${COMMON_SH}" ]; then
  # shellcheck disable=SC1090
  source "${COMMON_SH}"
else
  echo "[$SCRIPT_NAME] Missing library: ${COMMON_SH}" >&2
  exit 1
fi

# shellcheck disable=SC1091
[ -f config/env.sh ] && source config/env.sh

NAME="${NAME:-wal-g}"
WALG_BIN="/usr/local/bin/wal-g"
TEST_SUITE="${TEST_SUITE:-all}"

section "extended-test: $NAME"
start_time=$(date +%s)

# Verify wal-g binary exists
if [[ ! -f "$WALG_BIN" ]]; then
  echo "[extended-test-wal-g] ERROR: wal-g binary not found at $WALG_BIN"
  echo "[extended-test-wal-g] Run: ./assemble.sh --run --component wal-g --steps install"
  exit 1
fi

# Source the gpdemo environment
GPDEMO_ENV="${PARTS_DIR}/cloudberry/gpAux/gpdemo/gpdemo-env.sh"
if [[ -f "${GPDEMO_ENV}" ]]; then
    log "Sourcing gpdemo environment from ${GPDEMO_ENV}"
    source "${GPDEMO_ENV}"
else
    echo "[extended-test-wal-g] ERROR: gpdemo-env.sh not found at ${GPDEMO_ENV}"
    echo "[extended-test-wal-g] Run: ./assemble.sh --run --component cloudberry --steps create-demo-cluster"
    exit 1
fi

# Check cluster status
log "Checking Cloudberry cluster status..."
if ! gpstate -q &>/dev/null; then
  echo "[extended-test-wal-g] ERROR: Cloudberry cluster is not running"
  echo "[extended-test-wal-g] Start cluster with: ./assemble.sh --run --component cloudberry --steps gpstart"
  exit 1
fi
log "  ✓ Cluster is running (PGPORT=$PGPORT)"

# Check for existing wal-g processes
log "Checking for running wal-g processes..."
WALG_PIDS=$(pgrep -f "wal-g.*backup-push" || true)
if [[ -n "$WALG_PIDS" ]]; then
  log "  ⚠ Found running wal-g processes: $WALG_PIDS"
  log "  - Automatically terminating processes for clean test run"
  echo "$WALG_PIDS" | xargs kill -9 2>/dev/null || true
  sleep 2
  log "  ✓ Processes terminated"
else
  log "  ✓ No existing wal-g processes found"
fi

# Setup test directories
TEST_BASE_DIR="${PARTS_DIR}/../bom-test-artifacts/wal-g/extended"
WALG_BACKUP_DIR="$TEST_BASE_DIR/backups"
WALG_LOG_DIR="$TEST_BASE_DIR/logs"
WALG_CONFIG_FILE="$TEST_BASE_DIR/walg-config.json"
WALG_SEG_STATES_DIR="$TEST_BASE_DIR/seg_states"

# Clean up any previous test runs
if [[ -d "$TEST_BASE_DIR" ]]; then
  log "Cleaning up previous test artifacts: $TEST_BASE_DIR"
  rm -rf "$TEST_BASE_DIR"
fi

log "Creating test directories..."
mkdir -p "$WALG_BACKUP_DIR"
mkdir -p "$WALG_LOG_DIR"
mkdir -p "$WALG_SEG_STATES_DIR"
log "  - Test artifacts: $TEST_BASE_DIR"
log "  - Backup directory: $WALG_BACKUP_DIR"
log "  - Log directory: $WALG_LOG_DIR"

# Create wal-g configuration file
log "Creating wal-g configuration..."
cat > "$WALG_CONFIG_FILE" <<EOF
{
  "WALG_FILE_PREFIX": "$WALG_BACKUP_DIR",
  "WALG_GP_LOGS_DIR": "$WALG_LOG_DIR",
  "WALG_GP_SEG_STATES_DIR": "$WALG_SEG_STATES_DIR",
  "WALG_GP_SEG_POLL_INTERVAL": "1s",
  "WALG_GP_SEG_POLL_RETRIES": "60",
  "WALG_GP_RELATIVE_RECOVERY_CONF_PATH": "conf.d/recovery.conf",
  "PGDATA": "$COORDINATOR_DATA_DIRECTORY",
  "PGHOST": "localhost",
  "PGPORT": "$PGPORT",
  "PGUSER": "$USER",
  "PGDATABASE": "postgres",
  "WALG_COMPRESSION_METHOD": "brotli",
  "WALG_DELTA_MAX_STEPS": "5"
}
EOF
log "  - Config file: $WALG_CONFIG_FILE"
log "  - Using PG 12+ recovery method (conf.d/recovery.conf)"

# Enable WAL archiving for delta backups
log ""
log "Enabling WAL archiving for delta backup support..."

# Update postgresql.conf for coordinator (content-id = -1)
COORDINATOR_CONF="$COORDINATOR_DATA_DIRECTORY/postgresql.conf"
if [[ -f "$COORDINATOR_CONF" ]]; then
  log "  - Configuring coordinator WAL archiving (content-id=-1)"

  # Remove any existing archive settings
  sed -i '/^archive_mode/d' "$COORDINATOR_CONF"
  sed -i '/^archive_command/d' "$COORDINATOR_CONF"
  sed -i '/^wal_level/d' "$COORDINATOR_CONF"
  sed -i '/^archive_timeout/d' "$COORDINATOR_CONF"

  # Add new archive settings (using seg wal-push with content-id)
  echo "" >> "$COORDINATOR_CONF"
  echo "# WAL-G archiving configuration (added by extended-test.sh)" >> "$COORDINATOR_CONF"
  echo "wal_level = archive" >> "$COORDINATOR_CONF"
  echo "archive_mode = on" >> "$COORDINATOR_CONF"
  echo "archive_timeout = 600" >> "$COORDINATOR_CONF"
  echo "archive_command = '/usr/bin/timeout 60 /usr/bin/wal-g seg wal-push %p --content-id=-1 --config=$WALG_CONFIG_FILE'" >> "$COORDINATOR_CONF"

  log "  ✓ Coordinator configured"
fi

# Update postgresql.conf for all segments
GPDEMO_DIR="${PARTS_DIR}/cloudberry/gpAux/gpdemo"
segment_num=0
for seg_dir in "$GPDEMO_DIR"/datadirs/dbfast*/demoDataDir*; do
  if [[ -d "$seg_dir" && -f "$seg_dir/postgresql.conf" ]]; then
    seg_name=$(basename "$seg_dir")
    log "  - Configuring segment: $seg_name (content-id=$segment_num)"

    # Remove any existing archive settings
    sed -i '/^archive_mode/d' "$seg_dir/postgresql.conf"
    sed -i '/^archive_command/d' "$seg_dir/postgresql.conf"
    sed -i '/^wal_level/d' "$seg_dir/postgresql.conf"
    sed -i '/^archive_timeout/d' "$seg_dir/postgresql.conf"

    # Add new archive settings (using seg wal-push with content-id)
    echo "" >> "$seg_dir/postgresql.conf"
    echo "# WAL-G archiving configuration (added by extended-test.sh)" >> "$seg_dir/postgresql.conf"
    echo "wal_level = archive" >> "$seg_dir/postgresql.conf"
    echo "archive_mode = on" >> "$seg_dir/postgresql.conf"
    echo "archive_timeout = 600" >> "$seg_dir/postgresql.conf"
    echo "archive_command = '/usr/bin/timeout 60 /usr/bin/wal-g seg wal-push %p --content-id=$segment_num --config=$WALG_CONFIG_FILE'" >> "$seg_dir/postgresql.conf"

    ((segment_num++))
  fi
done
log "  ✓ All segments configured"

# Restart PostgreSQL cluster (required for archive_mode change)
log "  - Restarting cluster to enable archive_mode..."
gpstop -ar -a
log "  ✓ Cluster restarted"
log "  ✓ WAL archiving enabled"

# Export configuration for test scripts
export WALG_CONFIG_FILE
export WALG_LOG_DIR
export WALG_BACKUP_DIR

log ""
log "========================================="
log "WAL-G Extended Integration Test Suite"
log "========================================="
log "Configuration:"
log "  - PGHOST: localhost"
log "  - PGPORT: $PGPORT"
log "  - PGUSER: $USER"
log "  - COORDINATOR_DATA_DIRECTORY: $COORDINATOR_DATA_DIRECTORY"
log "  - Storage backend: Local filesystem"
log "  - Test suite: $TEST_SUITE"
log ""

# Define available tests
TEST_DIR="${SCRIPT_DIR}/extended-tests"
TESTS=(
  "01_full_backup_test.sh"
  "02_delta_backup_test.sh"
  "03_delete_retain_test.sh"
  "04_ao_storage_test.sh"
)

# Make test scripts executable
chmod +x "$TEST_DIR"/*.sh

# Track test results
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0
declare -a FAILED_TEST_NAMES

# Run tests
for test_script in "${TESTS[@]}"; do
  test_path="${TEST_DIR}/${test_script}"
  test_name=$(basename "$test_script" .sh)

  # Skip if specific test requested and this isn't it
  if [[ "$TEST_SUITE" != "all" && "$test_name" != "$TEST_SUITE" ]]; then
    log "Skipping $test_name (not requested)"
    ((SKIPPED_TESTS++))
    continue
  fi

  log ""
  log "========================================="
  log "Running: $test_name"
  log "========================================="

  if [[ -f "$test_path" ]]; then
    if bash "$test_path"; then
      log "✓ $test_name PASSED"
      ((PASSED_TESTS++))
    else
      log "✗ $test_name FAILED"
      ((FAILED_TESTS++))
      FAILED_TEST_NAMES+=("$test_name")
    fi
  else
    log "⚠ Test script not found: $test_path"
    ((SKIPPED_TESTS++))
  fi

  # Clean up between tests
  log "Cleaning up test database..."
  psql -p "$PGPORT" -c "DROP DATABASE IF EXISTS walg_extended_test;" postgres 2>/dev/null || true

  # Small delay between tests
  sleep 2
done

# Final cleanup
log ""
log "========================================="
log "Final Cleanup"
log "========================================="
psql -p "$PGPORT" -c "DROP DATABASE IF EXISTS walg_extended_test;" postgres 2>/dev/null || true
log "  ✓ Test database cleaned up"

# Disable WAL archiving
log "Disabling WAL archiving..."
if [[ -f "$COORDINATOR_CONF" ]]; then
  sed -i '/# WAL-G archiving configuration/d' "$COORDINATOR_CONF"
  sed -i '/^wal_level = archive/d' "$COORDINATOR_CONF"
  sed -i '/^archive_mode = on/d' "$COORDINATOR_CONF"
  sed -i '/^archive_timeout = /d' "$COORDINATOR_CONF"
  sed -i '/^archive_command = /d' "$COORDINATOR_CONF"
  log "  ✓ Coordinator archiving disabled"
fi

for seg_dir in "$GPDEMO_DIR"/datadirs/dbfast*/demoDataDir*; do
  if [[ -d "$seg_dir" && -f "$seg_dir/postgresql.conf" ]]; then
    sed -i '/# WAL-G archiving configuration/d' "$seg_dir/postgresql.conf"
    sed -i '/^wal_level = archive/d' "$seg_dir/postgresql.conf"
    sed -i '/^archive_mode = on/d' "$seg_dir/postgresql.conf"
    sed -i '/^archive_timeout = /d' "$seg_dir/postgresql.conf"
    sed -i '/^archive_command = /d' "$seg_dir/postgresql.conf"
  fi
done

gpstop -u -a &>/dev/null
log "  ✓ WAL archiving disabled and configuration reloaded"

# Summary
log ""
log "========================================="
log "Test Summary"
log "========================================="
log "Total tests: $((PASSED_TESTS + FAILED_TESTS + SKIPPED_TESTS))"
log "  ✓ Passed: $PASSED_TESTS"
log "  ✗ Failed: $FAILED_TESTS"
if [[ $SKIPPED_TESTS -gt 0 ]]; then
  log "  ⊘ Skipped: $SKIPPED_TESTS"
fi

if [[ $FAILED_TESTS -gt 0 ]]; then
  log ""
  log "Failed tests:"
  for failed_test in "${FAILED_TEST_NAMES[@]}"; do
    log "  - $failed_test"
  done
fi

log ""
log "Test artifacts preserved at:"
log "  - Base directory: $TEST_BASE_DIR"
log "  - Backups: $WALG_BACKUP_DIR"
log "  - Logs: $WALG_LOG_DIR"
log "  - Config: $WALG_CONFIG_FILE"
log ""
log "To cleanup test files:"
log "  rm -rf $TEST_BASE_DIR"

section_complete "extended-test-wal-g" "$start_time"

# Exit with failure if any tests failed
if [[ $FAILED_TESTS -gt 0 ]]; then
  exit 1
fi

log ""
log "========================================="
log "All tests PASSED!"
log "========================================="
