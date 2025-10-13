#!/bin/bash
# --------------------------------------------------------------------
# File     : stations/utilities/wal-g/extended-tests/util.sh
# Purpose  : Utility functions for wal-g extended tests (adapted from wal-g native tests)
# Based on : wal-g/docker/cloudberry_tests/scripts/tests/test_functions/util.sh
# --------------------------------------------------------------------

set -e

# Determine segment directories dynamically from gpdemo environment
get_segment_dirs() {
  local gpdemo_dir="${PARTS_DIR}/cloudberry/gpAux/gpdemo"

  # Initialize SEGMENTS_DIRS array
  SEGMENTS_DIRS=(
    "-1 ${gpdemo_dir}/datadirs/qddir/demoDataDir-1"
  )

  # Add primary segments
  local seg_count=$(psql -t -p "$PGPORT" -d postgres -c "SELECT count(*) FROM gp_segment_configuration WHERE role='p' AND content >= 0;" | xargs)
  for ((i=0; i<seg_count; i++)); do
    SEGMENTS_DIRS+=("$i ${gpdemo_dir}/datadirs/dbfast$((i+1))/demoDataDir${i}")
  done

  export SEGMENTS_DIRS
}

insert_data() {
  echo "Inserting sample data..."
  psql -p "$PGPORT" -d postgres -c "DROP DATABASE IF EXISTS walg_extended_test"
  psql -p "$PGPORT" -d postgres -c "CREATE DATABASE walg_extended_test"
  psql -p "$PGPORT" -d walg_extended_test -c "CREATE TABLE heap AS SELECT a FROM generate_series(1,10) AS a;"
  psql -p "$PGPORT" -d walg_extended_test -c "CREATE TABLE ao(a int, b int) WITH (appendoptimized = true) DISTRIBUTED BY (a);"
  psql -p "$PGPORT" -d walg_extended_test -c "CREATE TABLE co(a int, b int) WITH (appendoptimized = true, orientation = column) DISTRIBUTED BY (a);"
  psql -p "$PGPORT" -d walg_extended_test -c "INSERT INTO ao select i, i FROM generate_series(1,10)i;"
  psql -p "$PGPORT" -d walg_extended_test -c "INSERT INTO co select i, i FROM generate_series(1,10)i;"
}

insert_a_lot_of_data() {
  echo "Inserting large dataset..."
  psql -p "$PGPORT" -d postgres -c "DROP DATABASE IF EXISTS walg_extended_test"
  psql -p "$PGPORT" -d postgres -c "CREATE DATABASE walg_extended_test"
  psql -p "$PGPORT" -d walg_extended_test -c "CREATE TABLE heap AS SELECT a FROM generate_series(1,100000) AS a;"
  psql -p "$PGPORT" -d walg_extended_test -c "CREATE TABLE ao(a int, b int) WITH (appendoptimized = true) DISTRIBUTED BY (a);"
  psql -p "$PGPORT" -d walg_extended_test -c "CREATE TABLE co(a int, b int) WITH (appendoptimized = true, orientation = column) DISTRIBUTED BY (a);"
  psql -p "$PGPORT" -d walg_extended_test -c "INSERT INTO ao select i, i FROM generate_series(1,100000)i;"
  psql -p "$PGPORT" -d walg_extended_test -c "INSERT INTO co select i, i FROM generate_series(1,100000)i;"
}

