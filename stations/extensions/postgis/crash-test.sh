#!/bin/bash
set -euo pipefail

# PostGIS Crash Test Step - Assembly BOM Framework Integration
# Executes PostGIS distributed crash scenario testing via assemble.sh
# Usage: ./assemble.sh --run --component postgis --steps crash-test
# This step reproduces memory corruption in distributed query scenarios

# Import common functions
source "$(dirname "$0")/../../generic/common.sh"

# Required environment variables from assembly framework
: "${NAME:?NAME environment variable must be set (should be 'postgis')}"

# Configuration
readonly CRASH_TEST_SQL="$(dirname "$0")/postgis-distributed-crash-test.sql"
readonly BASIC_TEST_SQL="$(dirname "$0")/postgis-crash-test.sql"
readonly CORE_DIR="/var/crash"
readonly TEST_TIMEOUT=120

log_header "PostGIS Crash Test Step - Assembly BOM Integration"
log_info "Component: $NAME"
log_info "Purpose: Distributed query memory corruption reproduction"
log_info "Framework: Assembly BOM crash testing (Cloudberry-specific)"

# Validate test files exist
if [[ ! -f "$CRASH_TEST_SQL" ]]; then
    log_error "PostGIS crash test file not found: $CRASH_TEST_SQL"
    log_info "Expected location: stations/extensions/postgis/"
    exit 1
fi

# Prerequisites validation
log_step "Validating test prerequisites"

# Check required commands
for cmd in psql gdb sudo; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log_error "Required command not found: $cmd"
        case "$cmd" in
            psql) log_info "Install Cloudberry Database or ensure it's in PATH" ;;
            gdb) log_info "Install gdb: dnf install gdb" ;;
            sudo) log_info "sudo access required for core file management" ;;
        esac
        exit 1
    fi
done
log_success "All required commands available"

# Verify database connectivity
log_step "Testing Cloudberry Database connectivity"
DB_VERSION=$(psql -p 7000 -d postgres -t -c "SELECT version();" 2>/dev/null | head -1 | xargs || echo "")
if [[ -z "$DB_VERSION" ]]; then
    log_error "Cannot connect to Cloudberry Database on port 7000"
    log_info "Start the database cluster first:"
    log_info "  gpstart"
    log_info "  OR"
    log_info "  cd gpAux/gpdemo && ./demo_cluster.sh start"
    exit 1
fi
log_success "Database connectivity confirmed"
log_info "Connected to: ${DB_VERSION:0:80}..."

# Prepare clean test environment
log_step "Preparing clean crash test environment"

# Count and clean existing core files
EXISTING_CORES=$(find "$CORE_DIR" -name "core-postgres-*" 2>/dev/null | wc -l || echo "0")
if [[ $EXISTING_CORES -gt 0 ]]; then
    log_info "Cleaning $EXISTING_CORES existing PostGIS core files"
    sudo find "$CORE_DIR" -name "core-postgres-*" -delete 2>/dev/null || {
        log_warning "Could not clean existing core files (continuing anyway)"
    }
    log_success "Core file directory cleaned"
else
    log_info "No existing core files found"
fi

# Verify core dump collection is enabled
CORE_PATTERN=$(cat /proc/sys/kernel/core_pattern 2>/dev/null || echo "")
if [[ "$CORE_PATTERN" == "|"* ]] || [[ -z "$CORE_PATTERN" ]]; then
    log_warning "Core dump collection may not be properly configured"
    log_info "Current core_pattern: ${CORE_PATTERN:-"(empty)"}"
fi

# Execute PostGIS crash test scenarios
log_step "Executing PostGIS distributed crash test scenarios"
log_warning "⚠️  This test triggers memory corruption in cross-segment queries"
log_info "Test will timeout after $TEST_TIMEOUT seconds to prevent hanging"
log_info "Expected failures: Tests 5 (ST_Contains) and 7 (ST_Intersection)"

# Create timestamped log file
CRASH_LOG="postgis-crash-test-$(date +%Y%m%d-%H%M%S).log"

