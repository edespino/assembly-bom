#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/cloudberry/setup-multinode.sh
# Purpose  : Configure multinode Cloudberry cluster environment
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

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------

# Segment hosts - easily configurable
SEGMENT_HOSTS=("sdw1" "sdw2" "sdw3" "sdw4")

# Coordinator host (current system)
COORDINATOR_HOST="$(hostname -s)"

# SSH options for auto-accepting host keys
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR)

# Cloudberry installation directory
CLOUDBERRY_DIR="/usr/local/cloudberry"

# Data directories to create on all hosts
DATA_DIRS=("/data1" "/data2" "/data3" "/data4")
DATA_SUBDIRS=("coordinator" "primary" "mirror" "standby_coordinator")

section "setup multinode cluster"
start_time=$(date +%s)

# Create list of all hosts (coordinator + segments)
ALL_HOSTS=("$COORDINATOR_HOST" "${SEGMENT_HOSTS[@]}")

# --------------------------------------------------------------------
# Open permissions on /usr/local across all hosts
# --------------------------------------------------------------------

log "Step: Opening permissions on /usr/local across all hosts"

for host in "${ALL_HOSTS[@]}"; do
  log "  → Setting permissions on /usr/local at $host..."

  if [[ "$host" == "$COORDINATOR_HOST" ]]; then
    # Execute locally on coordinator
    sudo chmod a+w /usr/local
  else
    # Execute remotely on segment
    # shellcheck disable=SC2029
    ssh "${SSH_OPTS[@]}" "cbadmin@${host}" "sudo chmod a+w /usr/local"
  fi

  log "  ✓ Completed on $host"
done

log "✅ /usr/local permissions updated on all hosts"

# --------------------------------------------------------------------
# Copy Cloudberry installation to remote hosts
# --------------------------------------------------------------------

log "Step: Copying Cloudberry installation to remote segment hosts"

if [[ ! -d "$CLOUDBERRY_DIR" ]]; then
  echo "[$SCRIPT_NAME] ❌ ERROR: Cloudberry directory not found: $CLOUDBERRY_DIR"
  exit 1
fi

for host in "${SEGMENT_HOSTS[@]}"; do
  log "  → Copying $CLOUDBERRY_DIR to $host..."

  # Use rsync for efficient copying, with SSH options for auto-acceptance
  rsync -az --delete \
    -e "ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR" \
    "$CLOUDBERRY_DIR/" \
    "cbadmin@${host}:${CLOUDBERRY_DIR}/"

  log "  ✓ Completed copy to $host"
done

log "✅ Cloudberry installation copied to all segment hosts"

# --------------------------------------------------------------------
# Install python3-pygresql on remote hosts
# --------------------------------------------------------------------

log "Step: Installing python3-pygresql on remote segment hosts"

for host in "${SEGMENT_HOSTS[@]}"; do
  log "  → Installing python3-pygresql on $host..."

  # shellcheck disable=SC2029
  ssh "${SSH_OPTS[@]}" "cbadmin@${host}" \
    "sudo apt-get update -qq && sudo apt-get install -y python3-pygresql"

  log "  ✓ Completed installation on $host"
done

log "✅ python3-pygresql installed on all segment hosts"

# --------------------------------------------------------------------
# Clean and create data directories on all hosts
# --------------------------------------------------------------------

log "Step: Setting up data directories on all hosts (coordinator + segments)"

for host in "${ALL_HOSTS[@]}"; do
  log "  → Setting up data directories on $host..."

  # Build the commands to execute
  SETUP_CMDS=""

  # Remove existing data directories for clean start
  for data_dir in "${DATA_DIRS[@]}"; do
    SETUP_CMDS+="sudo rm -rf ${data_dir}; "
  done

  # Create new directories
  for data_dir in "${DATA_DIRS[@]}"; do
    for subdir in "${DATA_SUBDIRS[@]}"; do
      SETUP_CMDS+="sudo mkdir -p ${data_dir}/${subdir}; "
    done
  done

  # Fix ownership and permissions
  SETUP_CMDS+="sudo chown -R cbadmin:cbadmin /data*/; "
  SETUP_CMDS+="sudo chmod -R 755 /data*/"

  # Execute on host
  if [[ "$host" == "$COORDINATOR_HOST" ]]; then
    # Execute locally on coordinator
    bash -c "$SETUP_CMDS"
  else
    # Execute remotely on segment
    # shellcheck disable=SC2029
    ssh "${SSH_OPTS[@]}" "cbadmin@${host}" "$SETUP_CMDS"
  fi

  log "  ✓ Completed setup on $host"
done

log "✅ Data directories created and configured on all hosts"

# --------------------------------------------------------------------
# Create gpinitsystem configuration on coordinator
# --------------------------------------------------------------------

log "Step: Creating gpinitsystem configuration on coordinator"

# Add COORDINATOR_DATA_DIRECTORY to .bashrc
log "  → Adding COORDINATOR_DATA_DIRECTORY to ~/.bashrc"
if ! grep -qF 'export COORDINATOR_DATA_DIRECTORY=/data1/coordinator/cbseg-1' ~/.bashrc; then
  echo 'export COORDINATOR_DATA_DIRECTORY=/data1/coordinator/cbseg-1' >> ~/.bashrc
  log "  ✅ COORDINATOR_DATA_DIRECTORY added to ~/.bashrc"
else
  log "  ℹ️  COORDINATOR_DATA_DIRECTORY already exists in ~/.bashrc (skipped)"
fi

# Create gpinitsystem.conf
log "  → Creating /home/cbadmin/gpinitsystem.conf"
cat >| /home/cbadmin/gpinitsystem.conf <<EOF
ARRAY_NAME="Apache Cloudberry (Incubating) Cluster"
SEG_PREFIX=cbseg
CHECK_POINT_SEGMENTS=8
COORDINATOR_MAX_CONNECT=250
COORDINATOR_PORT=5432
COORDINATOR_HOSTNAME=${COORDINATOR_HOST}
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

log "✅ gpinitsystem configuration created"

# --------------------------------------------------------------------
# Create host files on coordinator
# --------------------------------------------------------------------

log "Step: Creating host files on coordinator"

# Create all_hosts.txt with all hosts (coordinator + segments)
log "  → Creating /home/cbadmin/all_hosts.txt (all hosts)"
{
  echo "$COORDINATOR_HOST"
  for host in "${SEGMENT_HOSTS[@]}"; do
    echo "$host"
  done
} > /home/cbadmin/all_hosts.txt

# Create hostfile_gpinitsystem with segment hosts only
log "  → Creating /home/cbadmin/hostfile_gpinitsystem (segment hosts only)"
{
  for host in "${SEGMENT_HOSTS[@]}"; do
    echo "$host"
  done
} > /home/cbadmin/hostfile_gpinitsystem

log "✅ Host files created"

# --------------------------------------------------------------------
# Summary
# --------------------------------------------------------------------

log ""
log "Multinode cluster setup complete!"
log ""
log "Configuration summary:"
log "  Coordinator:    $COORDINATOR_HOST"
log "  Segment hosts:  ${SEGMENT_HOSTS[*]}"
log "  Data directories: ${DATA_DIRS[*]}"
log ""

section_complete "setup multinode cluster" "$start_time"
