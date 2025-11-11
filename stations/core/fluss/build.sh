#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Get component name from environment (exported by assemble.sh)
COMPONENT_NAME="${NAME:?Missing NAME environment variable}"

# Environment variables from BOM
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$COMPONENT_NAME"
RELEASE_VERSION="${RELEASE_VERSION:-unknown}"

echo "[fluss-build] ========================================="
echo "[fluss-build] Apache Fluss Build"
echo "[fluss-build] ========================================="
echo "[fluss-build] Component: $COMPONENT_NAME"
echo "[fluss-build] Directory: $COMPONENT_DIR"
echo ""

# Find the extracted source directory
EXTRACTED_DIR=$(find "$COMPONENT_DIR" -maxdepth 1 -type d -name "*-src" -o -name "*-source" -o -name "${COMPONENT_NAME}-*" | grep -v "artifacts" | head -1)
if [[ -z "$EXTRACTED_DIR" ]]; then
  echo "[fluss-build] ❌ No extracted source directory found"
  echo "[fluss-build] Please run extract step first"
  exit 1
fi

echo "[fluss-build] Source: $EXTRACTED_DIR"
echo ""

# Change to extracted directory
cd "$EXTRACTED_DIR"

# Check if Maven wrapper exists
if [[ ! -f "./mvnw" ]]; then
  echo "[fluss-build] ❌ Maven wrapper (mvnw) not found"
  echo "[fluss-build] Expected: $EXTRACTED_DIR/mvnw"
  exit 1
fi

# Check Java version - Fluss 0.8 requires Java 11+
JAVA_VERSION=$(java -version 2>&1 | head -1 | cut -d'"' -f2)
echo "[fluss-build] Detected Java version: $JAVA_VERSION"
echo ""

# Validate Java 11 or higher is installed
if [[ "$JAVA_VERSION" == 1.8.* ]] || [[ "$JAVA_VERSION" == 9.* ]] || [[ "$JAVA_VERSION" == 10.* ]]; then
  echo "[fluss-build] ❌ ERROR: Fluss 0.8 requires Java 11 or higher"
  echo "[fluss-build]"
  echo "[fluss-build] Current Java version: $JAVA_VERSION"
  echo "[fluss-build]"
  echo "[fluss-build] Fluss 0.8+ only provides binaries built with Java 11."
  echo "[fluss-build] Java 8 is deprecated and will be removed in future versions."
  echo "[fluss-build]"
  echo "[fluss-build] Please install Java 11 or higher:"
  echo "[fluss-build]   - Java 11: OpenJDK 11"
  echo "[fluss-build]   - Java 17: OpenJDK 17 (LTS)"
  echo "[fluss-build]   - Java 21: OpenJDK 21 (LTS)"
  echo "[fluss-build]"
  echo "[fluss-build] To switch Java versions on this system:"
  echo "[fluss-build]   sudo alternatives --config java"
  echo "[fluss-build]"
  echo "[fluss-build] Reference: https://github.com/apache/fluss/blob/release-0.8/website/docs/maintenance/operations/upgrade-notes-0.8.md"
  exit 1
fi

# Extract major version
if [[ "$JAVA_VERSION" =~ ^1\.([0-9]+) ]]; then
  JAVA_MAJOR="${BASH_REMATCH[1]}"
else
  JAVA_MAJOR=$(echo "$JAVA_VERSION" | cut -d'.' -f1)
fi

echo "[fluss-build] ✓ Java $JAVA_MAJOR detected (meets minimum requirement of Java 11)"
echo "[fluss-build] Using default build profile for Java $JAVA_MAJOR"
JAVA_PROFILE=""

echo "[fluss-build] ========================================="
echo "[fluss-build] Step 1: Running Maven Build"
echo "[fluss-build] ========================================="
echo "[fluss-build] Command: ./mvnw clean install -DskipTests"
echo "[fluss-build] Note: Using 'install' to deploy artifacts to local Maven repo"
echo "[fluss-build]       This is required for the test step to resolve internal plugins"
echo ""

