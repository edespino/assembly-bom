# WAL-G Usage Guide

## Overview

This guide covers using WAL-G for backup and recovery operations with Cloudberry Database.

## Table of Contents

- [Configuration](#configuration)
- [Backup Operations](#backup-operations)
- [Restore Operations](#restore-operations)
- [WAL Archiving](#wal-archiving)
- [Backup Management](#backup-management)
- [Advanced Features](#advanced-features)

## Configuration

### Configuration File

WAL-G requires a configuration file specifying connection and storage settings.

**Local Filesystem** (`/etc/wal-g/wal-g.json`):
```json
{
  "WALG_FILE_PREFIX": "/backup/cloudberry",
  "WALG_GP_LOGS_DIR": "/var/log/wal-g",
  "WALG_GP_SEG_STATES_DIR": "/tmp/walg_seg_states",
  "PGDATA": "/data/coordinator",
  "PGHOST": "localhost",
  "PGPORT": "5432",
  "PGUSER": "gpadmin",
  "PGDATABASE": "postgres",
  "WALG_COMPRESSION_METHOD": "brotli",
  "WALG_DELTA_MAX_STEPS": "5"
}
```

**Amazon S3**:
```json
{
  "WALG_S3_PREFIX": "s3://my-bucket/cloudberry-backups",
  "AWS_REGION": "us-west-2",
  "AWS_ACCESS_KEY_ID": "your-access-key",
  "AWS_SECRET_ACCESS_KEY": "your-secret-key",
  "WALG_COMPRESSION_METHOD": "brotli",
  "PGHOST": "localhost",
  "PGPORT": "5432",
  "PGUSER": "gpadmin"
}
```

**Azure Blob Storage**:
```json
{
  "WALG_AZ_PREFIX": "azure://container/path",
  "AZURE_STORAGE_ACCOUNT": "your-account",
  "AZURE_STORAGE_ACCESS_KEY": "your-key",
  "WALG_COMPRESSION_METHOD": "brotli"
}
```

### Environment Variables

Alternatively, use environment variables:
```bash
export WALG_FILE_PREFIX="/backup/cloudberry"
export PGHOST=localhost
export PGPORT=5432
export PGUSER=gpadmin
```

## Backup Operations

### Full Backup

Create a complete backup of all segments:

```bash
wal-g backup-push --full --config=/etc/wal-g/wal-g.json
```

With custom user data:
```bash
wal-g backup-push --full --add-user-data="daily-backup-$(date +%Y%m%d)" \
  --config=/etc/wal-g/wal-g.json
```

### Delta (Incremental) Backup

Create an incremental backup:

```bash
wal-g backup-push --config=/etc/wal-g/wal-g.json
```

Delta backups are automatically created based on the most recent full backup.

### Permanent Backup

Mark a backup as permanent (won't be deleted by retention policies):

```bash
wal-g backup-push --full --permanent --config=/etc/wal-g/wal-g.json
```

### List Backups

View available backups:

```bash
# Simple list
wal-g backup-list --config=/etc/wal-g/wal-g.json

# Detailed information
wal-g backup-list --detail --config=/etc/wal-g/wal-g.json

# JSON output
wal-g backup-list --detail --json --config=/etc/wal-g/wal-g.json
```

Example output:
```
backup_name                                modified                  wal_file_name            storage_name
backup_20251013T003011Z                    2025-10-13T00:30:12-07:00 ZZZZZZZZZZZZZZZZZZZZZZZZ default
backup_20251013T003012Z_D_20251013T003011Z 2025-10-13T00:30:13-07:00 ZZZZZZZZZZZZZZZZZZZZZZZZ default
```

## Restore Operations

### Basic Restore

⚠️ **Warning**: Restore operations require cluster shutdown and will overwrite existing data.

```bash
# 1. Stop the cluster
gpstop -a

# 2. Backup current data directory (optional but recommended)
mv $COORDINATOR_DATA_DIRECTORY ${COORDINATOR_DATA_DIRECTORY}.bak

# 3. Restore latest backup
wal-g backup-fetch LATEST --in-place --config=/etc/wal-g/wal-g.json

# 4. Start the cluster
gpstart -a
```

### Restore Specific Backup

Restore a specific backup by name:

```bash
wal-g backup-fetch backup_20251013T003011Z --in-place \
  --config=/etc/wal-g/wal-g.json
```

### Restore to Specific Time

Using restore points:

```bash
# List available restore points
wal-g restore-point-list --config=/etc/wal-g/wal-g.json

# Restore to specific restore point
wal-g backup-fetch --restore-point="my_restore_point" --in-place \
  --config=/etc/wal-g/wal-g.json

# Restore to closest backup before timestamp
wal-g backup-fetch --restore-point-ts="2025-10-13T12:00:00Z" --in-place \
  --config=/etc/wal-g/wal-g.json
```

### Partial Restore

Restore only specific segments (useful for segment-level recovery):

```bash
# Restore only segments 0 and 2
wal-g backup-fetch LATEST --content-ids=0,2 --in-place \
  --config=/etc/wal-g/wal-g.json
```

### Restore Specific Databases

Restore only specified databases (experimental):

```bash
wal-g backup-fetch LATEST --restore-only=db1,db2 --in-place \
  --config=/etc/wal-g/wal-g.json
```

## WAL Archiving

### Enable Continuous Archiving

Edit `postgresql.conf` on the coordinator:

```bash
# For coordinator (content-id = -1)
archive_mode = on
archive_command = 'wal-g seg wal-push %p --content-id=-1 --config=/etc/wal-g/wal-g.json'
```

For each segment, WAL-G automatically handles the appropriate content ID.

### Restart Cluster

Apply configuration:

```bash
gpstop -ar
```

### Verify WAL Archiving

```bash
# Check archive mode
psql -c "SHOW archive_mode;"
psql -c "SHOW archive_command;"

# Force WAL switch to test
psql -c "SELECT pg_switch_wal();"

# Verify WAL archives
wal-g wal-show --config=/etc/wal-g/wal-g.json
```

### Manual WAL Push

Manually archive a WAL file:

```bash
wal-g seg wal-push /path/to/wal/file --content-id=-1 \
  --config=/etc/wal-g/wal-g.json
```

## Backup Management

### Delete Old Backups

Keep last N backups:

```bash
# Keep last 7 backups
wal-g delete retain 7 --config=/etc/wal-g/wal-g.json
```

Delete backups older than a specific date:

```bash
# Delete backups older than 30 days
wal-g delete before FIND_FULL 30 --config=/etc/wal-g/wal-g.json

# Delete backups before specific backup
wal-g delete before backup_20251001T000000Z --config=/etc/wal-g/wal-g.json
```

Delete specific backup:

```bash
wal-g delete target backup_20251013T003011Z --config=/etc/wal-g/wal-g.json
```

### Backup Retention Policy

Set up automated retention:

```bash
# In cron or scheduler
0 2 * * * /usr/local/wal-g/bin/wal-g delete retain 7 --config=/etc/wal-g/wal-g.json
```

## Advanced Features

### Restore Points

Create named restore points for point-in-time recovery:

```bash
# Create restore point
psql -c "SELECT pg_create_restore_point('before_major_update');" postgres

# List restore points
wal-g restore-point-list --config=/etc/wal-g/wal-g.json

# Restore to named point
wal-g backup-fetch --restore-point="before_major_update" --in-place \
  --config=/etc/wal-g/wal-g.json
```

### Compression Methods

WAL-G supports multiple compression algorithms:

```json
{
  "WALG_COMPRESSION_METHOD": "brotli"  // Options: brotli, lz4, lzma, zstd
}
```

Comparison:
- **brotli**: Best compression ratio, slower
- **lz4**: Fastest, lower compression
- **zstd**: Good balance of speed and compression
- **lzma**: Highest compression, slowest

### Encryption

Using libsodium encryption:

```json
{
  "WALG_LIBSODIUM_KEY": "your-encryption-key-here"
}
```

Or use a key file:

```json
{
  "WALG_LIBSODIUM_KEY_PATH": "/etc/wal-g/encryption.key"
}
```

### Copy Backups

Copy backups between storage locations:

```bash
wal-g copy --from="s3://source-bucket" --to="s3://dest-bucket" \
  backup_20251013T003011Z
```

### Backup Verification

Check AO/AOCS table integrity:

```bash
# On coordinator
wal-g check-ao-aocs-length --config=/etc/wal-g/wal-g.json
```

## Automation Examples

### Daily Full Backup

```bash
#!/bin/bash
# /usr/local/bin/wal-g-daily-backup.sh

set -e

CONFIG="/etc/wal-g/wal-g.json"
LOG="/var/log/wal-g/daily-backup.log"

echo "$(date): Starting daily backup" >> "$LOG"

/usr/local/wal-g/bin/wal-g backup-push --full \
  --add-user-data="daily-$(date +%Y%m%d)" \
  --config="$CONFIG" >> "$LOG" 2>&1

echo "$(date): Backup completed" >> "$LOG"

# Clean up old backups
/usr/local/wal-g/bin/wal-g delete retain 7 --config="$CONFIG" >> "$LOG" 2>&1
```

Cron entry:
```
0 2 * * * /usr/local/bin/wal-g-daily-backup.sh
```

### Hourly Delta Backup

```bash
#!/bin/bash
# /usr/local/bin/wal-g-hourly-delta.sh

set -e

CONFIG="/etc/wal-g/wal-g.json"
LOG="/var/log/wal-g/hourly-delta.log"

echo "$(date): Starting delta backup" >> "$LOG"

/usr/local/wal-g/bin/wal-g backup-push \
  --add-user-data="hourly-$(date +%Y%m%d-%H)" \
  --config="$CONFIG" >> "$LOG" 2>&1

echo "$(date): Delta backup completed" >> "$LOG"
```

Cron entry:
```
0 * * * * /usr/local/bin/wal-g-hourly-delta.sh
```

## Monitoring and Troubleshooting

### Check Backup Status

```bash
# List recent backups
wal-g backup-list --config=/etc/wal-g/wal-g.json | tail -5

# Check backup size
du -sh /backup/cloudberry/basebackups_005/*/
```

### Monitor Logs

```bash
# View WAL-G logs
tail -f /var/log/wal-g/wal-g-gplog.log

# Check segment logs
tail -f /var/log/wal-g/wal-g-log-seg*.log
```

### Common Issues

**Backup Hanging**:
- Check segment logs for errors
- Verify all segments are accessible
- Ensure sufficient disk space

**Permission Errors**:
```bash
# Fix log directory permissions
sudo chown -R gpadmin:gpadmin /var/log/wal-g

# Fix backup directory permissions
sudo chown -R gpadmin:gpadmin /backup/cloudberry
```

**Archive Command Failures**:
```bash
# Check WAL archiving status
psql -c "SELECT * FROM pg_stat_archiver;"

# Test archive command manually
su - gpadmin -c "wal-g seg wal-push /path/to/wal --content-id=-1 --config=/etc/wal-g/wal-g.json"
```

## Best Practices

1. **Regular Testing**: Test restore procedures regularly
2. **Monitor Backup Size**: Track backup growth over time
3. **Retention Policy**: Implement appropriate retention based on requirements
4. **Off-site Backups**: Store backups in multiple locations
5. **Encryption**: Use encryption for sensitive data
6. **Documentation**: Document your backup/restore procedures
7. **Alerts**: Set up monitoring and alerts for backup failures

## Performance Tuning

### Parallel Upload

Increase concurrent uploads:

```json
{
  "WALG_UPLOAD_CONCURRENCY": "16",
  "WALG_UPLOAD_DISK_CONCURRENCY": "4"
}
```

### Compression Level

For brotli:
```json
{
  "WALG_COMPRESSION_METHOD": "brotli",
  "BROTLI_QUALITY": "6"  // 0-11, default is 11
}
```

### Network Rate Limiting

Limit backup upload speed:

```json
{
  "WALG_NETWORK_RATE_LIMIT": "104857600"  // 100 MB/s in bytes
}
```

## Related Documentation

- [Build Guide](BUILD.md)
- [Installation Guide](INSTALL.md)
- [Testing Guide](TEST.md)
- [Official WAL-G Greenplum Docs](https://github.com/wal-g/wal-g/blob/master/docs/Greenplum.md)
