#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/cloudberry/gprecoverseg-test.sh
# Purpose  : Test to reproduce gprecoverseg bug with Apache Cloudberry
# Issue    : gprecoverseg fails with "invalid literal for int()" error
#            when parsing files with PPMC notice header
# --------------------------------------------------------------------
# Test Strategy:
#   1. Kill TWO primary segments (simulating multiple failures)
#   2. Wait for mirrors to activate
#   3. Attempt recovery with gprecoverseg -a (may trigger bug)
#   4. Restore to preferred roles with gprecoverseg -ra
#   5. Verify all segments are balanced
# --------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../generic/common.sh"

component_name="cloudberry"
step_name="gprecoverseg-test"

# Workload control variables
WORKLOAD_PIDS=()
WORKLOAD_LOG="/tmp/gprecoverseg-workload-$$.log"
WORKLOAD_ERROR_LOG="/tmp/gprecoverseg-workload-errors-$$.log"
STOP_WORKLOAD=0

log_header "gprecoverseg Bug Reproduction Test with Load Simulation"

# Cleanup function
cleanup_workload() {
    log_info "Stopping workload processes..."
    STOP_WORKLOAD=1
    for pid in "${WORKLOAD_PIDS[@]}"; do
        if ps -p "$pid" >/dev/null 2>&1; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    wait 2>/dev/null || true
}

trap cleanup_workload EXIT

# Workload function - runs continuous inserts
run_insert_workload() {
    local worker_id=$1
    while [[ $STOP_WORKLOAD -eq 0 ]]; do
        psql -d postgres -c "
            INSERT INTO workload_test (worker_id, iteration, data, ts)
            SELECT $worker_id, generate_series(1, 100), md5(random()::text), now();
        " >> "$WORKLOAD_LOG" 2>> "$WORKLOAD_ERROR_LOG" || true
        sleep 0.1
    done
}

# Workload function - runs continuous queries
run_query_workload() {
    local worker_id=$1
    while [[ $STOP_WORKLOAD -eq 0 ]]; do
        psql -d postgres -c "
            SELECT worker_id, count(*), max(iteration), min(ts), max(ts)
            FROM workload_test
            WHERE worker_id = $worker_id
            GROUP BY worker_id;
        " >> "$WORKLOAD_LOG" 2>> "$WORKLOAD_ERROR_LOG" || true
        sleep 0.2
    done
}

# Workload function - runs continuous aggregations
run_aggregate_workload() {
    while [[ $STOP_WORKLOAD -eq 0 ]]; do
        psql -d postgres -c "
            SELECT count(*), count(DISTINCT worker_id),
                   avg(iteration), max(iteration)
            FROM workload_test;
        " >> "$WORKLOAD_LOG" 2>> "$WORKLOAD_ERROR_LOG" || true
        sleep 0.5
    done
}

# Source the gpdemo environment
GPDEMO_ENV="${PARTS_DIR}/${component_name}/gpAux/gpdemo/gpdemo-env.sh"
if [[ -f "${GPDEMO_ENV}" ]]; then
    log_info "Sourcing gpdemo environment from ${GPDEMO_ENV}"
    source "${GPDEMO_ENV}"
else
    log_error "gpdemo-env.sh not found at ${GPDEMO_ENV}"
    exit 1
fi

# Step 1: Verify cluster is running
log_step "Step 1: Verify cluster is running"
if ! gpstate -s >/dev/null 2>&1; then
    log_warning "Cluster not running, attempting to start..."
    gpstart -a || {
        log_error "Failed to start cluster"
        exit 1
    }
fi
log_success "Cluster is running"

# Step 2: Display system and database version information
log_step "Step 2: Display system and database version information"
log_info "=========================================="

# Get OS version
OS_VERSION=""
if [ -f /etc/os-release ]; then
    OS_VERSION=$(grep "^PRETTY_NAME=" /etc/os-release | cut -d= -f2 | tr -d '"' 2>/dev/null || uname -a)
else
    OS_VERSION=$(uname -a)
fi
log_info "OS Version: $OS_VERSION"

log_info ""

# Get Cloudberry version
CB_VERSION=$(postgres --gp-version 2>/dev/null || echo "Unable to retrieve version")
log_info "Cloudberry Database Version: $CB_VERSION"
log_info "=========================================="

# Step 3: Display cluster topology
log_step "Step 3: Display cluster topology"
log_info "=========================================="

