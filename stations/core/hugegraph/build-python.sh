#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Get component name from environment (exported by assemble.sh)
COMPONENT_NAME="${NAME:?Missing NAME environment variable}"

# Environment variables from BOM
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$COMPONENT_NAME"

echo "[hugegraph-python-build] ========================================="
echo "[hugegraph-python-build] Apache HugeGraph Python Build"
echo "[hugegraph-python-build] ========================================="
echo "[hugegraph-python-build] Component: $COMPONENT_NAME"
echo "[hugegraph-python-build] Directory: $COMPONENT_DIR"
echo ""

# Find all extracted source directories
mapfile -t SOURCE_DIRS < <(find "$COMPONENT_DIR" -maxdepth 1 -type d -name "*-src" | sort)

if [[ ${#SOURCE_DIRS[@]} -eq 0 ]]; then
  echo "[hugegraph-python-build] ❌ No extracted source directories found"
  echo "[hugegraph-python-build] Please run extract step first"
  exit 1
fi

echo "[hugegraph-python-build] Found ${#SOURCE_DIRS[@]} source director(ies):"
for dir in "${SOURCE_DIRS[@]}"; do
  echo "[hugegraph-python-build]   - $(basename "$dir")"
done
echo ""

# Track overall build status
OVERALL_BUILD_STATUS=0
BUILT_PROJECTS=0
SKIPPED_PROJECTS=0

# Process each source directory
for EXTRACTED_DIR in "${SOURCE_DIRS[@]}"; do
  echo ""
  echo "[hugegraph-python-build] ========================================"
  echo "[hugegraph-python-build] Building: $(basename "$EXTRACTED_DIR")"
  echo "[hugegraph-python-build] ========================================"
  echo "[hugegraph-python-build] Path: $EXTRACTED_DIR"
  echo ""

  # Change to extracted directory
  cd "$EXTRACTED_DIR"

  # Check if this is a Python project
  if [[ ! -f "pyproject.toml" ]]; then
    echo "[hugegraph-python-build] ℹ No pyproject.toml found - not a Python project"
    echo "[hugegraph-python-build] ⏭ Skipping"
    SKIPPED_PROJECTS=$((SKIPPED_PROJECTS + 1))
    continue
  fi

  echo "[hugegraph-python-build] ✓ Detected Python project (pyproject.toml)"
  echo ""

  # Check Python version
  PYTHON_VERSION=$(python3 --version 2>&1 || echo "not found")
  echo "[hugegraph-python-build] Python version: $PYTHON_VERSION"

  # Check if build module is available
  if ! python3 -c "import build" 2>/dev/null; then
    echo "[hugegraph-python-build] ℹ Installing 'build' module..."
    pip3 install --user build || {
      echo "[hugegraph-python-build] ❌ Failed to install 'build' module"
      OVERALL_BUILD_STATUS=1
      continue
    }
  fi

  # Create build log
  BUILD_LOG="/tmp/hugegraph-python-build-$(basename "$EXTRACTED_DIR").log"

  echo "[hugegraph-python-build]"
  echo "[hugegraph-python-build] ----------------------------------------"
  echo "[hugegraph-python-build] Python Build"
  echo "[hugegraph-python-build] ----------------------------------------"
  echo "[hugegraph-python-build] Command: python3 -m build"
  echo "[hugegraph-python-build] Log: $BUILD_LOG"
  echo ""

  # Clean previous build artifacts
  if [[ -d "dist" ]]; then
    echo "[hugegraph-python-build] Cleaning previous build artifacts..."
    rm -rf dist/
  fi

  # Run Python build
  set +e
  python3 -m build 2>&1 | tee "$BUILD_LOG"
  BUILD_EXIT_CODE=$?
  set -e

  echo ""
  echo "[hugegraph-python-build] Build exit code: $BUILD_EXIT_CODE"
  echo ""

  if [[ $BUILD_EXIT_CODE -ne 0 ]]; then
    echo "[hugegraph-python-build] ❌ Python build FAILED"
    echo "[hugegraph-python-build] See log: $BUILD_LOG"
    OVERALL_BUILD_STATUS=1
    continue
  fi

  # Count built artifacts
  if [[ -d "dist" ]]; then
    WHL_FILES=$(find dist -name "*.whl" 2>/dev/null || true)
    TAR_GZ_FILES=$(find dist -name "*.tar.gz" 2>/dev/null || true)
    WHL_COUNT=$(echo "$WHL_FILES" | grep -c ".whl" || echo "0")
    TAR_GZ_COUNT=$(echo "$TAR_GZ_FILES" | grep -c ".tar.gz" || echo "0")

    echo "[hugegraph-python-build] ✓ Python build completed"
    echo "[hugegraph-python-build] Wheel packages: $WHL_COUNT"
    echo "[hugegraph-python-build] Source distributions: $TAR_GZ_COUNT"

    if [[ $WHL_COUNT -gt 0 ]]; then
      echo "[hugegraph-python-build]"
      echo "[hugegraph-python-build] Wheel packages:"
      echo "$WHL_FILES" | while read -r whl; do
        if [[ -f "$whl" ]]; then
          SIZE=$(du -h "$whl" | cut -f1)
          echo "[hugegraph-python-build]   - $(basename "$whl") ($SIZE)"
        fi
      done
    fi

    if [[ $TAR_GZ_COUNT -gt 0 ]]; then
      echo "[hugegraph-python-build]"
      echo "[hugegraph-python-build] Source distributions:"
      echo "$TAR_GZ_FILES" | while read -r tar_gz; do
        if [[ -f "$tar_gz" ]]; then
          SIZE=$(du -h "$tar_gz" | cut -f1)
          echo "[hugegraph-python-build]   - $(basename "$tar_gz") ($SIZE)"
        fi
      done
    fi

    BUILT_PROJECTS=$((BUILT_PROJECTS + 1))
  else
    echo "[hugegraph-python-build] ⚠ No dist/ directory created"
  fi

done

# Summary
echo ""
echo "[hugegraph-python-build] ========================================="
echo "[hugegraph-python-build] Overall Build Summary"
echo "[hugegraph-python-build] ========================================="
echo "[hugegraph-python-build] Total source directories: ${#SOURCE_DIRS[@]}"
echo "[hugegraph-python-build] Built successfully: $BUILT_PROJECTS"
echo "[hugegraph-python-build] Skipped (non-Python): $SKIPPED_PROJECTS"
echo "[hugegraph-python-build] Failed: $((${#SOURCE_DIRS[@]} - BUILT_PROJECTS - SKIPPED_PROJECTS))"
echo "[hugegraph-python-build]"

if [[ $OVERALL_BUILD_STATUS -eq 0 ]]; then
  echo "[hugegraph-python-build] ✅ All Python builds completed successfully"
  echo "[hugegraph-python-build] ========================================="
else
  echo "[hugegraph-python-build] ❌ Some builds failed - check logs above"
  echo "[hugegraph-python-build] ========================================="
fi

exit $OVERALL_BUILD_STATUS
