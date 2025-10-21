# WAL-G for Apache Cloudberry

## Overview

WAL-G is a backup and recovery tool for Cloudberry/Greenplum databases, providing fast, compressed, and encrypted backups with support for incremental (delta) backups and point-in-time recovery (PITR).

## Features

- **Multi-segment Backup**: Parallel backup of all Cloudberry segments
- **Incremental Backups**: Delta backups reduce storage and backup time
- **Compression**: Multiple algorithms (brotli, lz4, zstd, lzma)
- **Encryption**: Secure backups with libsodium
- **Flexible Storage**: Local filesystem, S3, Azure, GCS
- **Point-in-Time Recovery**: Restore to specific timestamps
- **WAL Archiving**: Continuous archiving for minimal data loss

## Quick Start

### Build and Install

```bash
# Build WAL-G
./assemble.sh --run --component wal-g --steps build

# Install WAL-G
./assemble.sh --run --component wal-g --steps install

# Verify installation
/usr/local/bin/wal-g --version
```

### Run Tests

```bash
# Ensure cluster is running
source ~/bom-parts/cloudberry/gpAux/gpdemo/gpdemo-env.sh
gpstate -q

# Run test suite
./assemble.sh --run --component wal-g --steps test
```

### Create Your First Backup

```bash
# Create configuration
cat > /tmp/wal-g-config.json <<EOF
{
  "WALG_FILE_PREFIX": "/backup/cloudberry",
  "PGHOST": "localhost",
  "PGPORT": "7000",
  "PGUSER": "$(whoami)"
}
EOF

# Create backup directory
mkdir -p /backup/cloudberry

# Create full backup
wal-g backup-push --full --config=/tmp/wal-g-config.json

# List backups
wal-g backup-list --config=/tmp/wal-g-config.json
```

## Documentation

### Core Documentation

- **[BUILD.md](BUILD.md)** - Building WAL-G from source
- **[INSTALL.md](INSTALL.md)** - Installation and setup
- **[TEST.md](TEST.md)** - Testing procedures
- **[USAGE.md](USAGE.md)** - Comprehensive usage guide

### Topics Covered

**Building**:
- Prerequisites and dependencies
- Build configuration and flags
- Version information
- Troubleshooting build issues

**Installation**:
- Installation methods
- PATH configuration
- Cluster integration
- Permissions and security

**Testing**:
- Automated test suite (12 tests)
- Manual testing procedures
- Performance testing
- Troubleshooting

**Usage**:
- Configuration (filesystem, S3, Azure)
- Backup operations (full, delta, permanent)
- Restore operations (basic, PITR, partial)
- WAL archiving setup
- Backup management and retention
- Advanced features (encryption, compression)
- Automation examples
- Monitoring and troubleshooting

## Component Structure

```
stations/utilities/wal-g/
├── README.md          # This file
├── BUILD.md           # Build documentation
├── INSTALL.md         # Installation documentation
├── TEST.md            # Testing documentation
├── USAGE.md           # Usage documentation
├── build.sh           # Build script
├── install.sh         # Installation script
└── test.sh            # Test script
```

## Configuration

WAL-G is configured in `bom.yaml`:

```yaml
- name: wal-g
  url: https://github.com/wal-g/wal-g.git
  branch: v3.0.7
  build_flags: |
    USE_BROTLI=1
    USE_LIBSODIUM=1
  env:
    INSTALL_PREFIX: /usr/local
  steps:
    - clone
    - build
    - install
    - test
    - extended-test
```

### Installation Path Override

By default, components install to `/usr/local/$NAME` (e.g., `/usr/local/wal-g`). WAL-G overrides this to `/usr/local` via the `env.INSTALL_PREFIX` setting, resulting in the binary being installed at `/usr/local/bin/wal-g`. This simplifies PATH configuration and follows standard Unix conventions for system utilities.

A symlink is also created at `/usr/bin/wal-g` for recovery configuration compatibility.

## Test Suite

The test suite validates:
- ✓ Version check
- ✓ Database operations
- ✓ Full backup creation
- ✓ Delta backup creation
- ✓ Backup listing and metadata
- ✓ Data integrity
- ✓ Restore preparation

Test artifacts are stored in: `~/bom-test-artifacts/wal-g/`

## Common Commands

```bash
# Create full backup
wal-g backup-push --full --config=/etc/wal-g/wal-g.json

# Create delta backup
wal-g backup-push --config=/etc/wal-g/wal-g.json

# List backups
wal-g backup-list --config=/etc/wal-g/wal-g.json

# Restore latest backup
wal-g backup-fetch LATEST --in-place --config=/etc/wal-g/wal-g.json

# Delete old backups (keep last 7)
wal-g delete retain 7 --config=/etc/wal-g/wal-g.json

# List restore points
wal-g restore-point-list --config=/etc/wal-g/wal-g.json
```

