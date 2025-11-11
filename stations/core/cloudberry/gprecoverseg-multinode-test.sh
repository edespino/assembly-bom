#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/core/cloudberry/gprecoverseg-multinode-test.sh
# Purpose  : Test gprecoverseg in multinode environment with host failure
# --------------------------------------------------------------------
# Test Strategy:
#   1. Verify multinode cluster is running
#   2. Select ONE segment host for failure simulation
#   3. Trigger failure with "sudo reboot" on segment host
#   4. Wait for mirrors to activate on remaining hosts
#   5. Wait for failed host to come back online
#   6. Attempt recovery with gprecoverseg -a
#   7. Restore to preferred roles with gprecoverseg -ra
#   8. Verify all segments are balanced
# --------------------------------------------------------------------

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../generic/common.sh"

component_name="cloudberry"
step_name="gprecoverseg-multinode-test"

# Workload control variables
WORKLOAD_PIDS=()
WORKLOAD_LOG="/tmp/gprecoverseg-multinode-workload-$$.log"
WORKLOAD_ERROR_LOG="/tmp/gprecoverseg-multinode-workload-errors-$$.log"
STOP_WORKLOAD=0

# SSH options for segment hosts
SSH_OPTS=(-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5)

# Timeout for host recovery (seconds)
HOST_RECOVERY_TIMEOUT=300  # 5 minutes

log_header "gprecoverseg Multinode Test with Host Failure Simulation"

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

# Use existing cluster environment from user's shell
# The multinode cluster environment should already be configured in ~/.bashrc
# with COORDINATOR_DATA_DIRECTORY and other variables

log_info "Using cluster environment from shell"
if [[ -z "${COORDINATOR_DATA_DIRECTORY:-}" ]]; then
    log_error "COORDINATOR_DATA_DIRECTORY not set in environment"
    log_error "Please ensure your multinode cluster environment is configured"
    log_error "Hint: source ~/.bashrc or set COORDINATOR_DATA_DIRECTORY manually"
    exit 1
fi

log_info "  COORDINATOR_DATA_DIRECTORY: ${COORDINATOR_DATA_DIRECTORY}"
log_info "  PGPORT: ${PGPORT:-5432}"

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

# Step 3: Verify multinode cluster topology
log_step "Step 3: Verify multinode cluster topology"
log_info "=========================================="

