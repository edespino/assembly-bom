# WAL-G Testing Guide

## Overview

This guide covers testing WAL-G with Cloudberry Database, including the automated test suite and manual testing procedures.

## Automated Test Suite

### Running the Test Suite

The easiest way to test WAL-G:

```bash
./assemble.sh --run --component wal-g --steps test
```

### Prerequisites

Before running tests:

1. **Cloudberry cluster must be running**:
   ```bash
   source ~/bom-parts/cloudberry/gpAux/gpdemo/gpdemo-env.sh
   gpstate -q
   ```

2. **WAL-G must be installed**:
   ```bash
   /usr/local/wal-g/bin/wal-g --version
   ```

### Test Coverage

The test suite performs 12 comprehensive tests:

1. **Version Check** - Verifies wal-g binary and version
2. **Database Creation** - Creates test database with sample data
3. **Configuration Check** - Validates PostgreSQL settings
4. **Full Backup** - Creates full backup of all segments
5. **Backup Listing** - Lists and validates backups
6. **Backup Metadata** - Retrieves backup details
7. **Incremental Data** - Adds more test data
8. **Delta Backup** - Creates incremental backup
9. **Backup Verification** - Checks backup storage
10. **Restore Preparation** - Validates restore process
11. **Data Integrity** - Verifies data consistency
12. **Cleanup** - Optional cleanup of test resources

### Test Artifacts

All test artifacts are stored in:
```
~/bom-test-artifacts/wal-g/
├── backups/           # WAL-G backup storage
├── logs/              # Coordinator and segment logs
├── seg_states/        # Segment coordination files
├── walg-config.json   # Test configuration
├── backup-push.log    # Full backup log
└── backup-push-delta.log  # Delta backup log
```

### Expected Results

Successful test run:
```
All tests PASSED!
✓ Test 1:  Version check - PASSED
✓ Test 2:  Database creation - PASSED
...
✓ Test 12: Cleanup - COMPLETED
```

Test duration: ~3-5 seconds

## Manual Testing

### Basic Backup Test

Create a simple backup:

```bash
# Source environment
source ~/bom-parts/cloudberry/gpAux/gpdemo/gpdemo-env.sh

# Set up configuration
export WALG_FILE_PREFIX="/tmp/walg-manual-test"
export PGDATA="$COORDINATOR_DATA_DIRECTORY"
mkdir -p "$WALG_FILE_PREFIX"

# Create backup
wal-g backup-push --full --config=/dev/stdin <<EOF
{
  "WALG_FILE_PREFIX": "$WALG_FILE_PREFIX",
  "PGDATA": "$COORDINATOR_DATA_DIRECTORY",
  "PGHOST": "localhost",
  "PGPORT": "$PGPORT"
}
EOF

# List backups
wal-g backup-list --config=/dev/stdin <<EOF
{
  "WALG_FILE_PREFIX": "$WALG_FILE_PREFIX"
}
EOF
```

### Testing Compression

Test different compression methods:

```bash
# Test with brotli (default)
WALG_COMPRESSION_METHOD=brotli wal-g backup-push --full

# Test with lz4
WALG_COMPRESSION_METHOD=lz4 wal-g backup-push --full

# Test with zstd
WALG_COMPRESSION_METHOD=zstd wal-g backup-push --full

# Compare sizes
du -sh /tmp/walg-manual-test/basebackups_005/*/
```

### Testing Delta Backups

Create incremental backups:

```bash
# Create base backup
wal-g backup-push --full

# Make some changes
psql -d postgres -c "CREATE TABLE test_delta (id serial, data text);"
psql -d postgres -c "INSERT INTO test_delta (data) SELECT 'row ' || generate_series(1,1000);"

# Create delta backup
wal-g backup-push

# List backups (should show base + delta)
wal-g backup-list
```

## Testing WAL Archiving

### Enable WAL Archiving

Configure continuous archiving:

