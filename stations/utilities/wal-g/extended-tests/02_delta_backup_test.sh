#!/bin/bash
# --------------------------------------------------------------------
# File     : stations/utilities/wal-g/extended-tests/02_delta_backup_test.sh
# Purpose  : Delta (incremental) backup test
# Based on : wal-g delta_backup_test.sh
# --------------------------------------------------------------------

set -e -x

TEST_NAME="Delta Backup Test"
source "$(dirname "$0")/util.sh"

echo "========================================"
echo "Test: $TEST_NAME"
echo "========================================"

# Verify cluster is running
if ! gpstate -q &>/dev/null; then
  echo "ERROR: Cloudberry cluster is not running"
  exit 1
fi

# Create initial data and full backup
insert_data
run_backup_logged "${WALG_CONFIG_FILE}" "${COORDINATOR_DATA_DIRECTORY}" "--full"

# Take first delta backup
psql -p "$PGPORT" -d walg_extended_test -c "INSERT INTO heap select i FROM generate_series(11,20)i;"
run_backup_logged "${WALG_CONFIG_FILE}" "${COORDINATOR_DATA_DIRECTORY}" "--delta-from-name=LATEST"

# Take second delta backup
psql -p "$PGPORT" -d walg_extended_test -c "INSERT INTO ao select i, i FROM generate_series(11,30)i;"
run_backup_logged "${WALG_CONFIG_FILE}" "${COORDINATOR_DATA_DIRECTORY}" "--delta-from-name=LATEST"

# Take third delta backup
psql -p "$PGPORT" -d walg_extended_test -c "INSERT INTO co select i, i FROM generate_series(11,40)i;"
run_backup_logged "${WALG_CONFIG_FILE}" "${COORDINATOR_DATA_DIRECTORY}" "--delta-from-name=LATEST"

# Show backup list
echo ""
echo "Listing available backups:"
BACKUP_LIST=$(/usr/local/bin/wal-g backup-list --config="${WALG_CONFIG_FILE}")
echo "$BACKUP_LIST"

verify_backup_count 4 "$BACKUP_LIST"

# Save data for verification
HEAP_BEFORE=$(psql -t -p "$PGPORT" -d walg_extended_test -c "SELECT count(*) FROM heap;" | xargs)
AO_BEFORE=$(psql -t -p "$PGPORT" -d walg_extended_test -c "SELECT count(*) FROM ao;" | xargs)
CO_BEFORE=$(psql -t -p "$PGPORT" -d walg_extended_test -c "SELECT count(*) FROM co;" | xargs)

echo "Data before restore:"
echo "  - heap: $HEAP_BEFORE rows"
echo "  - ao: $AO_BEFORE rows"
echo "  - co: $CO_BEFORE rows"

# Test restore from delta backup
stop_and_delete_cluster_dir

echo ""
echo "Restoring from LATEST delta backup..."
/usr/local/bin/wal-g backup-fetch LATEST --in-place --config="${WALG_CONFIG_FILE}"

prepare_cluster_after_restore
start_cluster

# Verify data after restore
echo ""
echo "Verifying data after restore from delta backup..."
verify_table_data "walg_extended_test" "heap" "$HEAP_BEFORE"
verify_table_data "walg_extended_test" "ao" "$AO_BEFORE"
verify_table_data "walg_extended_test" "co" "$CO_BEFORE"

echo ""
echo "✓ $TEST_NAME PASSED"
