#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Get component name from environment (exported by assemble.sh)
COMPONENT_NAME="${NAME:?Missing NAME environment variable}"

# Environment variables from BOM
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$COMPONENT_NAME"

# Optional: Set to "true" for incubator projects (defaults to auto-detect)
INCUBATOR_PROJECT="${INCUBATOR_PROJECT:-auto}"

echo "[validate-build-artifacts] ========================================="
echo "[validate-build-artifacts] Apache Build Artifacts Validation"
echo "[validate-build-artifacts] ========================================="
echo "[validate-build-artifacts] Component: $COMPONENT_NAME"
echo "[validate-build-artifacts] Directory: $COMPONENT_DIR"
echo ""

# Find the extracted source directory (exclude the component directory itself)
EXTRACTED_DIR=$(find "$COMPONENT_DIR" -maxdepth 1 -type d -not -path "$COMPONENT_DIR" | head -1)
if [[ -z "$EXTRACTED_DIR" ]]; then
  echo "[validate-build-artifacts] ❌ No extracted source directory found"
  echo "[validate-build-artifacts] Please run extract step first"
  exit 1
fi

echo "[validate-build-artifacts] Source: $EXTRACTED_DIR"
echo ""

# Change to extracted directory
cd "$EXTRACTED_DIR"

# Auto-detect incubator project
if [[ "$INCUBATOR_PROJECT" == "auto" ]]; then
  RELEASE_URL="${RELEASE_URL:-}"
  if [[ "$COMPONENT_NAME" == *"incubating"* ]] || \
     [[ "$EXTRACTED_DIR" == *"incubating"* ]] || \
     [[ "$RELEASE_URL" == *"/incubator/"* ]]; then
    INCUBATOR_PROJECT="true"
  else
    INCUBATOR_PROJECT="false"
  fi
fi

echo "[validate-build-artifacts] ========================================="
echo "[validate-build-artifacts] Incubator Project Detection"
echo "[validate-build-artifacts] ========================================="

if [[ "$INCUBATOR_PROJECT" == "true" ]]; then
  echo "[validate-build-artifacts] ⚠ Incubator project detected"
  echo "[validate-build-artifacts]   All built JAR files MUST contain 'incubating' in filename"
  echo "[validate-build-artifacts]   Reference: https://incubator.apache.org/policy/incubation.html"
else
  echo "[validate-build-artifacts] ℹ Not an incubator project"
  echo "[validate-build-artifacts]   JAR naming requirements do not apply"
  echo "[validate-build-artifacts] ========================================="
  echo "[validate-build-artifacts] ✓ Validation SKIPPED (not required)"
  exit 0
fi

echo ""
echo "[validate-build-artifacts] ========================================="
echo "[validate-build-artifacts] Searching for Built JAR Files"
echo "[validate-build-artifacts] ========================================="

# Find all JAR files (excluding source and javadoc JARs for primary check)
# We'll look in common build output directories
JAR_FILES=()
while IFS= read -r -d '' jar_file; do
  JAR_FILES+=("$jar_file")
done < <(find . -type f -name "*.jar" -print0 2>/dev/null || true)

if [[ ${#JAR_FILES[@]} -eq 0 ]]; then
  echo "[validate-build-artifacts] ⚠ No JAR files found in build output"
  echo "[validate-build-artifacts]   Build may not have produced any artifacts yet"
  echo "[validate-build-artifacts]   Make sure the build step has completed successfully"
  echo "[validate-build-artifacts] ========================================="
  exit 0
fi

echo "[validate-build-artifacts] Found ${#JAR_FILES[@]} JAR file(s)"
echo ""

# Validation results
VALIDATION_PASSED=true
VIOLATIONS=()

echo "[validate-build-artifacts] ========================================="
echo "[validate-build-artifacts] Validating JAR Filenames"
echo "[validate-build-artifacts] ========================================="

# Track categories
COMPLIANT_JARS=0
NONCOMPLIANT_JARS=0

for jar_file in "${JAR_FILES[@]}"; do
  # Get just the filename
  jar_basename=$(basename "$jar_file")

  # Check if filename contains "incubating"
  if [[ "$jar_basename" == *"incubating"* ]]; then
    echo "[validate-build-artifacts] ✓ $jar_basename"
    ((COMPLIANT_JARS++))
  else
    echo "[validate-build-artifacts] ❌ $jar_basename"
    echo "[validate-build-artifacts]    MISSING 'incubating' in filename"
    VIOLATIONS+=("$jar_file")
    VALIDATION_PASSED=false
    ((NONCOMPLIANT_JARS++))
  fi
done

echo ""
echo "[validate-build-artifacts] ========================================="
echo "[validate-build-artifacts] Validation Summary"
echo "[validate-build-artifacts] ========================================="
echo "[validate-build-artifacts] Total JAR files: ${#JAR_FILES[@]}"
echo "[validate-build-artifacts] Compliant: $COMPLIANT_JARS"
echo "[validate-build-artifacts] Non-compliant: $NONCOMPLIANT_JARS"
echo ""

if [[ "$VALIDATION_PASSED" == "true" ]]; then
  echo "[validate-build-artifacts] ✓ All JAR files comply with incubator naming requirements"
  echo "[validate-build-artifacts] ========================================="
  exit 0
else
  echo "[validate-build-artifacts] ❌ JAR filename validation FAILED"
  echo ""
  echo "[validate-build-artifacts] The following JAR files are missing 'incubating' in their names:"
  echo ""
  for violation in "${VIOLATIONS[@]}"; do
    jar_basename=$(basename "$violation")
    # Suggest a corrected name
    if [[ "$jar_basename" =~ ^(.+)-([0-9]+\.[0-9]+\.[0-9]+)(.*\.jar)$ ]]; then
      suggested_name="${BASH_REMATCH[1]}-${BASH_REMATCH[2]}-incubating${BASH_REMATCH[3]}"
      echo "[validate-build-artifacts]   ❌ $jar_basename"
      echo "[validate-build-artifacts]      Suggested: $suggested_name"
    else
      echo "[validate-build-artifacts]   ❌ $jar_basename"
    fi
  done
  echo ""
  echo "[validate-build-artifacts] Apache Incubator Policy Requirements:"
  echo "[validate-build-artifacts] - All release artifacts (including JARs) must include 'incubating'"
  echo "[validate-build-artifacts] - This applies to Maven coordinates and filenames"
  echo "[validate-build-artifacts] - Example: my-artifact-1.0.0-incubating.jar"
  echo "[validate-build-artifacts]"
  echo "[validate-build-artifacts] To fix this issue:"
  echo "[validate-build-artifacts] 1. Update the project's Maven POM files to use version like '0.7.0-incubating'"
  echo "[validate-build-artifacts] 2. Ensure all module POMs inherit the incubating version"
  echo "[validate-build-artifacts] 3. Rebuild the project"
  echo ""
  echo "[validate-build-artifacts] Reference: https://incubator.apache.org/policy/incubation.html"
  echo "[validate-build-artifacts] ========================================="
  exit 1
fi
