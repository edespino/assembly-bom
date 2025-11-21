#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Get component name from environment (exported by assemble.sh)
COMPONENT_NAME="${NAME:?Missing NAME environment variable}"

# Environment variables from BOM
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$COMPONENT_NAME"
RELEASE_VERSION="${RELEASE_VERSION:-unknown}"

echo "[hugegraph-build] ========================================="
echo "[hugegraph-build] Apache HugeGraph Build"
echo "[hugegraph-build] ========================================="
echo "[hugegraph-build] Component: $COMPONENT_NAME"
echo "[hugegraph-build] Directory: $COMPONENT_DIR"
echo ""

# Find all extracted source directories
mapfile -t SOURCE_DIRS < <(find "$COMPONENT_DIR" -maxdepth 1 -type d -name "*-src" | sort)

if [[ ${#SOURCE_DIRS[@]} -eq 0 ]]; then
  echo "[hugegraph-build] ❌ No extracted source directories found"
  echo "[hugegraph-build] Please run extract step first"
  exit 1
fi

echo "[hugegraph-build] Found ${#SOURCE_DIRS[@]} source director(ies):"
for dir in "${SOURCE_DIRS[@]}"; do
  echo "[hugegraph-build]   - $(basename "$dir")"
done
echo ""

# Track overall build status
OVERALL_BUILD_STATUS=0
BUILT_PROJECTS=0
SKIPPED_PROJECTS=0

# Process each source directory
for EXTRACTED_DIR in "${SOURCE_DIRS[@]}"; do
  echo ""
  echo "[hugegraph-build] ========================================"
  echo "[hugegraph-build] Building: $(basename "$EXTRACTED_DIR")"
  echo "[hugegraph-build] ========================================"
  echo "[hugegraph-build] Path: $EXTRACTED_DIR"
  echo ""

  # Change to extracted directory
  cd "$EXTRACTED_DIR"

  # Check build system at root level
  HAS_ROOT_MAVEN=false
  HAS_SUBDIRS=false

  if [[ -f "pom.xml" ]]; then
    HAS_ROOT_MAVEN=true
    echo "[hugegraph-build] ✓ Detected Maven project at root (pom.xml)"
  fi

  if [[ -f "pyproject.toml" ]]; then
    echo "[hugegraph-build] ℹ Detected Python project (pyproject.toml)"
    echo "[hugegraph-build] ⏭ Skipping - use build-python.sh for Python builds"
    SKIPPED_PROJECTS=$((SKIPPED_PROJECTS + 1))
    continue
  fi

  # Check for Maven/Go subdirectories (e.g., computer/pom.xml, vermeer/go.mod)
  MAVEN_SUBDIRS=()
  GO_SUBDIRS=()

  for subdir in */; do
    if [[ -f "${subdir}pom.xml" ]]; then
      MAVEN_SUBDIRS+=("$subdir")
    fi
    if [[ -f "${subdir}go.mod" ]]; then
      GO_SUBDIRS+=("$subdir")
    fi
  done

  if [[ ${#MAVEN_SUBDIRS[@]} -gt 0 ]] || [[ ${#GO_SUBDIRS[@]} -gt 0 ]]; then
    HAS_SUBDIRS=true
    echo "[hugegraph-build] ✓ Detected subdirectory projects:"
    for subdir in "${MAVEN_SUBDIRS[@]}"; do
      echo "[hugegraph-build]   - Maven: $subdir"
    done
    for subdir in "${GO_SUBDIRS[@]}"; do
      echo "[hugegraph-build]   - Go: $subdir"
    done
  fi

  if [[ "$HAS_ROOT_MAVEN" == "false" ]] && [[ "$HAS_SUBDIRS" == "false" ]]; then
    echo "[hugegraph-build] ⚠ No recognized build system (Maven/Go)"
    echo "[hugegraph-build] ⏭ Skipping - cannot determine how to build"
    SKIPPED_PROJECTS=$((SKIPPED_PROJECTS + 1))
    continue
  fi

  # Set Java environment for Maven builds
  export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-11.0.25.0.9-7.el9.x86_64"
  export PATH="$JAVA_HOME/bin:$PATH"

  # Maven build at root level
  if [[ "$HAS_ROOT_MAVEN" == "true" ]]; then
    echo ""
    echo "[hugegraph-build] ----------------------------------------"
    echo "[hugegraph-build] Maven Build (Root)"
    echo "[hugegraph-build] ----------------------------------------"
    echo "[hugegraph-build] Using Java 11 (required for HugeGraph dependencies)"
    echo "[hugegraph-build] JAVA_HOME: $JAVA_HOME"

    # Use Maven wrapper if available, otherwise use system Maven
    if [[ -f "./mvnw" ]]; then
      MVN_CMD="./mvnw"
      echo "[hugegraph-build] Using Maven wrapper: ./mvnw"
    else
      MVN_CMD="mvn"
      echo "[hugegraph-build] Using system Maven: mvn"
    fi

    # Check if mvn is available
    if ! command -v mvn &> /dev/null && [[ ! -f "./mvnw" ]]; then
      echo "[hugegraph-build] ❌ Maven not found in PATH and no mvnw wrapper"
      echo "[hugegraph-build] Please install Maven or provide Maven wrapper"
      OVERALL_BUILD_STATUS=1
      continue
    fi

    # Show Maven/Java version
    echo "[hugegraph-build]"
    $MVN_CMD --version | head -3 | sed 's/^/[hugegraph-build] /'
    echo ""

    # Create build log
    BUILD_LOG="/tmp/hugegraph-build-$(basename "$EXTRACTED_DIR").log"

    echo "[hugegraph-build] Command: $MVN_CMD clean install -DskipTests"
    echo "[hugegraph-build] Log: $BUILD_LOG"
    echo ""

    # Run Maven build
    set +e
    $MVN_CMD clean install -DskipTests 2>&1 | tee "$BUILD_LOG"
    BUILD_EXIT_CODE=$?
    set -e

    echo ""
    echo "[hugegraph-build] Maven build exit code: $BUILD_EXIT_CODE"
    echo ""

    if [[ $BUILD_EXIT_CODE -ne 0 ]]; then
      echo "[hugegraph-build] ❌ Maven build FAILED"
      echo "[hugegraph-build] See log: $BUILD_LOG"
      OVERALL_BUILD_STATUS=1
      continue
    fi

    # Count built JARs
    BUILD_JARS=$(find . -path "*/target/*.jar" -type f 2>/dev/null | grep -v "original-" || true)
    TOTAL_JARS=$(echo "$BUILD_JARS" | grep -c ".jar" || echo "0")

    echo "[hugegraph-build] ✓ Maven build completed"
    echo "[hugegraph-build] Found $TOTAL_JARS JAR file(s)"

    if [[ $TOTAL_JARS -gt 0 ]]; then
      echo "[hugegraph-build]"
      echo "[hugegraph-build] Sample artifacts (first 10):"
      echo "$BUILD_JARS" | head -10 | while read -r jar; do
        if [[ -f "$jar" ]]; then
          SIZE=$(du -h "$jar" | cut -f1)
          REL_PATH=$(echo "$jar" | sed "s|$EXTRACTED_DIR/||")
          echo "[hugegraph-build]   - $REL_PATH ($SIZE)"
        fi
      done
    fi

    BUILT_PROJECTS=$((BUILT_PROJECTS + 1))

    # If root Maven build succeeded, skip subdirectory Maven builds
    # (they were already built by the root reactor)
    if [[ ${#MAVEN_SUBDIRS[@]} -gt 0 ]]; then
      echo ""
      echo "[hugegraph-build] ℹ Skipping Maven subdirectory builds (already built by root reactor)"
    fi
    MAVEN_SUBDIRS=()
  fi

  # Build Maven subdirectories (only if no root build)
  for maven_subdir in "${MAVEN_SUBDIRS[@]}"; do
    echo ""
    echo "[hugegraph-build] ----------------------------------------"
    echo "[hugegraph-build] Maven Build (${maven_subdir%/})"
    echo "[hugegraph-build] ----------------------------------------"

    cd "$EXTRACTED_DIR/$maven_subdir"

    # Use Maven wrapper if available, otherwise use system Maven
    if [[ -f "./mvnw" ]]; then
      MVN_CMD="./mvnw"
      echo "[hugegraph-build] Using Maven wrapper: ./mvnw"
    else
      MVN_CMD="mvn"
      echo "[hugegraph-build] Using system Maven: mvn"
    fi

    # Create build log
    BUILD_LOG="/tmp/hugegraph-build-$(basename "$EXTRACTED_DIR")-${maven_subdir%/}.log"

    echo "[hugegraph-build] Command: $MVN_CMD clean install -DskipTests"
    echo "[hugegraph-build] Log: $BUILD_LOG"
    echo ""

    # Run Maven build
    set +e
    $MVN_CMD clean install -DskipTests 2>&1 | tee "$BUILD_LOG"
    BUILD_EXIT_CODE=$?
    set -e

    echo ""
    echo "[hugegraph-build] Maven build exit code: $BUILD_EXIT_CODE"
    echo ""

    if [[ $BUILD_EXIT_CODE -ne 0 ]]; then
      echo "[hugegraph-build] ❌ Maven build FAILED"
      echo "[hugegraph-build] See log: $BUILD_LOG"
      OVERALL_BUILD_STATUS=1
      cd "$EXTRACTED_DIR"
      continue
    fi

    # Count built JARs
    BUILD_JARS=$(find . -path "*/target/*.jar" -type f 2>/dev/null | grep -v "original-" || true)
    TOTAL_JARS=$(echo "$BUILD_JARS" | grep -c ".jar" || echo "0")

    echo "[hugegraph-build] ✓ Maven build completed (${maven_subdir%/})"
    echo "[hugegraph-build] Found $TOTAL_JARS JAR file(s)"

    if [[ $TOTAL_JARS -gt 0 ]]; then
      echo "[hugegraph-build]"
      echo "[hugegraph-build] Sample artifacts (first 5):"
      echo "$BUILD_JARS" | head -5 | while read -r jar; do
        if [[ -f "$jar" ]]; then
          SIZE=$(du -h "$jar" | cut -f1)
          echo "[hugegraph-build]   - $(basename "$jar") ($SIZE)"
        fi
      done
    fi

    BUILT_PROJECTS=$((BUILT_PROJECTS + 1))
    cd "$EXTRACTED_DIR"
  done

  # Build Go subdirectories
  for go_subdir in "${GO_SUBDIRS[@]}"; do
    echo ""
    echo "[hugegraph-build] ----------------------------------------"
    echo "[hugegraph-build] Go Build (${go_subdir%/})"
    echo "[hugegraph-build] ----------------------------------------"

    cd "$EXTRACTED_DIR/$go_subdir"

    # Check if Go is available
    if ! command -v go &> /dev/null; then
      echo "[hugegraph-build] ❌ Go not found in PATH"
      echo "[hugegraph-build] Please install Go 1.23+ to build this module"
      OVERALL_BUILD_STATUS=1
      cd "$EXTRACTED_DIR"
      continue
    fi

    GO_VERSION=$(go version)
    echo "[hugegraph-build] $GO_VERSION"
    echo ""

    # Check for Makefile
    if [[ -f "Makefile" ]]; then
      echo "[hugegraph-build] Using Makefile for build"

      # Create build log
      BUILD_LOG="/tmp/hugegraph-build-$(basename "$EXTRACTED_DIR")-${go_subdir%/}.log"

      # Update dependencies if needed (sonic compatibility fix)
      if grep -q "github.com/bytedance/sonic" go.mod 2>/dev/null; then
        echo "[hugegraph-build] Checking sonic dependency for Go 1.25 compatibility..."
        CURRENT_SONIC=$(grep "github.com/bytedance/sonic" go.mod | grep -oP 'v\d+\.\d+\.\d+' | head -1)
        if [[ "$CURRENT_SONIC" < "v1.14.0" ]]; then
          echo "[hugegraph-build] Updating sonic to v1.14.2+ for Go 1.25 compatibility..."
          go get github.com/bytedance/sonic@latest
          go mod tidy
        fi
      fi

      echo "[hugegraph-build] Command: make all"
      echo "[hugegraph-build] Log: $BUILD_LOG"
      echo ""

      # Run make build
      set +e
      make all 2>&1 | tee "$BUILD_LOG"
      BUILD_EXIT_CODE=$?
      set -e

      echo ""
      echo "[hugegraph-build] Go build exit code: $BUILD_EXIT_CODE"
      echo ""

      if [[ $BUILD_EXIT_CODE -ne 0 ]]; then
        echo "[hugegraph-build] ❌ Go build FAILED"
        echo "[hugegraph-build] See log: $BUILD_LOG"
        OVERALL_BUILD_STATUS=1
        cd "$EXTRACTED_DIR"
        continue
      fi

      # Find built binaries
      BINARIES=$(find . -maxdepth 1 -type f -executable 2>/dev/null || true)
      if [[ -n "$BINARIES" ]]; then
        BINARY_COUNT=$(echo "$BINARIES" | wc -l)
      else
        BINARY_COUNT=0
      fi

      echo "[hugegraph-build] ✓ Go build completed (${go_subdir%/})"
      echo "[hugegraph-build] Found $BINARY_COUNT executable(s)"

      if [[ $BINARY_COUNT -gt 0 ]]; then
        echo "[hugegraph-build]"
        echo "[hugegraph-build] Binaries:"
        echo "$BINARIES" | while read -r binary; do
          if [[ -f "$binary" ]]; then
            SIZE=$(du -h "$binary" | cut -f1)
            echo "[hugegraph-build]   - $(basename "$binary") ($SIZE)"
          fi
        done
      fi

      BUILT_PROJECTS=$((BUILT_PROJECTS + 1))
    else
      echo "[hugegraph-build] ⚠ No Makefile found"
      echo "[hugegraph-build] ⏭ Skipping - Go build requires Makefile"
    fi

    cd "$EXTRACTED_DIR"
  done

done

# Summary
echo ""
echo "[hugegraph-build] ========================================="
echo "[hugegraph-build] Overall Build Summary"
echo "[hugegraph-build] ========================================="
echo "[hugegraph-build] Total source directories: ${#SOURCE_DIRS[@]}"
echo "[hugegraph-build] Projects built successfully: $BUILT_PROJECTS"
echo "[hugegraph-build] Projects skipped: $SKIPPED_PROJECTS"
echo "[hugegraph-build] Projects failed: $((${#SOURCE_DIRS[@]} - BUILT_PROJECTS - SKIPPED_PROJECTS))"
echo "[hugegraph-build]"
echo "[hugegraph-build] Build types completed:"
echo "[hugegraph-build]   • Maven (Java 11): Root + subdirectory projects"
echo "[hugegraph-build]   • Go (1.23+): Subdirectory projects with Makefile"
echo "[hugegraph-build]   • Python: Use build-python.sh separately"
echo "[hugegraph-build]"

if [[ $OVERALL_BUILD_STATUS -eq 0 ]]; then
  echo "[hugegraph-build] ✅ All builds completed successfully"
  echo "[hugegraph-build] ========================================="
else
  echo "[hugegraph-build] ❌ Some builds failed - check logs above"
  echo "[hugegraph-build] ========================================="
fi

exit $OVERALL_BUILD_STATUS
