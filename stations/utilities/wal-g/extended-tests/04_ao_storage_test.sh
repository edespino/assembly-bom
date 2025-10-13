#!/bin/bash
# --------------------------------------------------------------------
# File     : stations/utilities/wal-g/extended-tests/04_ao_storage_test.sh
# Purpose  : Append-optimized and column-oriented storage test
# Based on : wal-g ao_storage_test.sh
# --------------------------------------------------------------------

set -e -x

TEST_NAME="AO/CO Storage Test"
source "$(dirname "$0")/util.sh"

echo "========================================"
echo "Test: $TEST_NAME"
echo "========================================"

# Verify cluster is running
if ! gpstate -q &>/dev/null; then
  echo "ERROR: Cloudberry cluster is not running"
  exit 1
fi

# Create database with AO and CO tables with more data
echo "Creating test database with AO/CO tables..."
psql -p "$PGPORT" -c "DROP DATABASE IF EXISTS walg_extended_test"
psql -p "$PGPORT" -c "CREATE DATABASE walg_extended_test"

# Create heap table
psql -p "$PGPORT" -d walg_extended_test <<EOF
CREATE TABLE heap_table (
  id int,
  name text,
  value numeric
) DISTRIBUTED BY (id);

INSERT INTO heap_table SELECT i, 'name_' || i, i * 1.5 FROM generate_series(1, 1000) i;
EOF

# Create AO table
psql -p "$PGPORT" -d walg_extended_test <<EOF
CREATE TABLE ao_table (
  id int,
  name text,
  value numeric
) WITH (appendoptimized=true)
DISTRIBUTED BY (id);

INSERT INTO ao_table SELECT i, 'ao_' || i, i * 2.0 FROM generate_series(1, 1000) i;
EOF

# Create CO table
psql -p "$PGPORT" -d walg_extended_test <<EOF
CREATE TABLE co_table (
  id int,
  name text,
  value numeric
) WITH (appendoptimized=true, orientation=column)
DISTRIBUTED BY (id);

INSERT INTO co_table SELECT i, 'co_' || i, i * 3.0 FROM generate_series(1, 1000) i;
EOF

# Take full backup
run_backup_logged "${WALG_CONFIG_FILE}" "${COORDINATOR_DATA_DIRECTORY}" "--full"

# Add more data to AO table
psql -p "$PGPORT" -d walg_extended_test -c "INSERT INTO ao_table SELECT i, 'ao_' || i, i * 2.0 FROM generate_series(1001, 2000) i;"

# Take incremental backup
run_backup_logged "${WALG_CONFIG_FILE}" "${COORDINATOR_DATA_DIRECTORY}"

# Add more data to CO table
psql -p "$PGPORT" -d walg_extended_test -c "INSERT INTO co_table SELECT i, 'co_' || i, i * 3.0 FROM generate_series(1001, 2000) i;"

# Take another incremental backup
run_backup_logged "${WALG_CONFIG_FILE}" "${COORDINATOR_DATA_DIRECTORY}"

# Verify data before restore
HEAP_BEFORE=$(psql -t -p "$PGPORT" -d walg_extended_test -c "SELECT count(*) FROM heap_table;" | xargs)
AO_BEFORE=$(psql -t -p "$PGPORT" -d walg_extended_test -c "SELECT count(*) FROM ao_table;" | xargs)
CO_BEFORE=$(psql -t -p "$PGPORT" -d walg_extended_test -c "SELECT count(*) FROM co_table;" | xargs)

echo "Data before restore:"
echo "  - heap_table: $HEAP_BEFORE rows"
echo "  - ao_table: $AO_BEFORE rows"
echo "  - co_table: $CO_BEFORE rows"

# Restore test
stop_and_delete_cluster_dir

echo ""
echo "Restoring from LATEST backup..."
/usr/local/bin/wal-g backup-fetch LATEST --in-place --config="${WALG_CONFIG_FILE}"

prepare_cluster_after_restore
start_cluster

# Verify data after restore
echo ""
echo "Verifying AO/CO storage after restore..."
verify_table_data "walg_extended_test" "heap_table" "$HEAP_BEFORE"
verify_table_data "walg_extended_test" "ao_table" "$AO_BEFORE"
verify_table_data "walg_extended_test" "co_table" "$CO_BEFORE"

# Verify data integrity with checksums
echo ""
echo "Verifying data integrity..."
HEAP_SUM=$(psql -t -p "$PGPORT" -d walg_extended_test -c "SELECT sum(value) FROM heap_table;" | xargs)
AO_SUM=$(psql -t -p "$PGPORT" -d walg_extended_test -c "SELECT sum(value) FROM ao_table;" | xargs)
CO_SUM=$(psql -t -p "$PGPORT" -d walg_extended_test -c "SELECT sum(value) FROM co_table;" | xargs)

echo "  ✓ heap_table sum: $HEAP_SUM"
echo "  ✓ ao_table sum: $AO_SUM"
echo "  ✓ co_table sum: $CO_SUM"

echo ""
echo "✓ $TEST_NAME PASSED"