die_with_cb_logs() {
  echo "ERROR: Test failed. Dumping Cloudberry logs..."
  get_segment_dirs
  for elem in "${SEGMENTS_DIRS[@]}"; do
    read -a arr <<< "$elem"
    echo "*** Content ID ${arr[0]}: ${arr[1]} ***"
    if [ -d "${arr[1]}/log" ]; then
      tail -50 "${arr[1]}"/log/*.csv 2>/dev/null || true
    fi
  done
  exit 1
}

stop_cluster() {
  echo "Stopping Cloudberry cluster..."
  "${GPHOME}"/bin/gpstop -a -M fast
}

start_cluster() {
  echo "Starting Cloudberry cluster..."
  "${GPHOME}"/bin/gpstart -a -t 180 || die_with_cb_logs
}

prepare_cluster_after_restore() {
  echo "Preparing cluster after restore..."
  get_segment_dirs

  # Start coordinator only in utility mode (it will fail in normal mode)
  "${GPHOME}"/bin/gpstart -c -a -t 180 || true

  # Wait until coordinator recovery finishes and starts accepting connections
  for i in {1..180}; do
    PGOPTIONS='-c gp_role=utility' psql -p "$PGPORT" -d postgres -c "SELECT 1;" 2>/dev/null && break || sleep 1
  done

  # Stop coordinator-only mode
  "${GPHOME}"/bin/gpstop -c -a -M fast || true

  # Remove recovery signals and recovery.conf include to allow clean restart
  for elem in "${SEGMENTS_DIRS[@]}"; do
    read -a arr <<< "$elem"
    # Remove recovery signal file
    rm -f "${arr[1]}"/recovery.signal || true

    # Remove recovery.conf files (both old and new style)
    rm -f "${arr[1]}"/recovery.conf || true

    # Remove conf.d/recovery.conf (PG 12+ style)
    if [ -d "${arr[1]}/conf.d" ]; then
      rm -f "${arr[1]}"/conf.d/recovery.conf || true
    fi

    # Remove include_if_exists lines from postgresql.conf (both old and new style)
    if [ -f "${arr[1]}/postgresql.conf" ]; then
      sed -i '/^include_if_exists=recovery.conf/d' "${arr[1]}/postgresql.conf" || true
      sed -i '/^include_if_exists=conf.d\/recovery.conf/d' "${arr[1]}/postgresql.conf" || true
    fi
  done

  # Start the full cluster
  "${GPHOME}"/bin/gpstart -a -t 180 || true

  # Repair any broken segments
  "${GPHOME}"/bin/gprecoverseg -F -a || true

  # Final stop to ensure clean state
  "${GPHOME}"/bin/gpstop -a -M fast || true
}

setup_wal_archiving() {
  echo "Setting up WAL archiving with wal-g..."
  get_segment_dirs

  for elem in "${SEGMENTS_DIRS[@]}"; do
    read -a arr <<< "$elem"
    echo "
wal_level = replica
archive_mode = on
archive_timeout = 600
archive_command = '/usr/bin/timeout 60 /usr/local/bin/wal-g seg wal-push %p --content-id=${arr[0]} --config ${WALG_CONFIG_FILE}'
" >> "${arr[1]}"/postgresql.conf
  done

  stop_cluster
  start_cluster
}

delete_cluster_dirs() {
  echo "Deleting cluster data directories..."

  # SEGMENTS_DIRS should already be populated before stopping the cluster
  if [ ${#SEGMENTS_DIRS[@]} -eq 0 ]; then
    echo "ERROR: SEGMENTS_DIRS not populated"
    return 1
  fi

  for elem in "${SEGMENTS_DIRS[@]}"; do
    read -a arr <<< "$elem"
    rm -rf "${arr[1]}"
  done
}

stop_and_delete_cluster_dir() {
  # Get segment directories BEFORE stopping cluster
  get_segment_dirs

  stop_cluster
  delete_cluster_dirs
}

run_backup_logged() {
  local config_file="$1"
  local data_dir="$2"
  local backup_flags="${3:-}"

  echo "Running backup: wal-g backup-push $backup_flags"

  if /usr/local/bin/wal-g --config="$config_file" backup-push $backup_flags; then
    echo "  ✓ Backup completed successfully"
    return 0
  else
    local exit_status=$?
    echo "ERROR: Backup failed with exit code $exit_status"
    echo "=== wal-g coordinator log ==="
    cat "$WALG_LOG_DIR"/wal-g-gplog.log 2>/dev/null || echo "No coordinator log found"
    echo ""
    echo "=== wal-g segment logs ==="
    for logfile in "$WALG_LOG_DIR"/wal-g-log-seg*.log; do
      if [ -f "$logfile" ]; then
        echo "--- $(basename "$logfile") ---"
        tail -50 "$logfile"
      fi
    done 2>/dev/null || true
    return $exit_status
  fi
}

verify_backup_count() {
  local expected_count=$1
  local backup_list=$2

  # Count actual backup entries (skip header line by excluding "backup_name")
  local actual_count=$(echo "$backup_list" | grep "^backup_" | grep -v "^backup_name" | wc -l)

  if [ "$actual_count" -ne "$expected_count" ]; then
    echo "ERROR: Expected $expected_count backups, but found $actual_count"
    return 1
  fi

  echo "  ✓ Verified $actual_count backup(s)"
  return 0
}

verify_table_data() {
  local database=$1
  local table=$2
  local expected_rows=$3

  local actual_rows=$(psql -t -p "$PGPORT" -d "$database" -c "SELECT count(*) FROM $table;" | xargs)

  if [ "$actual_rows" -ne "$expected_rows" ]; then
    echo "ERROR: Table $table - expected $expected_rows rows, but found $actual_rows"
    return 1
  fi

  echo "  ✓ Table $table has $actual_rows rows (expected $expected_rows)"
  return 0
}

cleanup_test_database() {
  psql -p "$PGPORT" -c "DROP DATABASE IF EXISTS walg_extended_test;" postgres 2>/dev/null || true
}
