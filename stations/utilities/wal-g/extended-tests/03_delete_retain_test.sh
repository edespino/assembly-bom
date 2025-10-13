#!/bin/bash
# --------------------------------------------------------------------
# File     : stations/utilities/wal-g/extended-tests/03_delete_retain_test.sh
# Purpose  : Backup retention policy test
# Based on : wal-g delete_retain_test.sh
# --------------------------------------------------------------------

set -e -x

TEST_NAME="Delete Retain Test"
source "$(dirname "$0")/util.sh"

echo "========================================"
echo "Test: $TEST_NAME"
echo "========================================"

# Verify cluster is running
if ! gpstate -q &>/dev/null; then
  echo "ERROR: Cloudberry cluster is not running"
  exit 1
fi

# Create initial data
insert_data

# Create 5 backups
for i in {1..5}; do
  echo ""
  echo "Creating backup $i of 5..."
  psql -p "$PGPORT" -d walg_extended_test -c "INSERT INTO heap select i FROM generate_series($((i*100)), $((i*100+10)))i;"
  if [ $i -eq 1 ]; then
    run_backup_logged "${WALG_CONFIG_FILE}" "${COORDINATOR_DATA_DIRECTORY}" "--full"
  else
    run_backup_logged "${WALG_CONFIG_FILE}" "${COORDINATOR_DATA_DIRECTORY}"
  fi
  sleep 2
done

echo ""
echo "Backups before retention:"
BACKUP_LIST=$(/usr/local/bin/wal-g backup-list --config="${WALG_CONFIG_FILE}")
echo "$BACKUP_LIST"
verify_backup_count 5 "$BACKUP_LIST"

# Delete all but last 2 backups
echo ""
echo "Applying retention policy: keep last 2 backups..."
/usr/local/bin/wal-g delete retain 2 --confirm --config="${WALG_CONFIG_FILE}"

echo ""
echo "Backups after retention:"
BACKUP_LIST=$(/usr/local/bin/wal-g backup-list --config="${WALG_CONFIG_FILE}")
echo "$BACKUP_LIST"
verify_backup_count 2 "$BACKUP_LIST"

# Verify we can still restore from retained backup
HEAP_BEFORE=$(psql -t -p "$PGPORT" -d walg_extended_test -c "SELECT count(*) FROM heap;" | xargs)

stop_and_delete_cluster_dir

echo ""
echo "Restoring from retained backup..."
/usr/local/bin/wal-g backup-fetch LATEST --in-place --config="${WALG_CONFIG_FILE}"

prepare_cluster_after_restore
start_cluster

verify_table_data "walg_extended_test" "heap" "$HEAP_BEFORE"

echo ""
echo "✓ $TEST_NAME PASSED"
