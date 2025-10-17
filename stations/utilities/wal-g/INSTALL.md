# WAL-G Installation Guide

## Overview

This guide covers installing WAL-G after building it for use with Apache Cloudberry.

## Installation Methods

### Using assemble.sh (Recommended)

Install WAL-G to the default location:

```bash
./assemble.sh --run --component wal-g --steps install
```

This installs to `/usr/local/bin/wal-g`

### Custom Installation

To install to a custom location, set the `INSTALL_PREFIX` environment variable:

```bash
INSTALL_PREFIX=/opt/wal-g ./assemble.sh --run --component wal-g --steps install
```

## Installation Locations

### Default Paths

- **Binary**: `/usr/local/bin/wal-g`
- **Source**: `~/bom-parts/wal-g/`
- **Build logs**: `~/bom-parts/wal-g/make-wal-g-*.log`

### PATH Configuration

Add WAL-G to your PATH:

```bash
# For current session
export PATH="/usr/local/bin:$PATH"

# Permanent (add to ~/.bashrc or ~/.bash_profile)
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

## Post-Installation Verification

### Check Installation

```bash
# Verify binary exists
ls -lh /usr/local/bin/wal-g

# Check version
/usr/local/bin/wal-g --version
```

Expected output:
```
wal-g version v3.0.7	6ea13b90	2025.10.13_01:57:12	GreenplumDB
```

### Test Basic Functionality

```bash
# Show help
wal-g --help

# List available commands
wal-g backup-push --help
wal-g backup-list --help
wal-g backup-fetch --help
```

## Configuration Setup

### Create Configuration Directory

```bash
# Create config directory
sudo mkdir -p /etc/wal-g
sudo chown $USER:$USER /etc/wal-g
```

### Basic Configuration File

Create `/etc/wal-g/wal-g.json`:

```json
{
  "WALG_FILE_PREFIX": "/backup/cloudberry",
  "WALG_GP_LOGS_DIR": "/var/log/wal-g",
  "PGHOST": "localhost",
  "PGPORT": "5432",
  "PGUSER": "gpadmin",
  "PGDATABASE": "postgres",
  "WALG_COMPRESSION_METHOD": "brotli"
}
```

For S3 storage:

```json
{
  "WALG_S3_PREFIX": "s3://my-bucket/cloudberry-backups",
  "AWS_REGION": "us-west-2",
  "AWS_ACCESS_KEY_ID": "your-key",
  "AWS_SECRET_ACCESS_KEY": "your-secret",
  "WALG_COMPRESSION_METHOD": "brotli"
}
```

## Cluster Integration

### For Single-Node Demo Cluster

If you're using the gpdemo single-node cluster:

```bash
# Source the cluster environment
source ~/bom-parts/cloudberry/gpAux/gpdemo/gpdemo-env.sh

# Verify cluster is running
gpstate -q

# Run test suite
./assemble.sh --run --component wal-g --steps test
```

### For Production Cluster

1. **Install on all hosts** where Cloudberry segments run
2. **Ensure consistent PATH** across all hosts
3. **Configure shared storage** (NFS, S3, etc.)
4. **Set up log directories** on all hosts

```bash
# On each host
sudo mkdir -p /var/log/wal-g
sudo chown gpadmin:gpadmin /var/log/wal-g

sudo mkdir -p /backup/cloudberry
sudo chown gpadmin:gpadmin /backup/cloudberry
```

## Permissions

### Required Access

WAL-G needs:
- **Read access** to PostgreSQL data directories
- **Write access** to backup storage location
- **Write access** to log directories
- **Execute permissions** on bash and wal-g binary

### User Setup

WAL-G should run as the same user as Cloudberry (typically `gpadmin`):

```bash
# Verify ownership
ls -ld /usr/local/bin/wal-g

# If needed, adjust permissions
sudo chown root:root /usr/local/bin/wal-g
sudo chmod 755 /usr/local/bin/wal-g
```

## Uninstallation

To remove WAL-G:

```bash
# Remove binary
sudo rm -f /usr/local/bin/wal-g /usr/bin/wal-g

# Remove configuration (optional)
sudo rm -rf /etc/wal-g

# Remove source (optional)
rm -rf ~/bom-parts/wal-g
```

## Troubleshooting

### Binary Not Found

If `wal-g` command is not found:

```bash
# Check if binary exists
ls -l /usr/local/bin/wal-g

# Add to PATH temporarily
export PATH="/usr/local/bin:$PATH"

# Verify
which wal-g
```

### Permission Denied

If you see "permission denied":

```bash
# Check permissions
ls -l /usr/local/bin/wal-g

# Fix if needed
sudo chmod +x /usr/local/bin/wal-g
```

### Bash Not Found Error

If you see "bash: executable file not found":

This occurs when WAL-G runs on segments. Ensure `/usr/bin` is in PATH:

```bash
export PATH="/usr/bin:/usr/local/bin:$PATH"
```

## Next Steps

After installation:

1. [Run the test suite](TEST.md) to verify functionality
2. [Configure backups](USAGE.md) for your cluster
3. Set up WAL archiving for continuous backup

## Related Documentation

- [Build Guide](BUILD.md)
- [Testing Guide](TEST.md)
- [Usage Guide](USAGE.md)
