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

# Find the extracted source directory (exclude the component directory itself)
EXTRACTED_DIR=$(find "$COMPONENT_DIR" -maxdepth 1 -type d -not -path "$COMPONENT_DIR" | head -1)
if [[ -z "$EXTRACTED_DIR" ]]; then
  echo "[apache-rat] ❌ No extracted source directory found"
  echo "[apache-rat] Please run extract step first"
  exit 1
fi

echo "[apache-rat] Source: $EXTRACTED_DIR"
echo ""

# Change to extracted directory
cd "$EXTRACTED_DIR"

# Check if Maven is available
if ! command -v mvn &> /dev/null; then
  echo "[apache-rat] ❌ Maven (mvn) not found in PATH"
  echo "[apache-rat] Please install Maven to run Apache RAT"
  exit 1
fi

echo "[apache-rat] ========================================="
echo "[apache-rat] Step 1: Running Apache RAT"
echo "[apache-rat] ========================================="
echo "[apache-rat] Command: mvn apache-rat:check"
echo ""

# Run Apache RAT (allow it to fail - we'll check the report)
set +e
mvn apache-rat:check 2>&1 | tee /tmp/rat-maven-output.log
RAT_EXIT_CODE=$?
set -e

echo ""
echo "[apache-rat] Maven exit code: $RAT_EXIT_CODE"

# Check if rat.txt was generated
if [[ ! -f "target/rat.txt" ]]; then
  echo "[apache-rat] ❌ RAT report not found at target/rat.txt"
  echo "[apache-rat] Maven may have failed to run RAT plugin"
  exit 1
fi

echo ""
echo "[apache-rat] ========================================="
echo "[apache-rat] Step 2: Analyzing RAT Report"
echo "[apache-rat] ========================================="
echo "[apache-rat] Report: $EXTRACTED_DIR/target/rat.txt"
echo ""

# Parse the RAT report and Maven output
RAT_REPORT="target/rat.txt"
MAVEN_OUTPUT="/tmp/rat-maven-output.log"

# Extract summary from Maven output (more reliable than rat.txt)
# Format: "[INFO] Rat check: Summary over all files. Unapproved: 194, unknown: 194, generated: 0, approved: 85 licenses."
RAT_SUMMARY=$(grep "Rat check: Summary" "$MAVEN_OUTPUT" || echo "")

if [[ -n "$RAT_SUMMARY" ]]; then
  UNAPPROVED=$(echo "$RAT_SUMMARY" | sed -n 's/.*Unapproved: \([0-9]*\).*/\1/p')
  UNKNOWN=$(echo "$RAT_SUMMARY" | sed -n 's/.*unknown: \([0-9]*\).*/\1/p')
  GENERATED=$(echo "$RAT_SUMMARY" | sed -n 's/.*generated: \([0-9]*\).*/\1/p')
  APACHE_LICENSED=$(echo "$RAT_SUMMARY" | sed -n 's/.*approved: \([0-9]*\).*/\1/p')
else
  # Fallback to parsing rat.txt
  APACHE_LICENSED=$(grep -E "^Apache Licensed: [0-9]+" "$RAT_REPORT" | awk '{print $3}' || echo "0")
  GENERATED=$(grep -E "^Generated Documents: [0-9]+" "$RAT_REPORT" | awk '{print $3}' || echo "0")
  UNKNOWN=$(grep -E "^Unknown Licenses: [0-9]+" "$RAT_REPORT" | awk '{print $3}' || echo "0")
  UNAPPROVED="$UNKNOWN"
fi

# Extract file statistics from rat.txt
TOTAL_FILES=$(grep -E "^Notes: [0-9]+" "$RAT_REPORT" | awk '{print $2}' || echo "0")
BINARIES=$(grep -E "^Binaries: [0-9]+" "$RAT_REPORT" | awk '{print $2}' || echo "0")
ARCHIVES=$(grep -E "^Archives: [0-9]+" "$RAT_REPORT" | awk '{print $2}' || echo "0")
STANDARDS=$(grep -E "^Standards: [0-9]+" "$RAT_REPORT" | awk '{print $2}' || echo "0")
JAVADOCS=$(grep -E "^JavaDoc Style: [0-9]+" "$RAT_REPORT" | awk '{print $3}' || echo "0")

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

# Files with unknown licenses are marked with '!?????' in RAT report
UNKNOWN_FILES=$(grep -E '^\s+!\?\?\?\?\?' "$RAT_REPORT" | sed 's/^[[:space:]]*!?????[[:space:]]*//' || true)

if [[ -n "$UNKNOWN_FILES" ]]; then
  echo "[apache-rat] The following files are missing Apache license headers:"
  echo "[apache-rat]"
  echo "$UNKNOWN_FILES" | while IFS= read -r file; do
    echo "[apache-rat]   - $file"
  done

  # Save to file for easy review
  UNKNOWN_LIST="$EXTRACTED_DIR/target/rat-unknown-licenses.txt"
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

SUMMARY_FILE="$EXTRACTED_DIR/target/rat-summary.txt"
cat > "$SUMMARY_FILE" << EOF
Apache RAT (Release Audit Tool) Summary
========================================
Component: $COMPONENT_NAME
Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")

File Statistics:
----------------
Total notes: $TOTAL_FILES
Binaries: $BINARIES
Archives: $ARCHIVES
Standards: $STANDARDS

License Status:
---------------
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
  echo "Files missing headers saved to: target/rat-unknown-licenses.txt" >> "$SUMMARY_FILE"
  echo ""
  echo "[apache-rat] ⚠ ATTENTION NEEDED - $NEEDS_ATTENTION file(s) missing license headers"
  VALIDATION_PASSED=false
fi

echo "[apache-rat]"
echo "[apache-rat] Full RAT report: $EXTRACTED_DIR/target/rat.txt"
echo "[apache-rat] Summary report: $SUMMARY_FILE"

if [[ -n "$UNKNOWN_FILES" ]]; then
  echo "[apache-rat] Unknown licenses: $UNKNOWN_LIST"
fi

echo "[apache-rat] ========================================="

# Exit based on validation result
if [[ "$VALIDATION_PASSED" == "true" ]]; then
  exit 0
else
  # Don't fail hard - RAT findings need manual review
  # Some files may legitimately not have headers
  echo "[apache-rat]"
  echo "[apache-rat] ℹ Manual review required for files without license headers"
  echo "[apache-rat] Some files may be legitimately excluded (e.g., test data, configs)"
  exit 0
fi
