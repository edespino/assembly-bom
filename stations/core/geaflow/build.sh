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
log_info "Building GeaFlow"
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

# Check if build.sh exists
if [[ ! -f "build.sh" ]]; then
  log_error "build.sh not found in $EXTRACTED_DIR"
  log_info "GeaFlow requires build.sh script in source root"
  exit 1
fi

log_info "========================================="
log_info "Running GeaFlow Build"
log_info "========================================="
log_info "Command: ./build.sh --module=geaflow --output=package"
echo ""

# Make build.sh executable
chmod +x build.sh

# Run the build
START_TIME=$(date +%s)

# Run build with output capture
set +e
./build.sh --module=geaflow --output=package 2>&1 | tee /tmp/geaflow-build.log
BUILD_EXIT_CODE=$?
set -e

END_TIME=$(date +%s)
BUILD_DURATION=$((END_TIME - START_TIME))
BUILD_DURATION_MIN=$((BUILD_DURATION / 60))
BUILD_DURATION_SEC=$((BUILD_DURATION % 60))

echo ""
log_info "Build exit code: $BUILD_EXIT_CODE"
log_info "Build duration: ${BUILD_DURATION_MIN}m ${BUILD_DURATION_SEC}s"

if [[ $BUILD_EXIT_CODE -ne 0 ]]; then
  log_error "Build FAILED"
  log_info "Check build log at: /tmp/geaflow-build.log"
  exit $BUILD_EXIT_CODE
fi

echo ""
log_info "========================================="
log_info "Analyzing Build Output"
log_info "========================================="

# Check for common output directories/files
if [[ -d "package" ]]; then
  log_success "Package directory created: package/"
  log_info "Contents:"
  ls -lh package/ | head -20 | sed 's/^/  /'
elif [[ -d "target" ]]; then
  log_success "Target directory exists: target/"
  log_info "Looking for built artifacts..."
  find target -name "*.tar.gz" -o -name "*.zip" | head -10 | sed 's/^/  /'
else
  log_warn "No standard output directory found (package/ or target/)"
fi

echo ""
log_info "========================================="
log_info "Build Summary"
log_info "========================================="

# Create build summary
BUILD_SUMMARY="$EXTRACTED_DIR/build-summary.txt"
cat > "$BUILD_SUMMARY" << EOF
GeaFlow Build Summary
=====================
Component: $COMPONENT_NAME
Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Duration: ${BUILD_DURATION_MIN}m ${BUILD_DURATION_SEC}s

Build Command:
--------------
./build.sh --module=geaflow --output=package

Exit Code: $BUILD_EXIT_CODE

Build Log:
----------
Full log available at: /tmp/geaflow-build.log

Output:
-------
EOF

if [[ -d "package" ]]; then
  echo "Package directory: $EXTRACTED_DIR/package/" >> "$BUILD_SUMMARY"
  echo "" >> "$BUILD_SUMMARY"
  echo "Package contents:" >> "$BUILD_SUMMARY"
  ls -lh package/ >> "$BUILD_SUMMARY"
elif [[ -d "target" ]]; then
  echo "Target directory: $EXTRACTED_DIR/target/" >> "$BUILD_SUMMARY"
  echo "" >> "$BUILD_SUMMARY"
  echo "Artifacts found:" >> "$BUILD_SUMMARY"
  find target -name "*.tar.gz" -o -name "*.zip" >> "$BUILD_SUMMARY"
fi

echo ""

if [[ $BUILD_EXIT_CODE -eq 0 ]]; then
  log_success "Build PASSED"
  log_info "Build artifacts ready for review"
else
  log_error "Build FAILED"
  log_info "Review build log for errors"
fi

log_info ""
log_info "Build summary: $BUILD_SUMMARY"
log_info "========================================="

exit $BUILD_EXIT_CODE