```bash
# Add to postgresql.conf
cat >> $COORDINATOR_DATA_DIRECTORY/postgresql.conf <<EOF
archive_mode = on
archive_command = 'wal-g seg wal-push %p --content-id=-1 --config=/etc/wal-g/wal-g.json'
EOF

# Restart cluster
gpstop -ar

# Verify
psql -c "SHOW archive_mode;"
psql -c "SHOW archive_command;"
```

### Test WAL Push

Generate WAL activity:

```bash
# Force WAL switch
psql -c "SELECT pg_switch_wal();"

# Create activity
psql -c "CREATE TABLE test_wal (id serial, data text);"
psql -c "INSERT INTO test_wal (data) SELECT 'test' FROM generate_series(1,10000);"

# Check WAL archives
wal-g wal-show
```

## Testing Restore

### Prepare for Restore Test

⚠️ **Warning**: Restore testing requires cluster downtime.

```bash
# Stop cluster
gpstop -a

# Backup current data directory
mv $COORDINATOR_DATA_DIRECTORY ${COORDINATOR_DATA_DIRECTORY}.bak

# List available backups
wal-g backup-list

# Restore latest backup
wal-g backup-fetch LATEST --in-place

# Start cluster
gpstart -a

# Verify data
psql -c "SELECT count(*) FROM test_backup;"
```

### Restore to Specific Point

```bash
# List restore points
wal-g restore-point-list

# Restore to specific backup
wal-g backup-fetch backup_20251013T003011Z --in-place
```

## Performance Testing

### Measure Backup Speed

```bash
# Time a full backup
time wal-g backup-push --full

# Check backup size
du -sh ~/bom-test-artifacts/wal-g/backups/
```

### Parallel Backup Testing

WAL-G automatically backs up all segments in parallel. Monitor:

```bash
# Watch segment backup progress
watch -n 1 'ls -lh ~/bom-test-artifacts/wal-g/logs/*.log'

# Check backup times per segment
grep "command success" ~/bom-test-artifacts/wal-g/logs/*.log
```

## Troubleshooting Tests

### Test Failures

If tests fail, check:

```bash
# Review test logs
cat ~/bom-test-artifacts/wal-g/logs/wal-g-gplog.log

# Check segment logs
cat ~/bom-test-artifacts/wal-g/logs/wal-g-log-seg*.log

# Review backup logs
cat ~/bom-test-artifacts/wal-g/backup-push.log
```

### Common Issues

**Cluster Not Running**:
```bash
gpstate -q
# If not running:
gpstart -a
```

**Permission Errors**:
```bash
# Check directory permissions
ls -ld ~/bom-test-artifacts/wal-g/

# Fix if needed
chmod 755 ~/bom-test-artifacts/wal-g/
```

**Bash Not Found**:
```bash
# Ensure bash is in PATH
export PATH="/usr/bin:$PATH"

# Verify
which bash
```

### Cleaning Up After Tests

```bash
# Remove test artifacts
rm -rf ~/bom-test-artifacts/wal-g/

# Drop test database
psql -c "DROP DATABASE IF EXISTS walg_test;" postgres

# Remove manual test backups
rm -rf /tmp/walg-manual-test/
```

## Test Best Practices

1. **Always test on non-production data**
2. **Verify cluster state before testing**
3. **Monitor disk space during backup tests**
4. **Review logs after each test**
5. **Clean up test artifacts regularly**

## Continuous Integration

### Automated Testing

Add to CI pipeline:

```bash
#!/bin/bash
set -e

# Start cluster
./assemble.sh --run --component cloudberry --steps gpstart

# Run WAL-G tests
echo "N" | ./assemble.sh --run --component wal-g --steps test

# Cleanup
rm -rf ~/bom-test-artifacts/wal-g/
```

## Related Documentation

- [Build Guide](BUILD.md)
- [Installation Guide](INSTALL.md)
- [Usage Guide](USAGE.md)