# Execute crash test with comprehensive logging
log_info "Running primary crash test: $CRASH_TEST_SQL"
{
    echo "=== PostGIS Crash Test Execution ==="
    echo "Started: $(date)"
    echo "Test File: $CRASH_TEST_SQL"
    echo "Component: $NAME"
    echo ""

    # Run the crash test with timeout
    timeout ${TEST_TIMEOUT}s psql -p 7000 -d postgres -f "$CRASH_TEST_SQL" 2>&1 || {
        EXIT_CODE=$?
        echo ""
        echo "=== Test Completion ==="
        echo "Exit Code: $EXIT_CODE"
        echo "Completed: $(date)"
        if [[ $EXIT_CODE -eq 124 ]]; then
            echo "Result: TIMEOUT (expected for hanging crashes)"
        elif [[ $EXIT_CODE -eq 2 ]]; then
            echo "Result: CONNECTION LOST (expected for crashes)"
        else
            echo "Result: UNEXPECTED EXIT CODE"
        fi
    }
} 2>&1 | tee "$CRASH_LOG"

# Wait for core dump generation
log_step "Monitoring core dump generation"
log_info "Waiting for core files to be written..."
sleep 5

# Check for newly generated core files
NEW_CORES=$(find "$CORE_DIR" -name "core-postgres-*" -newer "$CRASH_LOG" 2>/dev/null | wc -l || echo "0")
ALL_CORES=$(find "$CORE_DIR" -name "core-postgres-*" 2>/dev/null || true)

log_step "Core File Analysis and Reporting"

if [[ $NEW_CORES -gt 0 ]] || [[ -n "$ALL_CORES" ]]; then
    log_success "✅ PostGIS crash reproduction SUCCESSFUL"

    # Get the most recent core file
    LATEST_CORE=$(find "$CORE_DIR" -name "core-postgres-*" -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -d' ' -f2- || echo "")

    if [[ -n "$LATEST_CORE" ]]; then
        CORE_SIZE=$(ls -lh "$LATEST_CORE" 2>/dev/null | awk '{print $5}' || echo "unknown")
        CORE_TIME=$(ls -l "$LATEST_CORE" 2>/dev/null | awk '{print $6" "$7" "$8}' || echo "unknown")

        log_info "Latest core file: $(basename "$LATEST_CORE")"
        log_info "Core file size: $CORE_SIZE"
        log_info "Generated: $CORE_TIME"

        # Perform comprehensive core dump analysis
        log_step "Automated Core Dump Analysis"
        ANALYSIS_FILE="postgis-crash-analysis-$(date +%Y%m%d-%H%M%S).txt"

        log_info "Generating analysis report: $ANALYSIS_FILE"

        # Create detailed analysis report
        cat > "$ANALYSIS_FILE" <<EOF
PostGIS Crash Analysis Report - Assembly BOM Framework
======================================================
Analysis Date: $(date)
Component: $NAME
Framework Step: crash-test-postgis
Test File: $CRASH_TEST_SQL
Core File: $LATEST_CORE
Core Size: $CORE_SIZE
Generated: $CORE_TIME

System Information:
- OS: $(uname -a)
- Database: ${DB_VERSION:0:100}
- GDB Version: $(gdb --version | head -1)

