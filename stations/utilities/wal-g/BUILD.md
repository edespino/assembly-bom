# WAL-G Build Guide

## Overview

WAL-G is a backup and recovery tool for Greenplum/Cloudberry databases. This guide covers building WAL-G from source with support for compression and encryption.

## Prerequisites

### System Requirements
- Go 1.15 or later
- Git
- Make
- GCC/G++ compiler

### Optional Dependencies
- **Brotli** (`brotli-devel`) - For brotli compression support
- **libsodium** (`libsodium-devel`) - For encryption support
- **LZO** (`lzo-devel`) - For LZO compression support

## Building WAL-G

### Using assemble.sh

The simplest way to build WAL-G:

```bash
./assemble.sh --run --component wal-g --steps build
```

This will:
1. Clone the wal-g repository (v3.0.7 for Greenplum/Cloudberry)
2. Install Go dependencies
3. Build the Greenplum-specific binary with brotli and libsodium support
4. Generate version information

### Build Configuration

The build is configured in `bom.yaml`:

```yaml
- name: wal-g
  url: https://github.com/wal-g/wal-g.git
  branch: v3.0.7
  build_flags: |
    USE_BROTLI=1
    USE_LIBSODIUM=1
```

### Build Flags

Available build flags:
- `USE_BROTLI=1` - Enable Brotli compression
- `USE_LIBSODIUM=1` - Enable libsodium encryption
- `USE_LZO=1` - Enable LZO compression

### Manual Build

If you need to build manually:

```bash
cd ~/bom-parts/wal-g
make deps
cd main/gp
go build -mod vendor -tags "brotli libsodium" -o wal-g
```

## Build Output

### Location
The compiled binary is located at:
```
~/bom-parts/wal-g/main/gp/wal-g
```

### Verification

Check the build:
```bash
~/bom-parts/wal-g/main/gp/wal-g --version
```

Expected output:
```
wal-g version v3.0.7	<git-hash>	<build-date>	GreenplumDB
```

## Build Architecture

### Version Information

The build process embeds:
- **Version**: From git tag or branch name
- **Git Revision**: Short commit hash
- **Build Date**: UTC timestamp
- **Target**: GreenplumDB (compatible with Cloudberry)

### Binary Features

The Greenplum build includes:
- Multi-segment backup coordination
- Parallel backup/restore
- Delta (incremental) backups
- Compression (brotli, lz4, zstd)
- Encryption (libsodium)
- Restore point management

## Troubleshooting

### Go Version Issues

If you see "Go compiler not found":
```bash
# Check Go installation
which go
go version

# Add Go to PATH if needed
export PATH=/opt/go/bin:$PATH
```

### Missing Dependencies

If brotli or libsodium are missing:
```bash
# Install system packages
sudo dnf install brotli-devel

# Or build libsodium locally
./assemble.sh --run --component libsodium
```

### Build Failures

Check the build log:
```bash
ls -lt ~/bom-parts/wal-g/make-wal-g-*.log | head -1
```

## Related Documentation

- [Installation Guide](INSTALL.md)
- [Testing Guide](TEST.md)
- [Usage Guide](USAGE.md)
