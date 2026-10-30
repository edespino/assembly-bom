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

# Extracted trees are top-level directories. Names are not required to end in -src.
mapfile -t SOURCE_DIRS < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)

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
echo "[apache-rat] Trees without pom.xml are scanned by a generated RAT pom."
echo "[apache-rat] A missing report, or a report that scanned zero files, fails."
echo ""

declare -A RAT_REPORT_FOR=()

xml_escape() {
  local s=$1
  s=${s//&/&amp;}
  s=${s//</&lt;}
  s=${s//>/&gt;}
  printf '%s' "$s"
}

maven_log_for() {
  local dir=$1
  printf '%s\n' "${PARTS_DIR}/review-output/${COMPONENT_NAME}/rat-logs/$(basename "$dir").log"
}

files_scanned() {
  local report=$1
  local line notes=0 binaries=0 archives=0 standards=0 sum markers
  while IFS= read -r line; do
    case "$line" in
      "Notes:"*) notes=${line#Notes:}; notes=${notes//[[:space:]]/}; notes=${notes%%[^0-9]*} ;;
      "Binaries:"*) binaries=${line#Binaries:}; binaries=${binaries//[[:space:]]/}; binaries=${binaries%%[^0-9]*} ;;
      "Archives:"*) archives=${line#Archives:}; archives=${archives//[[:space:]]/}; archives=${archives%%[^0-9]*} ;;
      "Standards:"*) standards=${line#Standards:}; standards=${standards//[[:space:]]/}; standards=${standards%%[^0-9]*} ;;
    esac
  done < "$report"
  sum=$(( ${notes:-0} + ${binaries:-0} + ${archives:-0} + ${standards:-0} ))
  if [[ "$sum" -gt 0 ]]; then
    printf '%s\n' "$sum"
    return
  fi
  markers=$(grep -Ec '^[[:space:]]*(!?+|[A-Z]+)[[:space:]]+/' "$report" || true)
  printf '%s\n' "${markers:-0}"
}

resolve_b_path() {
  local dir=$1 rel=$2
  if [[ "$rel" == /* ]]; then
    printf '%s\n' "$rel"
  else
    printf '%s\n' "$dir/$rel"
  fi
}

# Return 0 when the RAT B entry is a compiled artifact.
# Suffix covers versioned shared libraries. file(1) covers extensionless
# ELF, Mach-O, and PE. If file(1) is missing, a non-allowlisted name fails.
is_compiled_binary() {
  local path=$1
  local base desc
  base=$(basename "$path")
  base=$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')
  case "$base" in
    *.so|*.so.[0-9]*|*.dylib|*.dylib.[0-9]*|*.dll|*.class|*.jar|*.o|*.a|*.exe|*.pyc|*.whl|*.node)
      return 0
      ;;
  esac
  if [[ ! -e "$path" ]] || ! command -v file >/dev/null 2>&1; then
    case "$base" in
      *.png|*.jpg|*.jpeg|*.gif|*.ico|*.svg|*.webp|*.bmp|*.tif|*.tiff|*.woff|*.woff2|*.ttf|*.eot|*.otf|*.pdf|*.mp3|*.mp4|*.wav|*.ogg|*.webm|*.avif|*.icns|*.gz|*.zip|*.tar|*.tgz|*.bz2|*.xz|*.7z)
        return 1
        ;;
    esac
    return 0
  fi
  desc=$(file -b -- "$path" 2>/dev/null || true)
  desc=$(printf '%s' "$desc" | tr '[:upper:]' '[:lower:]')
  case "$desc" in
    *elf*|*mach-o*|*pe32*|*ms-dos*|*java?class*|*byte-compiled*|*shared?object*|*ar?archive*)
      return 0
      ;;
  esac
  return 1
}

all_reports() {
  local dir=$1
  if [[ -n "${RAT_REPORT_FOR[$dir]:-}" && -f "${RAT_REPORT_FOR[$dir]}" ]]; then
    printf '%s\n' "${RAT_REPORT_FOR[$dir]}"
    return
  fi
  find "$dir" -type f -name rat.txt -path '*/target/rat.txt' -print | sort
}

require_scanned() {
  local dir=$1
  local report total=0 count
  local -a reports=()
  while IFS= read -r report; do
    [[ -n "$report" ]] && reports+=("$report")
  done < <(all_reports "$dir")
  if [[ ${#reports[@]} -eq 0 ]]; then
    echo "[apache-rat] ❌ No RAT report for $(basename "$dir")"
    exit 1
  fi
  for report in "${reports[@]}"; do
    count=$(files_scanned "$report")
    total=$((total + count))
  done
  if [[ "$total" -eq 0 ]]; then
    echo "[apache-rat] ❌ RAT scanned zero files in $(basename "$dir")"
    exit 1
  fi
  echo "[apache-rat] ✓ RAT scanned $total file(s) in $(basename "$dir")"
}

run_rat_without_pom() {
  local extracted=$1
  local tree pom_dir report log basedir_xml report_xml out_root
  tree=$(basename "$extracted")
  out_root="${PARTS_DIR}/review-output/${COMPONENT_NAME}"
  pom_dir="${out_root}/rat-pom/${tree}"
  report="${out_root}/rat/${tree}/rat.txt"
  log=$(maven_log_for "$extracted")
  mkdir -p "$pom_dir" "$(dirname "$report")" "$(dirname "$log")"
  basedir_xml=$(xml_escape "$extracted")
  report_xml=$(xml_escape "$report")
  cat > "$pom_dir/pom.xml" <<EOF
<project>
  <modelVersion>4.0.0</modelVersion>
  <groupId>org.apache.review</groupId>
  <artifactId>rat-scan</artifactId>
  <version>1</version>
  <build>
    <plugins>
      <plugin>
        <groupId>org.apache.rat</groupId>
        <artifactId>apache-rat-plugin</artifactId>
        <version>0.16.1</version>
        <configuration>
          <basedir>${basedir_xml}</basedir>
          <reportFile>${report_xml}</reportFile>
        </configuration>
      </plugin>
    </plugins>
  </build>
</project>
EOF
  echo "[apache-rat] No pom.xml in ${tree}. Scanning with a generated RAT pom."
  echo "[apache-rat] Report: $report"
  set +e
  (
    IFS=$' \t\n'
    mvn -f "$pom_dir/pom.xml" org.apache.rat:apache-rat-plugin:0.16.1:check 2>&1 | tee "$log"
  )
  set -e
  echo "[apache-rat] Maven finished for ${tree}"
  RAT_REPORT_FOR["$extracted"]="$report"
}

# Process each source directory
for EXTRACTED_DIR in "${SOURCE_DIRS[@]}"; do
  echo "[apache-rat] ----------------------------------------"
  echo "[apache-rat] Processing: ${EXTRACTED_DIR#$COMPONENT_DIR/}"
  echo "[apache-rat] ----------------------------------------"

  if [[ ! -f "$EXTRACTED_DIR/pom.xml" ]]; then
    if [[ -f "$EXTRACTED_DIR/go.mod" ]]; then
      echo "[apache-rat] ℹ Detected Go project"
    elif [[ -f "$EXTRACTED_DIR/pyproject.toml" ]]; then
      echo "[apache-rat] ℹ Detected Python project"
    elif [[ -f "$EXTRACTED_DIR/build.gradle" ]] || [[ -f "$EXTRACTED_DIR/build.gradle.kts" ]]; then
      echo "[apache-rat] ℹ Detected Gradle project"
    else
      echo "[apache-rat] ℹ No pom.xml"
    fi
    run_rat_without_pom "$EXTRACTED_DIR"
    require_scanned "$EXTRACTED_DIR"
    echo ""
    continue
  fi

  echo "[apache-rat] ✓ Found pom.xml - running Maven Apache RAT"
  pushd "$EXTRACTED_DIR" >/dev/null

  echo "[apache-rat] Cleaning old RAT reports..."
  find . -name "rat.txt" -path "*/target/rat.txt" -delete 2>/dev/null || true

  log=$(maven_log_for "$EXTRACTED_DIR")
  mkdir -p "$(dirname "$log")"

  # Allow RAT to exit non-zero. A missing header is a result, not a skipped scan.
  set +e
  (
    IFS=$' \t\n'
    # shellcheck disable=SC2086
    mvn $RAT_MAVEN_COMMAND 2>&1 | tee "$log"
  )
  RAT_EXIT_CODE=$?
  set -e
  popd >/dev/null

  echo ""
  echo "[apache-rat] Maven exit code: $RAT_EXIT_CODE"
  require_scanned "$EXTRACTED_DIR"
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
  MAVEN_OUTPUT=$(maven_log_for "$EXTRACTED_DIR")

  if [[ ! -f "$MAVEN_OUTPUT" ]]; then
    echo "[apache-rat] ❌ No Maven output for $(basename "$EXTRACTED_DIR")"
    exit 1
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

  # Extract file statistics from every RAT report for this tree.
  while IFS= read -r RAT_REPORT; do
    [[ -f "$RAT_REPORT" ]] || continue
    TOTAL_FILES=$((TOTAL_FILES + $(grep -E "^Notes: [0-9]+" "$RAT_REPORT" | awk '{print $2}' || echo "0")))
    TOTAL_BINARIES=$((TOTAL_BINARIES + $(grep -E "^Binaries: [0-9]+" "$RAT_REPORT" | awk '{print $2}' || echo "0")))
    TOTAL_ARCHIVES=$((TOTAL_ARCHIVES + $(grep -E "^Archives: [0-9]+" "$RAT_REPORT" | awk '{print $2}' || echo "0")))
    TOTAL_STANDARDS=$((TOTAL_STANDARDS + $(grep -E "^Standards: [0-9]+" "$RAT_REPORT" | awk '{print $2}' || echo "0")))
    TOTAL_JAVADOCS=$((TOTAL_JAVADOCS + $(grep -E "^JavaDoc Style: [0-9]+" "$RAT_REPORT" | awk '{print $3}' || echo "0")))
  done < <(all_reports "$EXTRACTED_DIR")
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
  ALL_RAT_FILES=$(all_reports "$EXTRACTED_DIR" || true)

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
  while IFS= read -r report; do
    [[ -n "$report" ]] || continue
    echo "[apache-rat]   - $(basename "$dir"): $report"
  done < <(all_reports "$dir")
done
echo "[apache-rat]"
echo "[apache-rat] Summary report: $SUMMARY_FILE"

if [[ -n "$UNKNOWN_FILES" ]]; then
  echo "[apache-rat] Unknown licenses: $UNKNOWN_LIST"
fi

echo "[apache-rat]"
echo "[apache-rat] ========================================="
echo "[apache-rat] Step 3: Categorize RAT binary files"
echo "[apache-rat] ========================================="
echo "[apache-rat] Files marked B were scanned and classified as binary."
echo "[apache-rat] They are not pom excludes. Images and data are expected."
echo "[apache-rat] Compiled artifacts fail this check."
echo ""

COMPILED_BINARIES=()
BINARY_TOTAL=0
declare -A BINARY_EXT_COUNTS=()

for dir in "${SOURCE_DIRS[@]}"; do
  tree_name=$(basename "$dir")
  tree_count=0
  mapfile -t tree_reports < <(all_reports "$dir")
  if [[ ${#tree_reports[@]} -eq 0 ]]; then
    echo "[apache-rat] ❌ No RAT report while classifying binaries in $tree_name"
    exit 1
  fi
  for RAT_REPORT in "${tree_reports[@]}"; do
    [[ -f "$RAT_REPORT" ]] || continue
    while IFS= read -r rel || [[ -n "$rel" ]]; do
      [[ -z "$rel" ]] && continue
      tree_count=$((tree_count + 1))
      BINARY_TOTAL=$((BINARY_TOTAL + 1))
      if [[ "$rel" == *.* ]]; then
        ext=".${rel##*.}"
        ext="${ext,,}"
      else
        ext="(noext)"
      fi
      BINARY_EXT_COUNTS["$ext"]=$(( ${BINARY_EXT_COUNTS[$ext]:-0} + 1 ))
      path=$(resolve_b_path "$dir" "$rel")
      if is_compiled_binary "$path"; then
        COMPILED_BINARIES+=("${tree_name}:${rel}")
      fi
    done < <(sed -n 's/^[[:space:]]*B[[:space:]]\{1,\}//p' "$RAT_REPORT")
  done
  echo "[apache-rat]   $tree_name: $tree_count binary"
done

echo "[apache-rat] Total RAT binaries: $BINARY_TOTAL"
if [[ ${#BINARY_EXT_COUNTS[@]} -gt 0 ]]; then
  echo "[apache-rat] By extension:"
  for ext in "${!BINARY_EXT_COUNTS[@]}"; do
    echo "[apache-rat]   ${BINARY_EXT_COUNTS[$ext]}  $ext"
  done | sort -k2 -nr
fi

echo "" >> "$SUMMARY_FILE"
echo "RAT binary files (marked B, not excludes): $BINARY_TOTAL" >> "$SUMMARY_FILE"
if [[ ${#COMPILED_BINARIES[@]} -eq 0 ]]; then
  echo "[apache-rat] ✅ PASS: No compiled binaries in the RAT binary list"
  echo "Compiled binaries: 0" >> "$SUMMARY_FILE"
else
  echo "[apache-rat] ❌ FAIL: Compiled binaries in the source tree"
  for item in "${COMPILED_BINARIES[@]}"; do
    echo "[apache-rat]   - $item"
    echo "  - $item" >> "$SUMMARY_FILE"
  done
  VALIDATION_PASSED=false
fi

echo ""
echo "[apache-rat] Archives (tar, zip, gzip, bzip2, xz, 7z)"
echo "[apache-rat] Identified, not failed. Test fixtures are expected."
ARCHIVE_TOTAL=0
declare -A ARCHIVE_EXT_COUNTS=()
for dir in "${SOURCE_DIRS[@]}"; do
  tree_name=$(basename "$dir")
  while IFS= read -r rel || [[ -n "$rel" ]]; do
    [[ -z "$rel" ]] && continue
    ARCHIVE_TOTAL=$((ARCHIVE_TOTAL + 1))
    base=$(basename "$rel")
    case "$base" in
      *.tar.gz|*.tar.bz2|*.tar.xz) ext=".${base#*.}" ;;
      *) ext=".${base##*.}" ;;
    esac
    ext="${ext,,}"
    ARCHIVE_EXT_COUNTS["$ext"]=$(( ${ARCHIVE_EXT_COUNTS[$ext]:-0} + 1 ))
    echo "[apache-rat]   $tree_name: $rel"
  done < <(find "$dir" -type f \
    \( -name '*.tar' -o -name '*.tar.gz' -o -name '*.tgz' -o -name '*.tar.bz2' \
       -o -name '*.tbz2' -o -name '*.tar.xz' -o -name '*.txz' -o -name '*.zip' \
       -o -name '*.gz' -o -name '*.bz2' -o -name '*.xz' -o -name '*.7z' \) \
    ! -path '*/target/*' -printf '%P\n')
done
echo "[apache-rat] Total archives: $ARCHIVE_TOTAL"
if [[ ${#ARCHIVE_EXT_COUNTS[@]} -gt 0 ]]; then
  echo "[apache-rat] Archives by extension:"
  for ext in "${!ARCHIVE_EXT_COUNTS[@]}"; do
    echo "[apache-rat]   ${ARCHIVE_EXT_COUNTS[$ext]}  $ext"
  done | sort -k2 -nr
fi
echo "Archives identified: $ARCHIVE_TOTAL" >> "$SUMMARY_FILE"

echo "[apache-rat] ========================================="

# Exit based on validation result
if [[ "$VALIDATION_PASSED" == "true" ]]; then
  exit 0
fi

echo "[apache-rat]"
if [[ ${NEEDS_ATTENTION:-0} -ne 0 ]]; then
  echo "[apache-rat] ❌ FAILED - Files missing license headers must be fixed or excluded"
  echo "[apache-rat] Unknown licenses: ${UNKNOWN_LIST:-$SUMMARY_FILE}"
fi
if [[ ${#COMPILED_BINARIES[@]} -gt 0 ]]; then
  echo "[apache-rat] ❌ FAILED - Compiled binaries do not belong in a source release"
fi
exit 1