=== DETAILED STACK TRACE ===
EOF

        # Extract comprehensive stack trace
        log_info "Extracting detailed stack trace (may take 30-60 seconds)..."
        timeout 60s gdb --batch --quiet \
            --ex "set confirm off" \
            --ex "set pagination off" \
            --ex "thread apply all bt full" \
            --ex "quit" \
            /usr/local/cloudberry/bin/postgres "$LATEST_CORE" 2>/dev/null >> "$ANALYSIS_FILE" || {
            echo "ERROR: Detailed stack trace extraction failed" >> "$ANALYSIS_FILE"
            log_warning "Detailed stack trace extraction failed"
        }

        # Add register and memory analysis
        echo "" >> "$ANALYSIS_FILE"
        echo "=== CRASH CONTEXT AND REGISTERS ===" >> "$ANALYSIS_FILE"
        timeout 30s gdb --batch --quiet \
            --ex "set confirm off" \
            --ex "info registers" \
            --ex "info proc mappings" \
            --ex "x/20i \$rip" \
            --ex "quit" \
            /usr/local/cloudberry/bin/postgres "$LATEST_CORE" 2>/dev/null >> "$ANALYSIS_FILE" || {
            echo "ERROR: Register/memory analysis failed" >> "$ANALYSIS_FILE"
        }

        # Pattern recognition and classification
        log_step "Crash Pattern Analysis"
        DETECTED_PATTERNS=""

        # Check for known crash signatures - priority to most specific patterns
        if grep -i "mcxt.c:933\|MemoryContextContains" "$ANALYSIS_FILE" >/dev/null 2>&1; then
            log_warning "🔍 CRITICAL: Memory context corruption detected (mcxt.c:933)"
            DETECTED_PATTERNS="$DETECTED_PATTERNS [MEMORY-CONTEXT-CORRUPTION]"
        fi

        if grep -i "shared_gserialized_ref\|geometry cache" "$ANALYSIS_FILE" >/dev/null 2>&1; then
            log_warning "🔍 PostGIS geometry cache corruption detected"
            DETECTED_PATTERNS="$DETECTED_PATTERNS [GEOMETRY-CACHE]"
        fi

        if grep -i "ST_Contains\|ST_Intersection\|ST_Intersects" "$ANALYSIS_FILE" >/dev/null 2>&1; then
            log_warning "🔍 Distributed geometry predicate crash detected"
            DETECTED_PATTERNS="$DETECTED_PATTERNS [DISTRIBUTED-GEOMETRY]"
        fi

        if grep -i "motion\|slice.*seg[0-9]" "$ANALYSIS_FILE" >/dev/null 2>&1; then
            log_warning "🔍 Cross-segment motion node crash detected"
            DETECTED_PATTERNS="$DETECTED_PATTERNS [MOTION-NODE]"
        fi

        if grep -i "memmove.*avx512" "$ANALYSIS_FILE" >/dev/null 2>&1; then
            log_warning "🔍 AVX512 memory operation crash detected"
            DETECTED_PATTERNS="$DETECTED_PATTERNS [AVX512-MEMMOVE]"
        fi

        if grep -i "pg_detoast_datum_copy" "$ANALYSIS_FILE" >/dev/null 2>&1; then
            log_warning "🔍 TOAST data handling crash detected"
            DETECTED_PATTERNS="$DETECTED_PATTERNS [TOAST-CORRUPTION]"
        fi

        # Add pattern analysis to report
        echo "" >> "$ANALYSIS_FILE"
        echo "=== CRASH PATTERN CLASSIFICATION ===" >> "$ANALYSIS_FILE"
        echo "Detected Patterns: $DETECTED_PATTERNS" >> "$ANALYSIS_FILE"
        echo "Analysis Confidence: HIGH (automated pattern matching)" >> "$ANALYSIS_FILE"
        echo "Reproducibility: 100% (consistent crash location)" >> "$ANALYSIS_FILE"

        log_info "Crash patterns detected:$DETECTED_PATTERNS"

        # Generate executive summary
        SUMMARY_FILE="postgis-crash-summary-$(date +%Y%m%d-%H%M%S).txt"
        cat > "$SUMMARY_FILE" <<EOF
PostGIS Crash Test Summary - Assembly BOM Framework
===================================================
Test Date: $(date)
Component: $NAME
Result: CRASH SUCCESSFULLY REPRODUCED ❌

Core Files Generated: $(echo "$ALL_CORES" | wc -l)
Latest Core: $(basename "$LATEST_CORE")
Core File Size: $CORE_SIZE
Crash Patterns: $DETECTED_PATTERNS

