#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Import common functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../generic/common.sh"

# Get component name from environment (exported by assemble.sh)
COMPONENT_NAME="${NAME:?Missing NAME environment variable}"

# Environment variables from BOM
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$COMPONENT_NAME"

log_info "========================================="
log_info "Testing GeaFlow - GQL Demo"
log_info "========================================="
log_info "Component: $COMPONENT_NAME"
log_info "Directory: $COMPONENT_DIR"
echo ""

# Find the extracted source directory (exclude the component directory itself)
EXTRACTED_DIR=$(find "$COMPONENT_DIR" -maxdepth 1 -type d -not -path "$COMPONENT_DIR" | head -1)
if [[ -z "$EXTRACTED_DIR" ]]; then
  log_error "No extracted source directory found"
  log_info "Please run extract step first"
  exit 1
fi

log_info "Source: $EXTRACTED_DIR"
echo ""

# Change to extracted directory
cd "$EXTRACTED_DIR"

log_info "========================================="
log_info "Step 1: Checking Prerequisites"
log_info "========================================="

# Check if build completed
if [[ ! -d "package" ]] && [[ ! -d "target" ]]; then
  log_error "Build artifacts not found"
  log_info "Please run build step first"
  log_info "Expected: package/ or target/ directory"
  exit 1
fi

# Check if gql_submit.sh exists
if [[ ! -f "bin/gql_submit.sh" ]]; then
  log_error "bin/gql_submit.sh not found"
  log_info "This script is required to run GQL tests"
  exit 1
fi

log_success "bin/gql_submit.sh found"

# Check if test SQL file exists
GQL_TEST_FILE="geaflow/geaflow-examples/gql/loop_detection_file_demo.sql"
if [[ ! -f "$GQL_TEST_FILE" ]]; then
  log_error "Test file not found: $GQL_TEST_FILE"
  log_info "This file is required for the GQL demo test"
  exit 1
fi

log_success "Test file found: $GQL_TEST_FILE"

# Make gql_submit.sh executable
chmod +x bin/gql_submit.sh

echo ""
log_info "========================================="
log_info "Step 2: Running GQL Loop Detection Demo"
log_info "========================================="
log_info "Command: ./bin/gql_submit.sh --gql $GQL_TEST_FILE"
echo ""

# Run the GQL test
START_TIME=$(date +%s)

# Capture output
set +e
./bin/gql_submit.sh --gql "$GQL_TEST_FILE" 2>&1 | tee /tmp/geaflow-gql-test.log
TEST_EXIT_CODE=$?
set -e

END_TIME=$(date +%s)
TEST_DURATION=$((END_TIME - START_TIME))

echo ""
log_info "Test exit code: $TEST_EXIT_CODE"
log_info "Test duration: ${TEST_DURATION} seconds"

echo ""
log_info "========================================="
log_info "Step 3: Analyzing Test Results"
log_info "========================================="

# Check for common success/failure indicators in output
if grep -qi "error" /tmp/geaflow-gql-test.log && ! grep -qi "0 error" /tmp/geaflow-gql-test.log; then
  log_warn "Output contains error messages"
fi

if grep -qi "exception" /tmp/geaflow-gql-test.log; then
  log_warn "Output contains exceptions"
fi

if grep -qi "success" /tmp/geaflow-gql-test.log; then
  log_info "Output indicates success"
fi

if grep -qi "completed" /tmp/geaflow-gql-test.log || grep -qi "finished" /tmp/geaflow-gql-test.log; then
  log_info "Test appears to have completed"
fi

# Check for output files or results
if [[ -d "output" ]]; then
  log_info "Output directory created:"
  ls -lh output/ | head -10 | sed 's/^/  /'
fi

echo ""
log_info "========================================="
log_info "Test Summary"
log_info "========================================="

# Create test summary
TEST_SUMMARY="$EXTRACTED_DIR/test-summary.txt"
cat > "$TEST_SUMMARY" << EOF
GeaFlow GQL Test Summary
========================
Component: $COMPONENT_NAME
Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Duration: ${TEST_DURATION} seconds

Test Command:
-------------
./bin/gql_submit.sh --gql $GQL_TEST_FILE

Exit Code: $TEST_EXIT_CODE

Test Description:
-----------------
Loop Detection File Demo - Tests GeaFlow's graph query capabilities
using a loop detection algorithm on file-based data.

Test Log:
---------
Full log available at: /tmp/geaflow-gql-test.log

EOF

# Add result interpretation
if [[ $TEST_EXIT_CODE -eq 0 ]]; then
  echo "Result: PASSED ✓" >> "$TEST_SUMMARY"
  echo "" >> "$TEST_SUMMARY"
  log_success "GQL Test PASSED"

  if [[ -d "output" ]]; then
    echo "Output files generated:" >> "$TEST_SUMMARY"
    ls -lh output/ >> "$TEST_SUMMARY"
  fi
else
  echo "Result: FAILED ✗" >> "$TEST_SUMMARY"
  echo "" >> "$TEST_SUMMARY"
  echo "Error Analysis:" >> "$TEST_SUMMARY"
  echo "--------------" >> "$TEST_SUMMARY"

  # Extract key error lines
  if grep -i "error" /tmp/geaflow-gql-test.log | grep -v "0 error" > /dev/null; then
    echo "Errors found:" >> "$TEST_SUMMARY"
    grep -i "error" /tmp/geaflow-gql-test.log | grep -v "0 error" | head -5 >> "$TEST_SUMMARY"
  fi

  if grep -i "exception" /tmp/geaflow-gql-test.log > /dev/null; then
    echo "" >> "$TEST_SUMMARY"
    echo "Exceptions found:" >> "$TEST_SUMMARY"
    grep -i "exception" /tmp/geaflow-gql-test.log | head -5 >> "$TEST_SUMMARY"
  fi

  log_error "GQL Test FAILED"
  log_info "Check test log for details: /tmp/geaflow-gql-test.log"
fi

log_info ""
log_info "Test summary: $TEST_SUMMARY"
log_info "Test log: /tmp/geaflow-gql-test.log"
log_info "========================================="

# Show last 20 lines of output for quick review
echo ""
log_info "Last 20 lines of test output:"
echo "----------------------------------------"
tail -20 /tmp/geaflow-gql-test.log
echo "----------------------------------------"

exit $TEST_EXIT_CODE
