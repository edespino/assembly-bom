#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/cloudberry/gpinitsystem.sh
# Purpose  : Initialize a Cloudberry cluster using gpinitsystem
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

NAME="${NAME:?Component NAME is required}"

section "gpinitsystem - Initialize Cloudberry cluster"
start_time=$(date +%s)

# Load Cloudberry environment with fallback
[ -f "${SCRIPT_DIR}/../../../config/cloudberry-env-loader.sh" ] && source "${SCRIPT_DIR}/../../../config/cloudberry-env-loader.sh"
if ! source_cloudberry_env /usr/local/cloudberry; then
  echo "[gpinitsystem] ERROR: Failed to load Cloudberry environment"
  exit 1
fi

# --------------------------------------------------------------------
# Step 1: Add COORDINATOR_DATA_DIRECTORY to .bashrc
# --------------------------------------------------------------------

log "Step 1: Adding COORDINATOR_DATA_DIRECTORY to ~/.bashrc"
if ! grep -qF 'export COORDINATOR_DATA_DIRECTORY=/data1/coordinator/gpseg-1' ~/.bashrc; then
  echo 'export COORDINATOR_DATA_DIRECTORY=/data1/coordinator/gpseg-1' >> ~/.bashrc
  log "✅ COORDINATOR_DATA_DIRECTORY added to ~/.bashrc"
else
  log "ℹ️  COORDINATOR_DATA_DIRECTORY already exists in ~/.bashrc (skipped)"
fi

# --------------------------------------------------------------------
# Step 2: Create gpinitsystem configuration
# --------------------------------------------------------------------

log "Step 2: Creating gpinitsystem configuration"
cat >| /home/cbadmin/gpinitsystem.conf <<'EOF'
ARRAY_NAME="Apache Cloudberry (Incubating) Cluster"
SEG_PREFIX=gpseg
CHECK_POINT_SEGMENTS=8
COORDINATOR_MAX_CONNECT=250
COORDINATOR_PORT=5432
COORDINATOR_HOSTNAME=$(hostname)
COORDINATOR_DIRECTORY=/data1/coordinator
PORT_BASE=6000
declare -a DATA_DIRECTORY=(/data1/primary /data2/primary /data3/primary /data4/primary)
MIRROR_PORT_BASE=7000
declare -a MIRROR_DATA_DIRECTORY=(/data1/mirror /data2/mirror /data3/mirror /data4/mirror)
TRUSTED_SHELL=ssh
ENCODING=UNICODE
DATABASE_NAME=cbadmin
MACHINE_LIST_FILE=/home/cbadmin/hostfile_gpinitsystem
EOF

log "✅ gpinitsystem.conf created at /home/cbadmin/gpinitsystem.conf"

# --------------------------------------------------------------------
# Step 3: Clean and create data directories
# --------------------------------------------------------------------

log "Step 3: Cleaning and creating data directories"
sudo rm -rf /data1/{coordinator,primary,mirror,standby_coordinator} \
            /data2/{coordinator,primary,mirror,standby_coordinator} \
            /data3/{coordinator,primary,mirror,standby_coordinator} \
            /data4/{coordinator,primary,mirror,standby_coordinator}

sudo mkdir -p /data1/{coordinator,primary,mirror,standby_coordinator} \
              /data2/{coordinator,primary,mirror,standby_coordinator} \
              /data3/{coordinator,primary,mirror,standby_coordinator} \
              /data4/{coordinator,primary,mirror,standby_coordinator}

sudo chmod -R a+w /data*
log "✅ Data directories created and permissions set"

# --------------------------------------------------------------------
# Step 4: Create host files
# --------------------------------------------------------------------

log "Step 4: Creating host files"
echo "cdw" >| /home/cbadmin/all_hosts.txt
echo "cdw" >| /home/cbadmin/hostfile_gpinitsystem
log "✅ Host files created (all_hosts.txt and hostfile_gpinitsystem)"

# --------------------------------------------------------------------
# Step 5: Setup SSH known_hosts
# --------------------------------------------------------------------

log "Step 5: Setting up SSH known_hosts"
ssh-keyscan cdw >> ~/.ssh/known_hosts 2>/dev/null
ssh-keyscan -H $(getent hosts | awk '/ cdw$/ && $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ { print $1 }') 2>/dev/null >> ~/.ssh/known_hosts
log "  → Testing SSH connection to cdw..."
ssh cdw hostname
log "✅ SSH setup complete and verified"

# --------------------------------------------------------------------
# Step 6: Run gpinitsystem
# --------------------------------------------------------------------

log "Step 6: Running gpinitsystem to initialize cluster"
log "  → Command: gpinitsystem -s $(hostname) -S /data1/standby_coordinator/gpseg-1 -P 6432 -c /home/cbadmin/gpinitsystem.conf -a"
gpinitsystem -s $(hostname) \
             -S /data1/standby_coordinator/gpseg-1 \
             -P 6432 \
             -c /home/cbadmin/gpinitsystem.conf \
             -a

log "✅ gpinitsystem completed successfully"

# --------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------

log ""
log "Cloudberry cluster initialization complete!"
log ""
log "Configuration summary:"
log "  Coordinator hostname: $(hostname)"
log "  Coordinator port: 5432"
log "  Standby coordinator: /data1/standby_coordinator/gpseg-1"
log "  Standby port: 6432"
log "  Database name: cbadmin"
log "  Segment prefix: gpseg"
log ""
log "Next steps:"
log "  - Run: source ~/.bashrc (to load COORDINATOR_DATA_DIRECTORY)"
log "  - Run: gpstate -a (to check cluster status)"
log ""

section_complete "gpinitsystem - Initialize Cloudberry cluster" "$start_time"