# Create build log
BUILD_LOG="/tmp/fluss-build.log"

# Run the build with install to make fluss-protogen-maven-plugin available
set +e
./mvnw clean install -DskipTests 2>&1 | tee "$BUILD_LOG"
BUILD_EXIT_CODE=$?
set -e

echo ""
echo "[fluss-build] Build exit code: $BUILD_EXIT_CODE"
echo ""

if [[ $BUILD_EXIT_CODE -ne 0 ]]; then
  echo "[fluss-build] ❌ Build FAILED"
  echo "[fluss-build] See log: $BUILD_LOG"
  exit 1
fi

echo "[fluss-build] ========================================="
echo "[fluss-build] Step 2: Checking Build Output"
echo "[fluss-build] ========================================="

# Find all JARs built (newer than pom.xml which was read at build start)
BUILD_JARS=$(find . -path "*/target/*.jar" -type f -newer pom.xml 2>/dev/null || true)
TOTAL_JARS=$(echo "$BUILD_JARS" | grep -c ".jar" || echo "0")

if [[ $TOTAL_JARS -gt 0 ]]; then
  echo "[fluss-build] ✓ Found $TOTAL_JARS JAR files built"
  echo "[fluss-build]"
  echo "[fluss-build] Key build artifacts:"

  # Show important artifacts (fluss-* JARs, excluding test JARs and originals)
  echo "$BUILD_JARS" | grep -E "fluss-[^/]+\.jar$" | grep -v "test" | grep -v "original-" | head -15 | while read -r jar; do
    if [[ -f "$jar" ]]; then
      SIZE=$(du -h "$jar" | cut -f1)
      REL_PATH=$(echo "$jar" | sed "s|$EXTRACTED_DIR/||")
      echo "[fluss-build]   - $REL_PATH ($SIZE)"
    fi
  done

  # Check for distribution package
  if [[ -d "fluss-dist/target/fluss-${RELEASE_VERSION}-incubating-bin" ]]; then
    echo "[fluss-build]"
    echo "[fluss-build] ✓ Distribution package built:"
    echo "[fluss-build]   fluss-dist/target/fluss-${RELEASE_VERSION}-incubating-bin/"
  fi
else
  echo "[fluss-build] ⚠ No JAR files found (or build artifacts same age as pom.xml)"
  echo "[fluss-build] This might indicate a build issue or cached build"
fi

echo "[fluss-build]"
echo "[fluss-build] Total JAR files: $TOTAL_JARS"

# Generate build summary
SUMMARY_FILE="$EXTRACTED_DIR/build-summary.txt"
cat > "$SUMMARY_FILE" << EOF
Apache Fluss Build Summary
==========================
Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Component: $COMPONENT_NAME
Source: $EXTRACTED_DIR

Build Configuration:
-------------------
Java Version: $JAVA_VERSION
Maven Profile: ${JAVA_PROFILE:-default}
Command: ./mvnw clean package -DskipTests $JAVA_PROFILE

Build Result:
-------------
Exit Code: $BUILD_EXIT_CODE
Status: SUCCESS

Build Artifacts:
---------------
Total JAR files: $TOTAL_JARS

Key Artifacts:
EOF

# Add fluss module JARs to summary
echo "$BUILD_JARS" | grep -E "fluss-[^/]+\.jar$" | grep -v "test" | grep -v "original-" | while read -r jar; do
  echo "  - $jar" >> "$SUMMARY_FILE"
done

echo "" >> "$SUMMARY_FILE"
echo "Log: $BUILD_LOG" >> "$SUMMARY_FILE"

echo ""
echo "[fluss-build] ========================================="
echo "[fluss-build] Build Summary"
echo "[fluss-build] ========================================="
echo "[fluss-build] ✓ Build completed successfully"
echo "[fluss-build]"
echo "[fluss-build] Build log: $BUILD_LOG"
echo "[fluss-build] Summary: $SUMMARY_FILE"
echo "[fluss-build] ========================================="

exit 0
