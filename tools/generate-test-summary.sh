#!/usr/bin/env bash
set -euo pipefail

# Enhanced Fluss Test Summary Generator
LOG_FILE="${1:?Usage: $0 <log-file>}"

if [[ ! -f "$LOG_FILE" ]]; then
  echo "Error: Log file not found: $LOG_FILE"
  exit 1
fi

echo "==========================================="
echo "Comprehensive Apache Fluss Test Summary"
echo "==========================================="
echo "Log: $LOG_FILE"
echo ""

# Aggregate all test results
echo "Aggregating test results..."
TOTAL_TESTS=$(grep "Tests run:" "$LOG_FILE" | awk -F'Tests run: ' '{print $2}' | awk -F',' '{print $1}' | awk '{sum+=$1} END {print sum}')
TOTAL_FAILURES=$(grep "Tests run:" "$LOG_FILE" | awk -F'Failures: ' '{print $2}' | awk -F',' '{print $1}' | awk '{sum+=$1} END {print sum}')
TOTAL_ERRORS=$(grep "Tests run:" "$LOG_FILE" | awk -F'Errors: ' '{print $2}' | awk -F',' '{print $1}' | awk '{sum+=$1} END {print sum}')
TOTAL_SKIPPED=$(grep "Tests run:" "$LOG_FILE" | awk -F'Skipped: ' '{print $2}' | awk -F',' '{print $1}' | awk '{sum+=$1} END {print sum}')
TEST_CLASSES=$(grep "Tests run:" "$LOG_FILE" | wc -l)

echo ""
echo "==========================================="
echo "Aggregate Test Results"
echo "==========================================="
echo "Test Classes: $TEST_CLASSES"
echo "Total Tests: $TOTAL_TESTS"
echo "Failures: $TOTAL_FAILURES"
echo "Errors: $TOTAL_ERRORS"
echo "Skipped: $TOTAL_SKIPPED"

if [[ $TOTAL_TESTS -gt 0 ]]; then
  echo "Success Rate: $(awk "BEGIN {printf \"%.2f%%\", ($TOTAL_TESTS - $TOTAL_FAILURES - $TOTAL_ERRORS) / $TOTAL_TESTS * 100}")"
fi
echo ""

# Show skipped tests
if [[ $TOTAL_SKIPPED -gt 0 ]]; then
  echo "==========================================="
  echo "Skipped Tests Breakdown"
  echo "==========================================="
  grep -E "Skipped: [1-9]" "$LOG_FILE" | grep -v "Skipped: 0" | head -20
  echo ""
fi

# Find failures if any
if [[ $TOTAL_FAILURES -gt 0 ]] || [[ $TOTAL_ERRORS -gt 0 ]]; then
  echo "==========================================="
  echo "Failed/Error Tests"
  echo "==========================================="
  grep -E "(Failures: [1-9]|Errors: [1-9])" "$LOG_FILE" | head -30
  echo ""
fi

# Maven reactor summary for test phase
echo "==========================================="
echo "Maven Reactor Test Summary"
echo "==========================================="
# Find the reactor summary from the test phase (not build phase)
grep -E "^\[INFO\] Reactor Summary" -A 50 "$LOG_FILE" | tail -n 60 | head -50
echo ""

# Build status
if grep -q "BUILD SUCCESS" "$LOG_FILE" | tail -1; then
  echo "✅ BUILD SUCCESS"
elif grep -q "BUILD FAILURE" "$LOG_FILE" | tail -1; then
  echo "❌ BUILD FAILURE"
else
  echo "⚠ BUILD STATUS UNKNOWN"
fi