# Count unique hosts
UNIQUE_HOSTS=$(psql -d postgres -t -A -c "
    SELECT count(DISTINCT hostname)
    FROM gp_segment_configuration
    WHERE content >= 0;
")
log_info "Cluster Nodes: $UNIQUE_HOSTS unique host(s)"

# Count primaries and mirrors
PRIMARY_COUNT=$(psql -d postgres -t -A -c "
    SELECT count(*)
    FROM gp_segment_configuration
    WHERE content >= 0 AND preferred_role = 'p';
")
MIRROR_COUNT=$(psql -d postgres -t -A -c "
    SELECT count(*)
    FROM gp_segment_configuration
    WHERE content >= 0 AND preferred_role = 'm';
")
log_info "Primary Segments: $PRIMARY_COUNT"
log_info "Mirror Segments: $MIRROR_COUNT"

# Check for standby coordinator
STANDBY_EXISTS=$(psql -d postgres -t -A -c "
    SELECT count(*)
    FROM gp_segment_configuration
    WHERE content = -1 AND role = 'm';
" 2>/dev/null || echo "0")

if [[ "$STANDBY_EXISTS" -gt 0 ]]; then
    STANDBY_HOST=$(psql -d postgres -t -A -c "
        SELECT hostname
        FROM gp_segment_configuration
        WHERE content = -1 AND role = 'm';
    ")
    log_info "Standby Coordinator: YES (on $STANDBY_HOST)"
else
    log_info "Standby Coordinator: NO"
fi

# Display segment distribution per host
log_info ""
log_info "Segment Distribution by Host:"
psql -d postgres -c "
    SELECT
        hostname,
        count(*) FILTER (WHERE preferred_role = 'p') as primaries,
        count(*) FILTER (WHERE preferred_role = 'm') as mirrors,
        count(*) as total_segments
    FROM gp_segment_configuration
    WHERE content >= 0
    GROUP BY hostname
    ORDER BY hostname;
"

log_info "Current Segment Status:"
psql -d postgres -c "
    SELECT
        role,
        preferred_role,
        status,
        mode,
        count(*) as segment_count
    FROM gp_segment_configuration
    WHERE content >= 0
    GROUP BY role, preferred_role, status, mode
    ORDER BY role, preferred_role;
"
log_info "=========================================="

# Step 4: Create workload test table
log_step "Step 4: Create workload test table"
psql -d postgres -c "
    DROP TABLE IF EXISTS workload_test;
    CREATE TABLE workload_test (
        id SERIAL,
        worker_id INT,
        iteration INT,
        data TEXT,
        ts TIMESTAMP
    ) DISTRIBUTED BY (worker_id);
" || {
    log_error "Failed to create workload test table"
    exit 1
}
log_success "Workload test table created"

# Step 5: Start background workload
log_step "Step 5: Start background workload (4 insert workers, 2 query workers, 1 aggregator)"
> "$WORKLOAD_LOG"
> "$WORKLOAD_ERROR_LOG"

# Start insert workers
for i in {1..4}; do
    run_insert_workload $i &
    WORKLOAD_PIDS+=($!)
    log_info "Started insert worker $i (PID: $!)"
done

# Start query workers
for i in {1..2}; do
    run_query_workload $i &
    WORKLOAD_PIDS+=($!)
    log_info "Started query worker $i (PID: $!)"
done

# Start aggregate worker
run_aggregate_workload &
WORKLOAD_PIDS+=($!)
log_info "Started aggregate worker (PID: $!)"

log_success "Started ${#WORKLOAD_PIDS[@]} workload workers"
log_info "Workload log: $WORKLOAD_LOG"
log_info "Workload error log: $WORKLOAD_ERROR_LOG"

# Let workload run for a bit to establish baseline
log_info "Running workload for 10 seconds to establish baseline..."
sleep 10

# Check initial data
INITIAL_COUNT=$(psql -d postgres -t -A -c "SELECT count(*) FROM workload_test;")
log_success "Workload baseline established: $INITIAL_COUNT rows inserted"

# Step 6: Get segment information
log_step "Step 6: Query segment configuration"
psql -d postgres -c "SELECT dbid, content, role, status, port, datadir FROM gp_segment_configuration ORDER BY dbid;"

# Step 7: Select two primary segments to fail
log_step "Step 7: Select two primary segments for failure simulation (WHILE WORKLOAD RUNNING)"
SEGMENTS_INFO=$(psql -d postgres -t -A -F'|' -c "
    SELECT dbid, content, port, datadir
    FROM gp_segment_configuration
    WHERE content >= 0 AND role = 'p'
    ORDER BY content
    LIMIT 2;
")

if [[ -z "$SEGMENTS_INFO" ]]; then
    log_error "No primary segments found"
    exit 1
fi

SEGMENT_COUNT=$(echo "$SEGMENTS_INFO" | wc -l)
if [[ $SEGMENT_COUNT -lt 2 ]]; then
    log_warning "Only $SEGMENT_COUNT primary segment(s) found, expected 2"
fi

log_info "Target segments:"
echo "$SEGMENTS_INFO" | while IFS='|' read -r dbid content port datadir; do
    log_info "  DBID: $dbid, Content: $content, Port: $port, DataDir: $datadir"
done

# Step 8: Kill both segments while workload is running
log_step "Step 8: Simulate multiple segment failures (UNDER LOAD)"
log_warning "Killing segments while workload is actively running..."
FAILED_CONTENTS=()

while IFS='|' read -r DBID CONTENT PORT DATADIR; do
    PID_FILE="$DATADIR/postmaster.pid"

    if [[ ! -f "$PID_FILE" ]]; then
        log_error "PID file not found at $PID_FILE"
        continue
    fi

    SEGMENT_PID=$(head -1 "$PID_FILE")

    if ! ps -p "$SEGMENT_PID" >/dev/null 2>&1; then
        log_error "Segment process $SEGMENT_PID not found"
        continue
    fi

    log_warning "Killing segment Content=$CONTENT PID=$SEGMENT_PID Port=$PORT"
    kill -9 "$SEGMENT_PID"
    log_success "Segment Content=$CONTENT terminated"
    FAILED_CONTENTS+=("$CONTENT")

done <<< "$SEGMENTS_INFO"

if [[ ${#FAILED_CONTENTS[@]} -eq 0 ]]; then
    log_error "Failed to kill any segments"
    exit 1
fi

log_success "Killed ${#FAILED_CONTENTS[@]} segment(s)"

# Step 9: Monitor workload during failure detection
log_step "Step 9: Wait for failure detection (30 seconds) - workload continues running"
log_info "Monitoring workload errors during failure detection..."
sleep 10
ERRORS_DURING_FAILURE=$(wc -l < "$WORKLOAD_ERROR_LOG" 2>/dev/null || echo "0")
log_info "Workload errors so far: $ERRORS_DURING_FAILURE"
sleep 20

# Step 10: Check mirror status with gpstate -m
log_step "Step 10: Check mirror status after failure (gpstate -m)"
log_info "This shows mirrors that have taken primary role:"
gpstate -m || log_warning "gpstate -m failed (may not have mirrors configured)"

# Step 11: Check segment status for failed segments
log_info "Segment status after failures:"
psql -d postgres -c "
    SELECT dbid, content, role, preferred_role, status, mode
    FROM gp_segment_configuration
    WHERE content IN ($(IFS=,; echo "${FAILED_CONTENTS[*]}"))
    ORDER BY content, role;
" 2>&1 || log_warning "Query failed (cluster may be in recovery mode)"

# Step 12: Check workload status before recovery
log_info "Workload status before recovery:"
ROWS_BEFORE_RECOVERY=$(psql -d postgres -t -A -c "SELECT count(*) FROM workload_test;" 2>/dev/null || echo "0")
log_info "Total rows inserted: $ROWS_BEFORE_RECOVERY (started with $INITIAL_COUNT)"

# Step 13: Attempt recovery (workload still running)
log_step "Step 13: Attempt segment recovery with gprecoverseg (UNDER LOAD)"
log_warning "=========================================="
log_warning "RUNNING: gprecoverseg -a"
log_warning "EXPECTING BUG TO OCCUR"
log_warning "=========================================="

set +e
RECOVER_OUTPUT=$(gprecoverseg -a 2>&1)
RECOVER_EXIT=$?
set -e

echo "$RECOVER_OUTPUT"

# Step 14: Analyze initial recovery results
log_step "Step 14: Analyze initial recovery results"
BUG_REPRODUCED=false

if echo "$RECOVER_OUTPUT" | grep -q "invalid literal for int() with base 10"; then
    log_error "=========================================="
    log_error "✓ BUG REPRODUCED!"
    log_error "=========================================="
    log_error ""
    log_error "Found error pattern: 'invalid literal for int()'"

    if echo "$RECOVER_OUTPUT" | grep -q "NOTICE from the Apache Cloudberry PPMC"; then
        log_error "Root cause: Parsing file with Apache Cloudberry PPMC header"
    fi

    log_error ""
    log_error "Test result: BUG CONFIRMED"
    BUG_REPRODUCED=true

elif [[ $RECOVER_EXIT -ne 0 ]]; then
    log_warning "gprecoverseg failed with different error (exit: $RECOVER_EXIT)"
    log_warning "Continuing with rebalance test..."

else
    log_success "=========================================="
    log_success "Initial recovery completed successfully"
    log_success "=========================================="
    log_info "Bug was not reproduced"
fi

# Step 15: Monitor workload during recovery sync
log_step "Step 15: Wait for recovery synchronization (15 seconds) - workload continues"
log_info "Checking workload health during recovery..."
ROWS_DURING_RECOVERY=$(psql -d postgres -t -A -c "SELECT count(*) FROM workload_test;" 2>/dev/null || echo "0")
log_info "Rows inserted during recovery: $ROWS_DURING_RECOVERY"
sleep 15

# Step 16: Check mirror status before rebalance
log_step "Step 16: Check mirror status before rebalance"
log_info "Checking if segments are in preferred roles:"
gpstate -m || log_warning "gpstate -m failed"

# Step 17: Check for segments not in preferred roles
log_info "Segments not in preferred roles:"
psql -d postgres -c "
    SELECT dbid, content, role, preferred_role, status, mode
    FROM gp_segment_configuration
    WHERE role != preferred_role
    ORDER BY content, role;
"

# Step 18: Restore to preferred roles with gprecoverseg -ra (workload still running)
log_step "Step 18: Restore segments to preferred roles (gprecoverseg -ra) - UNDER LOAD"
log_info "Running: gprecoverseg -ra"

set +e
REBALANCE_OUTPUT=$(gprecoverseg -ra 2>&1)
REBALANCE_EXIT=$?
set -e

echo "$REBALANCE_OUTPUT"

if [[ $REBALANCE_EXIT -ne 0 ]]; then
    log_error "Rebalance failed (exit: $REBALANCE_EXIT)"
else
    log_success "Rebalance command completed"
fi

# Step 19: Wait for rebalance to complete (workload still running)
log_step "Step 19: Wait for rebalance to complete (20 seconds) - workload continues"
log_info "Monitoring workload during rebalance..."
sleep 20

# Step 20: Stop workload and collect statistics
log_step "Step 20: Stop workload and collect statistics"
log_info "Stopping all workload workers..."
STOP_WORKLOAD=1
sleep 2

for pid in "${WORKLOAD_PIDS[@]}"; do
    if ps -p "$pid" >/dev/null 2>&1; then
        kill "$pid" 2>/dev/null || true
    fi
done
wait 2>/dev/null || true

log_success "Workload stopped"

# Collect final statistics
FINAL_COUNT=$(psql -d postgres -t -A -c "SELECT count(*) FROM workload_test;" 2>/dev/null || echo "0")
TOTAL_ERRORS=$(wc -l < "$WORKLOAD_ERROR_LOG" 2>/dev/null || echo "0")

log_info "=========================================="
log_info "Workload Statistics:"
log_info "  Initial rows:      $INITIAL_COUNT"
log_info "  Before recovery:   $ROWS_BEFORE_RECOVERY"
log_info "  During recovery:   $ROWS_DURING_RECOVERY"
log_info "  Final count:       $FINAL_COUNT"
log_info "  Total inserted:    $((FINAL_COUNT - INITIAL_COUNT))"
log_info "  Workload errors:   $TOTAL_ERRORS"
log_info "=========================================="

if [[ $TOTAL_ERRORS -gt 0 ]]; then
    log_warning "Workload encountered $TOTAL_ERRORS errors"
    log_info "Last 10 errors from workload:"
    tail -10 "$WORKLOAD_ERROR_LOG" 2>/dev/null || true
fi

# Step 21: Verify all segments are in preferred roles
log_step "Step 21: Verify all segments are in preferred roles"
log_info "Final mirror status:"
gpstate -m || log_warning "gpstate -m failed"

# Check programmatically
MISALIGNED=$(psql -d postgres -t -A -c "
    SELECT count(*)
    FROM gp_segment_configuration
    WHERE role != preferred_role;
")

log_info ""
log_info "=========================================="
if [[ "$MISALIGNED" -eq 0 ]]; then
    log_success "✓ All segments are in preferred roles"
    log_success "Rebalance successful!"
else
    log_error "✗ $MISALIGNED segment(s) not in preferred roles"
    log_error "Rebalance may have failed"
    psql -d postgres -c "
        SELECT dbid, content, role, preferred_role, status, mode
        FROM gp_segment_configuration
        WHERE role != preferred_role;
    "
fi
log_info "=========================================="

# Final test result
log_header "Test Summary"
log_info "Workload: $((FINAL_COUNT - INITIAL_COUNT)) rows inserted, $TOTAL_ERRORS errors"

if [[ "$BUG_REPRODUCED" == "true" ]]; then
    log_error "gprecoverseg bug: REPRODUCED"
    log_info "Workload continued running during bug occurrence"
    exit 1
elif [[ "$MISALIGNED" -ne 0 ]]; then
    log_error "Rebalance: FAILED ($MISALIGNED segments misaligned)"
    exit 1
elif [[ $TOTAL_ERRORS -gt 100 ]]; then
    log_error "Workload: TOO MANY ERRORS ($TOTAL_ERRORS errors during recovery)"
    log_error "This indicates poor resilience under load"
    exit 1
else
    log_success "All tests passed under load!"
    log_success "- No bug reproduced"
    log_success "- Rebalance successful"
    log_success "- Workload completed with $TOTAL_ERRORS errors (acceptable)"
fi

# Cleanup
log_info "Cleaning up workload logs..."
rm -f "$WORKLOAD_LOG" "$WORKLOAD_ERROR_LOG"
