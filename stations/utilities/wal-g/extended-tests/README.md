# WAL-G Extended Integration Tests

This directory contains an adapted test suite from the native wal-g project, modified to run against a local Cloudberry gpdemo cluster.

## Overview

The extended test suite validates comprehensive wal-g functionality with Apache Cloudberry, including:

- **Full backup and restore workflows**
- **Delta (incremental) backups**
- **Backup retention policies**
- **Append-Optimized (AO) and Column-Oriented (CO) storage**

These tests are based on the official wal-g integration tests from `wal-g/docker/cloudberry_tests/` but adapted to work with your local development environment.

## Test Suite

### 01_full_backup_test.sh
Tests basic backup and restore functionality:
- Creates multiple full backups
- Inserts data between backups
- Stops cluster and deletes data directories
- Restores from latest backup
- Verifies data integrity after restore

**Duration:** ~2-3 minutes

### 02_delta_backup_test.sh
Tests incremental backup functionality:
- Creates one full backup
- Creates multiple delta backups with incremental changes
- Verifies backup chain integrity
- Restores from delta backup
- Validates all data is correctly restored

**Duration:** ~3-4 minutes

### 03_delete_retain_test.sh
Tests backup lifecycle management:
- Creates 5 sequential backups
- Applies retention policy (keep last 2)
- Verifies old backups are deleted
- Ensures retained backups are restorable

**Duration:** ~4-5 minutes

### 04_ao_storage_test.sh
Tests Cloudberry-specific storage formats:
- Creates heap, AO, and CO tables
- Takes backups with different table types
- Validates AO/CO metadata is correctly backed up
- Restores and verifies data integrity with checksums

**Duration:** ~2-3 minutes

## Usage

### Run All Extended Tests
```bash
./assemble.sh --run --component wal-g --steps extended-test
```

### Run Specific Test
```bash
TEST_SUITE=01_full_backup_test ./assemble.sh --run --component wal-g --steps extended-test
```

### Manual Test Execution
```bash
# Source the gpdemo environment
source ~/bom-parts/cloudberry/gpAux/gpdemo/gpdemo-env.sh

# Run a specific test
cd stations/utilities/wal-g/extended-tests
./01_full_backup_test.sh
```

## Test Environment

### Prerequisites
- Cloudberry cluster must be running (gpdemo)
- wal-g installed at `/usr/local/bin/wal-g`
- gpdemo environment sourced

### Configuration
Tests use an isolated configuration:
- **Backup storage:** `~/bom-test-artifacts/wal-g/extended/backups/`
- **Logs:** `~/bom-test-artifacts/wal-g/extended/logs/`
- **Database:** `walg_extended_test` (created/dropped per test)
- **Compression:** Brotli
- **Backend:** Local filesystem

### Test Data
Tests create temporary databases and tables that are cleaned up automatically after each test completes.

## Troubleshooting

### Test Failures

**Cluster not running:**
```bash
./assemble.sh --run --component cloudberry --steps gpstart
```

**Backup timeout:**
- Check segment logs in `~/bom-test-artifacts/wal-g/extended/logs/`
- Verify no orphaned wal-g processes: `pgrep -f wal-g`
- Kill orphaned processes: `pkill -9 -f wal-g`

**Restore failures:**
- Check coordinator log: `tail -f ~/bom-parts/cloudberry/gpAux/gpdemo/datadirs/qddir/demoDataDir-1/log/*.csv`
- Verify segment directories exist and are writable

### Manual Cleanup

**Remove test artifacts:**
```bash
rm -rf ~/bom-test-artifacts/wal-g/extended
```

**Drop test database:**
```bash
psql -c "DROP DATABASE IF EXISTS walg_extended_test;" postgres
```

**Reset cluster:**
```bash
./assemble.sh --run --component cloudberry --steps gprestart
```

## Differences from Native Tests

The tests have been adapted for local Cloudberry development:

| Native Test Assumption | Local Adaptation |
|------------------------|------------------|
| Cloudberry at `/usr/local/gpdb_src/` | Uses `$GPHOME` from environment |
| Port 7000 (hardcoded) | Uses `$PGPORT` from gpdemo-env.sh |
| Docker-based isolation | Runs against local gpdemo cluster |
| S3 backend (for some tests) | Local filesystem backend |
| Segment paths hardcoded | Dynamically discovered from gpdemo |

## Adding New Tests

To add a new test:

1. Create test script: `stations/utilities/wal-g/extended-tests/05_new_test.sh`
2. Source utility functions: `source "$(dirname "$0")/util.sh"`
3. Implement test logic using utility functions
4. Add to `TESTS` array in `extended-test.sh`
5. Make executable: `chmod +x 05_new_test.sh`

### Template
```bash
#!/bin/bash
set -e -x

TEST_NAME="My New Test"
source "$(dirname "$0")/util.sh"

echo "========================================"
echo "Test: $TEST_NAME"
echo "========================================"

# Your test logic here
insert_data
run_backup_logged "${WALG_CONFIG_FILE}" "${COORDINATOR_DATA_DIRECTORY}" "--full"

# Verify results
verify_backup_count 1 "$(/usr/local/bin/wal-g backup-list --config=${WALG_CONFIG_FILE})"

echo ""
echo "✓ $TEST_NAME PASSED"
```

## References

- **WAL-G Documentation:** https://github.com/wal-g/wal-g/blob/master/docs/Greenplum.md
- **Native Test Source:** `~/bom-parts/wal-g/docker/cloudberry_tests/`
- **Cloudberry gpdemo:** `~/bom-parts/cloudberry/gpAux/gpdemo/`

## Notes

- Tests run sequentially (not in parallel) to avoid cluster contention
- Each test cleans up the `walg_extended_test` database after completion
- Test artifacts are preserved for debugging at `~/bom-test-artifacts/wal-g/extended/`
- WAL archiving is **not** configured by default (backups only, no continuous archiving)
- For continuous archiving tests, see the native wal-g docker-based tests