## Requirements

### Build Requirements
- Go 1.15+
- Git
- Make
- GCC/G++
- brotli-devel (optional)
- libsodium (optional, can be built locally)

### Runtime Requirements
- Cloudberry/Greenplum Database
- Bash
- Sufficient disk space for backups
- Network access to backup storage (if using cloud)

## Storage Backends

WAL-G supports multiple storage backends:

- **Local Filesystem**: `WALG_FILE_PREFIX="/path/to/backups"`
- **Amazon S3**: `WALG_S3_PREFIX="s3://bucket/path"`
- **Azure Blob**: `WALG_AZ_PREFIX="azure://container/path"`
- **Google Cloud**: `WALG_GS_PREFIX="gs://bucket/path"`
- **SSH**: `WALG_SSH_PREFIX="ssh://user@host/path"`

## Architecture

### Greenplum Build

The Greenplum-specific build (`main/gp/`) includes:
- Multi-segment coordination
- Parallel backup/restore
- Segment-specific operations
- Apache Cloudberry compatibility

### Backup Process

1. Coordinator initiates backup
2. Segments backup in parallel
3. Coordinator collects metadata
4. Backup sentinel created
5. Restore point registered

## Performance

### Typical Performance

With a 3-segment cluster:
- **Full backup**: ~1 second (demo cluster with minimal data)
- **Delta backup**: ~1 second
- **Backup size**: ~20-25MB (compressed with brotli)
- **Test suite**: ~3-5 seconds

### Optimization

- Use brotli for best compression
- Use lz4 for fastest speed
- Adjust `WALG_UPLOAD_CONCURRENCY` for parallel uploads
- Enable delta backups to reduce backup time

## Troubleshooting

### Common Issues

**Bash not found**:
```bash
export PATH="/usr/bin:/usr/local/bin:$PATH"
```

**Permission denied**:
```bash
sudo chmod +x /usr/local/bin/wal-g
```

**Cluster not running**:
```bash
source ~/bom-parts/cloudberry/gpAux/gpdemo/gpdemo-env.sh
gpstart -a
```

### Getting Help

1. Check logs: `~/bom-test-artifacts/wal-g/logs/`
2. Review [TEST.md](TEST.md#troubleshooting-tests)
3. See [USAGE.md](USAGE.md#monitoring-and-troubleshooting)
4. Check official docs: https://github.com/wal-g/wal-g

## Examples

### Daily Backup Automation

```bash
# Create backup script
cat > /usr/local/bin/daily-backup.sh <<'EOF'
#!/bin/bash
set -e
/usr/local/bin/wal-g backup-push --full \
  --config=/etc/wal-g/wal-g.json
/usr/local/bin/wal-g delete retain 7 \
  --config=/etc/wal-g/wal-g.json
EOF

chmod +x /usr/local/bin/daily-backup.sh

# Add to cron
echo "0 2 * * * /usr/local/bin/daily-backup.sh" | crontab -
```

### Point-in-Time Recovery

```bash
# Create restore point before major changes
psql -c "SELECT pg_create_restore_point('before_upgrade');" postgres

# ... perform changes ...

# If needed, restore to that point
gpstop -a
wal-g backup-fetch --restore-point="before_upgrade" --in-place \
  --config=/etc/wal-g/wal-g.json
gpstart -a
```

## Best Practices

1. **Test Regularly**: Test restore procedures monthly
2. **Monitor Backups**: Set up alerts for backup failures
3. **Off-site Storage**: Use S3 or similar for disaster recovery
4. **Retention Policy**: Define and enforce backup retention
5. **Documentation**: Document your backup/restore procedures
6. **Encryption**: Enable encryption for sensitive data
7. **Validation**: Verify backup integrity regularly

## Version Information

- **WAL-G Version**: v3.0.7
- **Target**: GreenplumDB (Cloudberry compatible)
- **Build Features**: Brotli compression, libsodium encryption
- **Repository**: https://github.com/wal-g/wal-g

## Contributing

When modifying WAL-G integration:

1. Update relevant documentation (BUILD.md, INSTALL.md, etc.)
2. Run the test suite
3. Update bom.yaml if changing configuration
4. Document any new features or changes

## License

WAL-G is licensed under the Apache License 2.0. See the [WAL-G repository](https://github.com/wal-g/wal-g) for details.

## Additional Resources

- [Official WAL-G Documentation](https://github.com/wal-g/wal-g)
- [Greenplum Documentation](https://github.com/wal-g/wal-g/blob/master/docs/Greenplum.md)
- [Apache Cloudberry](https://github.com/apache/cloudberry)
