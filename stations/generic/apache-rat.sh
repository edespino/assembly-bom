#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Get component name from environment (exported by assemble.sh)
COMPONENT_NAME="${NAME:?Missing NAME environment variable}"

# Environment variables from BOM
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$COMPONENT_NAME"

echo "[apache-rat] ========================================="
echo "[apache-rat] Apache Release Audit Tool (RAT)"
echo "[apache-rat] ========================================="
echo "[apache-rat] Component: $COMPONENT_NAME"
echo "[apache-rat] Directory: $COMPONENT_DIR"
echo ""

# Find all extracted source directories (ending in -src)
# For projects with multiple repositories, we'll have multiple source tarballs
mapfile -t SOURCE_DIRS < <(find "$COMPONENT_DIR" -maxdepth 1 -type d -name "*-src" | sort)

if [[ ${#SOURCE_DIRS[@]} -eq 0 ]]; then
  echo "[apache-rat] ❌ No extracted source directories found"
  echo "[apache-rat] Please run extract step first"
  exit 1
fi

echo "[apache-rat] Found ${#SOURCE_DIRS[@]} source director(ies):"
for dir in "${SOURCE_DIRS[@]}"; do
  echo "[apache-rat]   - ${dir#$COMPONENT_DIR/}"
done
echo ""

# Check if Maven is available
if ! command -v mvn &> /dev/null; then
  echo "[apache-rat] ❌ Maven (mvn) not found in PATH"
  echo "[apache-rat] Please install Maven to run Apache RAT"
  exit 1
fi

# Allow projects to customize the Maven command for RAT
# Some projects use 'mvn validate' with RAT bound to lifecycle
# Others use 'mvn apache-rat:check' for direct invocation
RAT_MAVEN_COMMAND="${RAT_MAVEN_COMMAND:-apache-rat:check}"

echo "[apache-rat] ========================================="
echo "[apache-rat] Step 1: Running Apache RAT on All Sources"
echo "[apache-rat] ========================================="
echo "[apache-rat] Command: mvn $RAT_MAVEN_COMMAND"
echo ""

# Process each source directory
for EXTRACTED_DIR in "${SOURCE_DIRS[@]}"; do
  echo "[apache-rat] ----------------------------------------"
  echo "[apache-rat] Processing: ${EXTRACTED_DIR#$COMPONENT_DIR/}"
  echo "[apache-rat] ----------------------------------------"

  # Check if this is a Maven project (has pom.xml)
  if [[ ! -f "$EXTRACTED_DIR/pom.xml" ]]; then
    echo "[apache-rat] ⚠ No pom.xml found - not a Maven project"

    # Detect build system for informational purposes
    if [[ -f "$EXTRACTED_DIR/pyproject.toml" ]]; then
      echo "[apache-rat] ℹ Detected Python project (pyproject.toml)"
    elif [[ -f "$EXTRACTED_DIR/build.gradle" ]] || [[ -f "$EXTRACTED_DIR/build.gradle.kts" ]]; then
      echo "[apache-rat] ℹ Detected Gradle project"
    elif [[ -f "$EXTRACTED_DIR/package.json" ]]; then
      echo "[apache-rat] ℹ Detected Node.js project"
    elif [[ -f "$EXTRACTED_DIR/go.mod" ]]; then
      echo "[apache-rat] ℹ Detected Go project"
    elif [[ -f "$EXTRACTED_DIR/Cargo.toml" ]]; then
      echo "[apache-rat] ℹ Detected Rust project"
    else
      echo "[apache-rat] ℹ Unknown build system"
    fi

    echo "[apache-rat] ⏭ Skipping - Apache RAT via Maven requires pom.xml"
    echo ""
    continue
  fi

  echo "[apache-rat] ✓ Found pom.xml - running Maven Apache RAT"

  # Change to extracted directory
  cd "$EXTRACTED_DIR"

  # Clean old rat.txt files to avoid stale data
  echo "[apache-rat] Cleaning old RAT reports..."
  find . -name "rat.txt" -path "*/target/rat.txt" -delete 2>/dev/null || true

  # Run Apache RAT (allow it to fail - we'll check the report)
  # Note: We don't quote $RAT_MAVEN_COMMAND to allow word splitting
  set +e
  (
    IFS=$' \t\n'
    # shellcheck disable=SC2086
    mvn $RAT_MAVEN_COMMAND 2>&1 | tee "/tmp/rat-maven-output-$(basename "$EXTRACTED_DIR").log"
  )
  RAT_EXIT_CODE=$?
  set -e

  echo ""
  echo "[apache-rat] Maven exit code: $RAT_EXIT_CODE"

  # Check if rat.txt was generated
  if [[ ! -f "target/rat.txt" ]]; then
    echo "[apache-rat] ⚠ RAT report not found at target/rat.txt for $(basename "$EXTRACTED_DIR")"
    echo "[apache-rat] Skipping this directory"
    echo ""
    continue
  fi

  echo "[apache-rat] ✓ RAT report generated: $EXTRACTED_DIR/target/rat.txt"
  echo ""
done

echo ""
echo "[apache-rat] ========================================="
echo "[apache-rat] Step 2: Analyzing All RAT Reports"
echo "[apache-rat] ========================================="
echo ""

# Aggregate statistics from all source directories
TOTAL_UNAPPROVED=0
TOTAL_UNKNOWN=0
TOTAL_GENERATED=0
TOTAL_APACHE_LICENSED=0
TOTAL_FILES=0
TOTAL_BINARIES=0
TOTAL_ARCHIVES=0
TOTAL_STANDARDS=0
TOTAL_JAVADOCS=0

# Process each source directory's RAT output
for EXTRACTED_DIR in "${SOURCE_DIRS[@]}"; do
  MAVEN_OUTPUT="/tmp/rat-maven-output-$(basename "$EXTRACTED_DIR").log"

  if [[ ! -f "$MAVEN_OUTPUT" ]]; then
    echo "[apache-rat] ⚠ Skipping $(basename "$EXTRACTED_DIR") - no Maven output found"
    continue
  fi

  echo "[apache-rat] Analyzing: $(basename "$EXTRACTED_DIR")"

  # Extract summary from Maven output
  RAT_SUMMARIES=$(grep "Rat check: Summary" "$MAVEN_OUTPUT" || echo "")

  if [[ -n "$RAT_SUMMARIES" ]]; then
    # Sum up all values across all modules within this source directory
    while IFS= read -r line; do
      TOTAL_UNAPPROVED=$((TOTAL_UNAPPROVED + $(echo "$line" | sed -n 's/.*Unapproved: \([0-9]*\).*/\1/p')))
      TOTAL_UNKNOWN=$((TOTAL_UNKNOWN + $(echo "$line" | sed -n 's/.*unknown: \([0-9]*\).*/\1/p')))
      TOTAL_GENERATED=$((TOTAL_GENERATED + $(echo "$line" | sed -n 's/.*generated: \([0-9]*\).*/\1/p')))
      TOTAL_APACHE_LICENSED=$((TOTAL_APACHE_LICENSED + $(echo "$line" | sed -n 's/.*approved: \([0-9]*\).*/\1/p')))
    done <<< "$RAT_SUMMARIES"
  fi

  # Extract file statistics from rat.txt
  RAT_REPORT="$EXTRACTED_DIR/target/rat.txt"
  if [[ -f "$RAT_REPORT" ]]; then
    TOTAL_FILES=$((TOTAL_FILES + $(grep -E "^Notes: [0-9]+" "$RAT_REPORT" | awk '{print $2}' || echo "0")))
    TOTAL_BINARIES=$((TOTAL_BINARIES + $(grep -E "^Binaries: [0-9]+" "$RAT_REPORT" | awk '{print $2}' || echo "0")))
    TOTAL_ARCHIVES=$((TOTAL_ARCHIVES + $(grep -E "^Archives: [0-9]+" "$RAT_REPORT" | awk '{print $2}' || echo "0")))
    TOTAL_STANDARDS=$((TOTAL_STANDARDS + $(grep -E "^Standards: [0-9]+" "$RAT_REPORT" | awk '{print $2}' || echo "0")))
    TOTAL_JAVADOCS=$((TOTAL_JAVADOCS + $(grep -E "^JavaDoc Style: [0-9]+" "$RAT_REPORT" | awk '{print $3}' || echo "0")))
  fi
done

# Use aggregated totals for reporting
UNAPPROVED=$TOTAL_UNAPPROVED
UNKNOWN=$TOTAL_UNKNOWN
GENERATED=$TOTAL_GENERATED
APACHE_LICENSED=$TOTAL_APACHE_LICENSED
TOTAL_FILES=$TOTAL_FILES
BINARIES=$TOTAL_BINARIES
ARCHIVES=$TOTAL_ARCHIVES
STANDARDS=$TOTAL_STANDARDS
JAVADOCS=$TOTAL_JAVADOCS

echo ""

echo "[apache-rat] Summary Statistics:"
echo "[apache-rat] ----------------------------------------"
echo "[apache-rat]   Total files analyzed: $TOTAL_FILES"
echo "[apache-rat]   Binaries: $BINARIES"
echo "[apache-rat]   Archives: $ARCHIVES"
echo "[apache-rat]   Standards: $STANDARDS"
echo "[apache-rat]"
echo "[apache-rat]   Apache Licensed (approved): $APACHE_LICENSED"
echo "[apache-rat]   Generated Documents: $GENERATED"
echo "[apache-rat]   JavaDoc Style: $JAVADOCS"
echo "[apache-rat]   Unknown Licenses (unapproved): $UNKNOWN"

# Calculate files needing attention
NEEDS_ATTENTION=$UNKNOWN

# Total files that need review
TOTAL_REVIEWED=$((APACHE_LICENSED + GENERATED + JAVADOCS + UNKNOWN))
echo "[apache-rat]"
echo "[apache-rat]   Total files reviewed: $TOTAL_REVIEWED"

if [[ $NEEDS_ATTENTION -eq 0 ]]; then
  echo "[apache-rat]"
  echo "[apache-rat] ✅ All files have appropriate license headers"
else
  echo "[apache-rat]"
  echo "[apache-rat] ⚠ Files needing attention: $NEEDS_ATTENTION"
fi

# Extract list of files with unknown licenses
echo ""
echo "[apache-rat] ========================================="
echo "[apache-rat] Step 3: Files with Unknown Licenses"
echo "[apache-rat] ========================================="

# Collect unknown files from all source directories
UNKNOWN_FILES=""
for EXTRACTED_DIR in "${SOURCE_DIRS[@]}"; do
  # Find all rat.txt files in this source directory's modules
  ALL_RAT_FILES=$(find "$EXTRACTED_DIR" -name "rat.txt" -path "*/target/rat.txt" 2>/dev/null || true)

  if [[ -n "$ALL_RAT_FILES" ]]; then
    while IFS= read -r rat_file; do
      # Files with unknown licenses are marked with '!?????' in RAT report
      MODULE_UNKNOWN=$(grep -E '^\s+!\?\?\?\?\?' "$rat_file" | sed 's/^[[:space:]]*!?????[[:space:]]*//' || true)
      if [[ -n "$MODULE_UNKNOWN" ]]; then
        # Prefix with source directory name for clarity
        SOURCE_NAME=$(basename "$EXTRACTED_DIR")
        while IFS= read -r file_path; do
          UNKNOWN_FILES="${UNKNOWN_FILES}[$SOURCE_NAME] $file_path"$'\n'
        done <<< "$MODULE_UNKNOWN"
      fi
    done <<< "$ALL_RAT_FILES"
  fi
done

# Remove trailing newline
UNKNOWN_FILES=$(echo -n "$UNKNOWN_FILES" | sed '/^$/d')

if [[ -n "$UNKNOWN_FILES" ]]; then
  echo "[apache-rat] The following files are missing Apache license headers:"
  echo "[apache-rat]"
  echo "$UNKNOWN_FILES" | while IFS= read -r file; do
    echo "[apache-rat]   - $file"
  done

  # Save to file for easy review in component directory
  UNKNOWN_LIST="$COMPONENT_DIR/rat-unknown-licenses.txt"
  echo "$UNKNOWN_FILES" > "$UNKNOWN_LIST"
  echo "[apache-rat]"
  echo "[apache-rat] Full list saved to: $UNKNOWN_LIST"
else
  echo "[apache-rat] ✅ No files with unknown licenses found"
fi

# Check for files that should be excluded
echo ""
echo "[apache-rat] ========================================="
echo "[apache-rat] Step 4: Exclusion Recommendations"
echo "[apache-rat] ========================================="

# Common patterns that should typically be excluded
echo "[apache-rat] Common file types that may need RAT exclusions:"
echo "[apache-rat] (Check if these should be excluded in pom.xml)"
echo "[apache-rat]"

# Check for common exclusion patterns
if echo "$UNKNOWN_FILES" | grep -qE '\.(md|txt|log|json|yaml|yml)$'; then
  echo "[apache-rat]   📝 Documentation/config files: .md, .txt, .json, .yaml"
fi

if echo "$UNKNOWN_FILES" | grep -qE '\.git/|\.github/'; then
  echo "[apache-rat]   🔧 Git metadata: .git/, .github/"
fi

if echo "$UNKNOWN_FILES" | grep -qE 'node_modules/|target/|build/|\.idea/'; then
  echo "[apache-rat]   📦 Build artifacts: node_modules/, target/, build/"
fi

if echo "$UNKNOWN_FILES" | grep -qE 'LICENSE|NOTICE|DISCLAIMER|README'; then
  echo "[apache-rat]   📄 License files: LICENSE, NOTICE, DISCLAIMER, README"
fi

if echo "$UNKNOWN_FILES" | grep -qE '\.(svg|png|jpg|jpeg|gif|ico)$'; then
  echo "[apache-rat]   🎨 Images: .svg, .png, .jpg"
fi

if echo "$UNKNOWN_FILES" | grep -qE '\.min\.(js|css)$'; then
  echo "[apache-rat]   📦 Minified files: .min.js, .min.css"
fi

# Create summary report
echo ""
echo "[apache-rat] ========================================="
echo "[apache-rat] Summary Report"
echo "[apache-rat] ========================================="

SUMMARY_FILE="$COMPONENT_DIR/rat-summary.txt"
cat > "$SUMMARY_FILE" << EOF
Apache RAT (Release Audit Tool) Summary
========================================
Component: $COMPONENT_NAME
Source Directories Analyzed: ${#SOURCE_DIRS[@]}
Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

Source Directories:
-------------------
EOF

for dir in "${SOURCE_DIRS[@]}"; do
  echo "  - $(basename "$dir")" >> "$SUMMARY_FILE"
done

cat >> "$SUMMARY_FILE" << EOF

File Statistics (Aggregated):
------------------------------
Total notes: $TOTAL_FILES
Binaries: $BINARIES
Archives: $ARCHIVES
Standards: $STANDARDS

License Status (Aggregated):
-----------------------------
Apache Licensed (approved): $APACHE_LICENSED
Generated Documents: $GENERATED
JavaDoc Style: $JAVADOCS
Unknown Licenses (unapproved): $UNKNOWN

Total files reviewed: $TOTAL_REVIEWED

Result:
-------
EOF

if [[ $NEEDS_ATTENTION -eq 0 ]]; then
  echo "✅ PASSED - All files have appropriate license headers" >> "$SUMMARY_FILE"
  echo ""
  echo "[apache-rat] ✅ PASSED - All files have appropriate license headers"
  VALIDATION_PASSED=true
else
  echo "⚠ ATTENTION NEEDED - $NEEDS_ATTENTION file(s) missing license headers" >> "$SUMMARY_FILE"
  echo ""
  echo "Files missing headers saved to: rat-unknown-licenses.txt" >> "$SUMMARY_FILE"
  echo ""
  echo "[apache-rat] ⚠ ATTENTION NEEDED - $NEEDS_ATTENTION file(s) missing license headers"
  VALIDATION_PASSED=false
fi

echo "[apache-rat]"
echo "[apache-rat] Individual RAT reports:"
for dir in "${SOURCE_DIRS[@]}"; do
  if [[ -f "$dir/target/rat.txt" ]]; then
    echo "[apache-rat]   - $(basename "$dir"): $dir/target/rat.txt"
  fi
done
echo "[apache-rat]"
echo "[apache-rat] Summary report: $SUMMARY_FILE"

if [[ -n "$UNKNOWN_FILES" ]]; then
  echo "[apache-rat] Unknown licenses: $UNKNOWN_LIST"
fi

echo "[apache-rat] ========================================="

# Exit based on validation result
if [[ "$VALIDATION_PASSED" == "true" ]]; then
  exit 0
else
  # Fail when files are missing license headers
  # For legitimate exclusions, configure them in pom.xml under <excludes>
  echo "[apache-rat]"
  echo "[apache-rat] ❌ FAILED - Files missing license headers must be fixed or excluded"
  echo "[apache-rat]"
  echo "[apache-rat] Options to resolve:"
  echo "[apache-rat]   1. Add Apache license headers to source files"
  echo "[apache-rat]   2. Configure RAT exclusions in pom.xml for legitimate cases:"
  echo "[apache-rat]      <plugin>"
  echo "[apache-rat]        <groupId>org.apache.rat</groupId>"
  echo "[apache-rat]        <artifactId>apache-rat-plugin</artifactId>"
  echo "[apache-rat]        <configuration>"
  echo "[apache-rat]          <excludes>"
  echo "[apache-rat]            <exclude>**/*.md</exclude>"
  echo "[apache-rat]            <exclude>**/LICENSE</exclude>"
  echo "[apache-rat]            <exclude>**/NOTICE</exclude>"
  echo "[apache-rat]            <!-- Add more patterns as needed -->"
  echo "[apache-rat]          </excludes>"
  echo "[apache-rat]        </configuration>"
  echo "[apache-rat]      </plugin>"
  exit 1
fi