# Count unique hosts
UNIQUE_HOSTS=$(psql -d postgres -t -A -c "
    SELECT count(DISTINCT hostname)
    FROM gp_segment_configuration
    WHERE content >= 0;
")
log_info "Cluster Nodes: $UNIQUE_HOSTS unique host(s)"

if [[ "$UNIQUE_HOSTS" -lt 2 ]]; then
    log_error "=========================================="
    log_error "MULTINODE CLUSTER REQUIRED"
    log_error "=========================================="
    log_error ""
    log_error "This test requires a multinode cluster with at least 2 hosts."
    log_error "Current cluster has only $UNIQUE_HOSTS host(s)."
    log_error ""
    log_error "Please run the 'setup-multinode' step first to create a multinode cluster."
    log_error ""
    exit 1
fi

log_success "Multinode cluster detected ($UNIQUE_HOSTS hosts)"

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

if [[ "$MIRROR_COUNT" -eq 0 ]]; then
    log_error "No mirrors configured - cannot test recovery"
    exit 1
fi

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
psql -d postgres -c "SELECT dbid, content, role, preferred_role, status, hostname, port FROM gp_segment_configuration WHERE content >= 0 ORDER BY hostname, content;"

# Step 7: Select segment host to fail
log_step "Step 7: Select segment host for failure simulation (WHILE WORKLOAD RUNNING)"

# Get the first segment host (not coordinator)
COORDINATOR_HOST=$(hostname -s)
FAILED_HOST=$(psql -d postgres -t -A -c "
    SELECT DISTINCT hostname
    FROM gp_segment_configuration
    WHERE content >= 0
      AND role = 'p'
      AND hostname != '$(hostname -s)'
    ORDER BY hostname
    LIMIT 1;
")

if [[ -z "$FAILED_HOST" ]]; then
    log_error "No segment host found to fail (hosts must be different from coordinator)"
    exit 1
fi

# Count segments on failed host
SEGMENTS_ON_HOST=$(psql -d postgres -t -A -c "
    SELECT count(*)
    FROM gp_segment_configuration
    WHERE hostname = '$FAILED_HOST' AND content >= 0;
")

# Get segment details
SEGMENT_DETAILS=$(psql -d postgres -t -A -F'|' -c "
    SELECT dbid, content, role, preferred_role, port
    FROM gp_segment_configuration
    WHERE hostname = '$FAILED_HOST' AND content >= 0
    ORDER BY content;
")

log_warning "=========================================="
log_warning "Target Host: $FAILED_HOST"
log_warning "Segments on host: $SEGMENTS_ON_HOST"
log_warning "=========================================="
log_info ""
log_info "Segments that will fail:"
echo "$SEGMENT_DETAILS" | while IFS='|' read -r dbid content role preferred_role port; do
    log_info "  DBID: $dbid, Content: $content, Role: $role, Preferred: $preferred_role, Port: $port"
done
log_info ""

# Store failed content IDs for later verification
FAILED_CONTENTS=($(psql -d postgres -t -A -c "
    SELECT content
    FROM gp_segment_configuration
    WHERE hostname = '$FAILED_HOST' AND content >= 0
    ORDER BY content;
"))

log_info "Will fail content IDs: ${FAILED_CONTENTS[*]}"

# Step 8: Verify SSH connectivity before reboot
log_step "Step 8: Verify SSH connectivity to target host"
if ssh "${SSH_OPTS[@]}" "cbadmin@${FAILED_HOST}" "echo 'SSH connectivity verified'" >/dev/null 2>&1; then
    log_success "SSH connection to $FAILED_HOST successful"
else
    log_error "Cannot SSH to $FAILED_HOST - aborting test"
    exit 1
fi

# Step 9: Trigger host failure with reboot
log_step "Step 9: Simulate host failure with reboot (UNDER LOAD)"
log_warning "=========================================="
log_warning "TRIGGERING HOST FAILURE"
log_warning "Command: sudo reboot (on $FAILED_HOST)"
log_warning "=========================================="

# Trigger reboot (will fail/disconnect, which is expected)
ssh "${SSH_OPTS[@]}" "cbadmin@${FAILED_HOST}" "sudo reboot" 2>/dev/null || true

log_warning "Reboot command sent to $FAILED_HOST"

# Step 10: Wait for host to go offline
log_step "Step 10: Wait for host to go offline"
HOST_OFFLINE=false
for i in {1..30}; do
    if ! ssh "${SSH_OPTS[@]}" "cbadmin@${FAILED_HOST}" "echo ok" >/dev/null 2>&1; then
        log_success "Host $FAILED_HOST is offline (attempt $i)"
        HOST_OFFLINE=true
        break
    fi
    log_info "Attempt $i/30: Host still responding, waiting..."
    sleep 2
done

if [[ "$HOST_OFFLINE" == "false" ]]; then
    log_warning "Host did not go offline as expected (may have failed to reboot)"
    log_warning "Continuing with test anyway..."
fi

# Step 11: Monitor workload during failure detection
log_step "Step 11: Wait for failure detection (30 seconds) - workload continues running"
log_info "Monitoring workload errors during failure detection..."
sleep 10
ERRORS_DURING_FAILURE=$(wc -l < "$WORKLOAD_ERROR_LOG" 2>/dev/null || echo "0")
log_info "Workload errors so far: $ERRORS_DURING_FAILURE"
sleep 20

# Step 12: Check mirror status with gpstate -m
log_step "Step 12: Check mirror status after host failure (gpstate -m)"
log_info "This shows mirrors that have taken primary role:"
gpstate -m || log_warning "gpstate -m failed"

# Step 13: Check segment status for failed segments
log_info "Segment status after host failure:"
psql -d postgres -c "
    SELECT dbid, content, role, preferred_role, status, mode, hostname
    FROM gp_segment_configuration
    WHERE content IN ($(IFS=,; echo "${FAILED_CONTENTS[*]}"))
    ORDER BY content, role;
" 2>&1 || log_warning "Query failed (cluster may be in recovery mode)"

# Step 14: Check workload status before recovery
log_info "Workload status before recovery:"
ROWS_BEFORE_RECOVERY=$(psql -d postgres -t -A -c "SELECT count(*) FROM workload_test;" 2>/dev/null || echo "0")
log_info "Total rows inserted: $ROWS_BEFORE_RECOVERY (started with $INITIAL_COUNT)"

# Step 15: Wait for failed host to come back online
log_step "Step 15: Wait for host $FAILED_HOST to come back online (max ${HOST_RECOVERY_TIMEOUT}s)"
HOST_ONLINE=false
POLL_INTERVAL=10
MAX_ATTEMPTS=$((HOST_RECOVERY_TIMEOUT / POLL_INTERVAL))

for i in $(seq 1 $MAX_ATTEMPTS); do
    log_info "Attempt $i/$MAX_ATTEMPTS: Checking if $FAILED_HOST is online..."

    if ssh "${SSH_OPTS[@]}" "cbadmin@${FAILED_HOST}" "echo 'Host is back'" >/dev/null 2>&1; then
        log_success "=========================================="
        log_success "Host $FAILED_HOST is back online!"
        log_success "=========================================="
        HOST_ONLINE=true
        break
    fi

    if [[ $i -lt $MAX_ATTEMPTS ]]; then
        sleep $POLL_INTERVAL
    fi
done

if [[ "$HOST_ONLINE" == "false" ]]; then
    log_error "=========================================="
    log_error "HOST RECOVERY TIMEOUT"
    log_error "=========================================="
    log_error ""
    log_error "Host $FAILED_HOST did not come back online within ${HOST_RECOVERY_TIMEOUT} seconds"
    log_error ""
    log_error "Test cannot continue without the failed host being available."
    log_error ""
    log_error "Please check:"
    log_error "  1. Host reboot status"
    log_error "  2. Network connectivity"
    log_error "  3. SSH service on host"
    log_error ""
    exit 1
fi

# Give host a bit more time to fully initialize services
log_info "Waiting 15 seconds for host services to fully initialize..."
sleep 15

# Step 16: Attempt recovery (workload still running)
log_step "Step 16: Attempt segment recovery with gprecoverseg (UNDER LOAD)"
log_warning "=========================================="
log_warning "RUNNING: gprecoverseg -a"
log_warning "=========================================="

set +e
RECOVER_OUTPUT=$(gprecoverseg -a 2>&1)
RECOVER_EXIT=$?
set -e

echo "$RECOVER_OUTPUT"

# Step 17: Analyze initial recovery results
log_step "Step 17: Analyze initial recovery results"

if [[ $RECOVER_EXIT -ne 0 ]]; then
    log_warning "gprecoverseg failed (exit: $RECOVER_EXIT)"

    if echo "$RECOVER_OUTPUT" | grep -q "invalid literal for int() with base 10"; then
        log_error "=========================================="
        log_error "✓ BUG REPRODUCED!"
        log_error "=========================================="
        log_error ""
        log_error "Found error pattern: 'invalid literal for int()'"
        log_error "This is the known gprecoverseg parsing bug"
        log_error ""
        exit 1
    else
        log_warning "Different error occurred, continuing with test..."
    fi
else
    log_success "=========================================="
    log_success "Initial recovery completed successfully"
    log_success "=========================================="
fi

# Step 18: Monitor workload during recovery sync
log_step "Step 18: Wait for recovery synchronization (15 seconds) - workload continues"
log_info "Checking workload health during recovery..."
ROWS_DURING_RECOVERY=$(psql -d postgres -t -A -c "SELECT count(*) FROM workload_test;" 2>/dev/null || echo "0")
log_info "Rows inserted during recovery: $ROWS_DURING_RECOVERY"
sleep 15

# Step 19: Check mirror status before rebalance
log_step "Step 19: Check mirror status before rebalance"
log_info "Checking if segments are in preferred roles:"
gpstate -m || log_warning "gpstate -m failed"

# Step 20: Check for segments not in preferred roles
log_info "Segments not in preferred roles:"
psql -d postgres -c "
    SELECT dbid, content, role, preferred_role, status, mode, hostname
    FROM gp_segment_configuration
    WHERE role != preferred_role
    ORDER BY content, role;
"

# Step 21: Restore to preferred roles with gprecoverseg -ra (workload still running)
log_step "Step 21: Restore segments to preferred roles (gprecoverseg -ra) - UNDER LOAD"
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

# Step 22: Wait for rebalance to complete (workload still running)
log_step "Step 22: Wait for rebalance to complete (20 seconds) - workload continues"
log_info "Monitoring workload during rebalance..."
sleep 20

# Step 23: Stop workload and collect statistics
log_step "Step 23: Stop workload and collect statistics"
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

# Step 24: Verify all segments are in preferred roles
log_step "Step 24: Verify all segments are in preferred roles"
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
        SELECT dbid, content, role, preferred_role, status, mode, hostname
        FROM gp_segment_configuration
        WHERE role != preferred_role;
    "
fi
log_info "=========================================="

# Final test result
log_header "Test Summary"
log_info "Host failed: $FAILED_HOST ($SEGMENTS_ON_HOST segments)"
log_info "Workload: $((FINAL_COUNT - INITIAL_COUNT)) rows inserted, $TOTAL_ERRORS errors"

if [[ "$MISALIGNED" -ne 0 ]]; then
    log_error "Rebalance: FAILED ($MISALIGNED segments misaligned)"
    exit 1
elif [[ $TOTAL_ERRORS -gt 100 ]]; then
    log_error "Workload: TOO MANY ERRORS ($TOTAL_ERRORS errors during recovery)"
    log_error "This indicates poor resilience under load"
    exit 1
else
    log_success "All tests passed under load!"
    log_success "- Host recovery successful"
    log_success "- Segment recovery successful"
    log_success "- Rebalance successful"
    log_success "- Workload completed with $TOTAL_ERRORS errors (acceptable)"
fi

# Cleanup
log_info "Cleaning up workload logs..."
rm -f "$WORKLOAD_LOG" "$WORKLOAD_ERROR_LOG"