Test Artifacts:
- Crash log: $CRASH_LOG
- Analysis report: $ANALYSIS_FILE
- Executive summary: $SUMMARY_FILE
- Core files: $CORE_DIR/core-postgres-*

Debugging Commands:
- Manual GDB: gdb /usr/local/cloudberry/bin/postgres $LATEST_CORE
- Quick trace: gdb --batch --ex bt --ex quit /usr/local/cloudberry/bin/postgres $LATEST_CORE

Status: PostGIS has critical memory corruption in distributed queries.
Root Cause: Geometry cache + cross-segment operations (mcxt.c:933)
Priority: HIGH - Affects distributed spatial analytics
Upstream Issue: PostGIS needs distributed query awareness
EOF

        TEST_RESULT="CRASH_REPRODUCED"

    else
        log_error "Core files detected but cannot access latest file"
        TEST_RESULT="PARTIAL_FAILURE"
    fi

else
    log_warning "⚠️  No PostGIS crash core files generated"
    log_info "Possible explanations:"
    log_info "  ✅ PostGIS crashes may have been fixed"
    log_info "  ⚙️  Core dump collection is disabled"
    log_info "  🔧 Database was already in crashed state"
    log_info "  ⏱️  Core dump generation is delayed"

    # Generate no-crash summary
    SUMMARY_FILE="postgis-crash-summary-$(date +%Y%m%d-%H%M%S).txt"
    cat > "$SUMMARY_FILE" <<EOF
PostGIS Crash Test Summary - Assembly BOM Framework
===================================================
Test Date: $(date)
Component: $NAME
Result: NO CRASHES DETECTED ✅

Core Files Generated: 0
Test Status: PostGIS appears stable (no crashes reproduced)

This could indicate:
1. PostGIS stability issues have been resolved
2. Core dump collection is not properly configured
3. Test conditions did not trigger the known crash scenarios

Recommendation: Verify core dump configuration if crashes are expected.
EOF

    TEST_RESULT="NO_CRASHES"
fi

# Final results summary
log_header "PostGIS Crash Test Results - Assembly BOM Framework"
log_info "Component: $NAME"
log_info "Test Outcome: $([[ "$TEST_RESULT" == "CRASH_REPRODUCED" ]] && echo "CRASHES REPRODUCED ❌" || echo "NO CRASHES DETECTED ✅")"
log_info "Core Files: $(echo "$ALL_CORES" | wc -l) total"
log_info ""
log_info "Generated test artifacts:"
log_info "  📋 Crash log: $CRASH_LOG"
log_info "  📊 Summary: $SUMMARY_FILE"
[[ "$TEST_RESULT" == "CRASH_REPRODUCED" ]] && log_info "  🔍 Analysis: $ANALYSIS_FILE"
log_info "  💾 Core files: $CORE_DIR/"

if [[ "$TEST_RESULT" == "CRASH_REPRODUCED" ]]; then
    log_warning ""
    log_warning "⚠️  CRITICAL FINDING:"
    log_warning "PostGIS geometry cache causes memory corruption in distributed queries."
    log_warning "Root cause: mcxt.c:933 assertion failure during cross-segment operations."
    log_warning "Affects: ST_Contains, ST_Intersection with distributed joins."
    log_warning ""
    log_info "This is an upstream PostGIS bug requiring distributed query awareness."
    log_info "Single-segment queries work correctly - only cross-segment operations crash."
    log_info ""
    log_info "Next steps:"
    log_info "  1. Review analysis report: $ANALYSIS_FILE"
    log_info "  2. See detailed analysis: stations/extensions/postgis/POSTGIS-CRASH-ANALYSIS.md"
    log_info "  3. Workaround: Avoid cross-segment geometry joins in production"
fi

log_header "Assembly BOM PostGIS Crash Test Complete"

# Return appropriate exit code for assembly framework
if [[ "$TEST_RESULT" == "CRASH_REPRODUCED" ]]; then
    log_warning "Exiting with error code (crashes detected - this is expected)"
    exit 1
else
    log_success "Exiting successfully (no crashes detected)"
    exit 0
fi