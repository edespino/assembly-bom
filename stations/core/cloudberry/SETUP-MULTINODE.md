# Cloudberry Multinode Cluster Setup

## Overview

The `setup-multinode` step automates the configuration of a distributed Cloudberry Database cluster across multiple hosts. This step prepares the coordinator (cdw) and segment hosts (sdw1, sdw2, etc.) for cluster initialization with `gpinitsystem`.

## What This Step Does

The setup-multinode script performs the following operations in sequence:

### 1. Open /usr/local Permissions
- **Scope**: All hosts (coordinator + segments)
- **Action**: `sudo chmod a+w /usr/local`
- **Purpose**: Allows rsync to copy Cloudberry installation without sudo

### 2. Copy Cloudberry Installation
- **Scope**: Segment hosts only
- **Source**: `/usr/local/cloudberry` from coordinator
- **Destination**: `/usr/local/cloudberry` on each segment
- **Method**: rsync with SSH auto-accept (`StrictHostKeyChecking=no`)

### 3. Install Dependencies
- **Scope**: Segment hosts only
- **Package**: `python3-pygresql` (required for gpinitsystem)
- **Method**: `apt-get install -y python3-pygresql`

### 4. Initialize Data Directories
- **Scope**: All hosts (coordinator + segments)
- **Directories Removed**: `/data1`, `/data2`, `/data3`, `/data4`
- **Directories Created**:
  ```
  /data1/{coordinator,primary,mirror,standby_coordinator}
  /data2/{coordinator,primary,mirror,standby_coordinator}
  /data3/{coordinator,primary,mirror,standby_coordinator}
  /data4/{coordinator,primary,mirror,standby_coordinator}
  ```
- **Ownership**: `cbadmin:cbadmin`
- **Permissions**: `755` (recursive)

### 5. Create gpinitsystem Configuration
- **Scope**: Coordinator only
- **Files Created**:
  - `/home/cbadmin/gpinitsystem.conf` - Cluster configuration
  - `~/.bashrc` - Adds `COORDINATOR_DATA_DIRECTORY` export

**Configuration Details**:
```bash
ARRAY_NAME="Apache Cloudberry (Incubating) Cluster"
COORDINATOR_HOSTNAME=cdw
COORDINATOR_PORT=5432
PORT_BASE=6000 (segments)
MIRROR_PORT_BASE=7000
DATA_DIRECTORY=(4 primary segments per host)
MIRROR_DATA_DIRECTORY=(4 mirror segments per host)
```

### 6. Generate Host Files
- **Scope**: Coordinator only
- **Files Created**:
  - `/home/cbadmin/all_hosts.txt` - All hosts (cdw + segments)
  - `/home/cbadmin/hostfile_gpinitsystem` - Segment hosts only

## Configuration

### Customizing Segment Hosts

Edit line 33 in `setup-multinode.sh`:

```bash
# Segment hosts - easily configurable
SEGMENT_HOSTS=("sdw1" "sdw2" "sdw3")  # Add/remove as needed
```

The script automatically adapts to any number of segment hosts.

### Data Directory Layout

Edit lines 45-46 to customize data directories:

```bash
DATA_DIRS=("/data1" "/data2" "/data3" "/data4")
DATA_SUBDIRS=("coordinator" "primary" "mirror" "standby_coordinator")
```

## Prerequisites

1. **SSH Access**:
   - User `cbadmin` exists on all hosts
   - Passwordless SSH configured from coordinator to all segments
   - SSH keys already exchanged

2. **Sudo Access**:
   - User `cbadmin` has passwordless sudo on all hosts

3. **Cloudberry Installation**:
   - Cloudberry already installed at `/usr/local/cloudberry` on coordinator
   - Installation step must complete before this step runs

4. **Network Configuration**:
   - All hosts can resolve each other's hostnames
   - Hostnames: cdw (coordinator), sdw1, sdw2, etc. (segments)

## Usage

### Via Assembly BOM

```bash
./assemble.sh --run --component cloudberry --steps setup-multinode
```

### Manual Execution

```bash
cd /home/cbadmin/assembly-bom
export NAME=cloudberry
stations/core/cloudberry/setup-multinode.sh
```

## Files Created

| File | Location | Purpose |
|------|----------|---------|
| `gpinitsystem.conf` | `/home/cbadmin/` | Cluster initialization configuration |
| `all_hosts.txt` | `/home/cbadmin/` | List of all hosts (cdw + segments) |
| `hostfile_gpinitsystem` | `/home/cbadmin/` | List of segment hosts for gpinitsystem |
| Data directories | `/data1-4/` on all hosts | Storage for coordinator, primary, mirror segments |

## SSH Configuration

The script uses the following SSH options to avoid host key verification prompts:

```bash
-o StrictHostKeyChecking=no
-o UserKnownHostsFile=/dev/null
-o LogLevel=ERROR
```

**Security Note**: These settings are appropriate for temporary, isolated test environments. For production systems, configure proper SSH host key verification.

## Next Steps

After `setup-multinode` completes, initialize the cluster:

```bash
source /usr/local/cloudberry/greenplum_path.sh
gpinitsystem -c /home/cbadmin/gpinitsystem.conf -h /home/cbadmin/hostfile_gpinitsystem
```

Or use the Assembly BOM `create-demo-cluster` step if configured for multinode.

## Troubleshooting

### Permission Denied on rsync
**Symptom**: `mkdir "/usr/local/cloudberry" failed: Permission denied (13)`

**Cause**: Step 1 (open /usr/local permissions) failed or was skipped

**Solution**: Verify sudo access works on all segment hosts

### SSH Connection Refused
**Symptom**: `ssh: connect to host sdw1 port 22: Connection refused`

**Cause**: SSH not configured or hostname not resolvable

**Solution**:
- Verify SSH daemon running: `sudo systemctl status ssh`
- Test SSH manually: `ssh cbadmin@sdw1 hostname`

### Data Directory Ownership Issues
**Symptom**: `Permission denied` when creating segments

**Cause**: Ownership not set correctly in Step 4

**Solution**: Run manually on affected host:
```bash
sudo chown -R cbadmin:cbadmin /data*/
sudo chmod -R 755 /data*/
```

## Design Notes

### Clean Start Philosophy
The script performs `sudo rm -rf /data*` before creating directories to ensure:
- No stale data from previous cluster attempts
- Consistent ownership and permissions
- Removal of any corrupted or partial installations

### Why Four Data Directories?
The default configuration uses 4 primary + 4 mirror segments per host:
- Maximizes parallelism on multi-core systems
- Balances I/O across multiple data directories
- Provides redundancy with mirrored segments

### Coordinator Detection
The script uses `hostname -s` to detect the coordinator host. This allows the script to:
- Execute local commands on the coordinator without SSH
- Execute remote commands via SSH on segments
- Work correctly regardless of hostname changes

## Related Files

- `stations/core/cloudberry/create-demo-cluster.sh` - Next step after setup-multinode
- `bom.yaml` - Contains setup-multinode in Cloudberry steps list
- `config/env.sh` - Environment variables for Cloudberry paths

---

**Last Updated**: 2025-10-18
**Script Location**: `stations/core/cloudberry/setup-multinode.sh`
