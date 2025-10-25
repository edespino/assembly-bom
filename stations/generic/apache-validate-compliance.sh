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

echo "[validate-apache-compliance] ========================================="
echo "[validate-apache-compliance] Apache Compliance Validation"
echo "[validate-apache-compliance] ========================================="
echo "[validate-apache-compliance] Component: $COMPONENT_NAME"
echo "[validate-apache-compliance] Directory: $COMPONENT_DIR"
echo ""

# Find the extracted source directory (exclude the component directory itself)
EXTRACTED_DIR=$(find "$COMPONENT_DIR" -maxdepth 1 -type d -not -path "$COMPONENT_DIR" | head -1)
if [[ -z "$EXTRACTED_DIR" ]]; then
  echo "[validate-apache-compliance] ❌ No extracted source directory found"
  echo "[validate-apache-compliance] Please run extract step first"
  exit 1
fi

echo "[validate-apache-compliance] Source: $EXTRACTED_DIR"
echo ""

# Change to extracted directory
cd "$EXTRACTED_DIR"

# Validation results
VALIDATION_PASSED=true
REQUIRED_FILES=("LICENSE" "NOTICE")
OPTIONAL_FILES=()

# Auto-detect incubator project
if [[ "$INCUBATOR_PROJECT" == "auto" ]]; then
  if [[ "$COMPONENT_NAME" == *"incubating"* ]] || [[ "$EXTRACTED_DIR" == *"incubating"* ]]; then
    INCUBATOR_PROJECT="true"
  else
    INCUBATOR_PROJECT="false"
  fi
fi

# Add DISCLAIMER to required files for incubator projects
if [[ "$INCUBATOR_PROJECT" == "true" ]]; then
  REQUIRED_FILES+=("DISCLAIMER")
  echo "[validate-apache-compliance] Incubator project detected - DISCLAIMER required"
else
  OPTIONAL_FILES+=("DISCLAIMER")
fi

echo "[validate-apache-compliance] ========================================="
echo "[validate-apache-compliance] Step 1: Checking Required Files"
echo "[validate-apache-compliance] ========================================="

# Check for required files
for FILE in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$FILE" ]]; then
    FILE_SIZE=$(stat -f%z "$FILE" 2>/dev/null || stat -c%s "$FILE" 2>/dev/null)
    echo "[validate-apache-compliance] ✓ $FILE exists (${FILE_SIZE} bytes)"
  else
    echo "[validate-apache-compliance] ❌ $FILE is MISSING (required)"
    VALIDATION_PASSED=false
  fi
done

# Check for optional files
if [[ ${#OPTIONAL_FILES[@]} -gt 0 ]]; then
  echo ""
  echo "[validate-apache-compliance] Optional files:"
  for FILE in "${OPTIONAL_FILES[@]}"; do
    if [[ -f "$FILE" ]]; then
      FILE_SIZE=$(stat -f%z "$FILE" 2>/dev/null || stat -c%s "$FILE" 2>/dev/null)
      echo "[validate-apache-compliance] ℹ $FILE exists (${FILE_SIZE} bytes)"
    else
      echo "[validate-apache-compliance] ℹ $FILE not present (optional)"
    fi
  done
fi

echo ""
echo "[validate-apache-compliance] ========================================="
echo "[validate-apache-compliance] Step 2: Validating LICENSE Content"
echo "[validate-apache-compliance] ========================================="

if [[ -f "LICENSE" ]]; then
  # Check for Apache License 2.0
  if grep -q "Apache License" LICENSE && grep -q "Version 2.0" LICENSE; then
    echo "[validate-apache-compliance] ✓ LICENSE contains Apache License 2.0"
  else
    echo "[validate-apache-compliance] ⚠ LICENSE does not appear to be Apache License 2.0"
    VALIDATION_PASSED=false
  fi

  # Show first few lines
  echo "[validate-apache-compliance]"
  echo "[validate-apache-compliance] LICENSE preview:"
  head -5 LICENSE | sed 's/^/[validate-apache-compliance]   /'
else
  echo "[validate-apache-compliance] ⚠ LICENSE file not found - skipping content validation"
fi

echo ""
echo "[validate-apache-compliance] ========================================="
echo "[validate-apache-compliance] Step 3: Validating NOTICE Content"
echo "[validate-apache-compliance] ========================================="

if [[ -f "NOTICE" ]]; then
  # Check for Apache Software Foundation mention
  if grep -qi "Apache Software Foundation" NOTICE; then
    echo "[validate-apache-compliance] ✓ NOTICE contains Apache Software Foundation attribution"
  else
    echo "[validate-apache-compliance] ⚠ NOTICE does not mention Apache Software Foundation"
    VALIDATION_PASSED=false
  fi

  # Check for copyright notice
  if grep -qi "Copyright" NOTICE; then
    echo "[validate-apache-compliance] ✓ NOTICE contains copyright notice"
  else
    echo "[validate-apache-compliance] ⚠ NOTICE does not contain copyright notice"
  fi

  # Check for current year in copyright
  CURRENT_YEAR=$(date +%Y)
  if grep -i "Copyright" NOTICE | grep -q "$CURRENT_YEAR"; then
    echo "[validate-apache-compliance] ✓ NOTICE copyright includes current year ($CURRENT_YEAR)"
  else
    echo "[validate-apache-compliance] ⚠ NOTICE copyright does not include current year ($CURRENT_YEAR)"
    echo "[validate-apache-compliance]   Apache policy requires copyright year to be updated"
    VALIDATION_PASSED=false
  fi

  # Show full NOTICE (usually short)
  echo "[validate-apache-compliance]"
  echo "[validate-apache-compliance] NOTICE content:"
  cat NOTICE | sed 's/^/[validate-apache-compliance]   /'
else
  echo "[validate-apache-compliance] ⚠ NOTICE file not found - skipping content validation"
fi

echo ""
echo "[validate-apache-compliance] ========================================="
echo "[validate-apache-compliance] Step 4: Validating DISCLAIMER Content"
echo "[validate-apache-compliance] ========================================="

if [[ -f "DISCLAIMER" ]]; then
  # Check for incubation mention
  if grep -qi "incubat" DISCLAIMER; then
    echo "[validate-apache-compliance] ✓ DISCLAIMER contains incubation status"
  else
    echo "[validate-apache-compliance] ⚠ DISCLAIMER does not mention incubation"
    if [[ "$INCUBATOR_PROJECT" == "true" ]]; then
      VALIDATION_PASSED=false
    fi
  fi

  # Show first 10 lines
  echo "[validate-apache-compliance]"
  echo "[validate-apache-compliance] DISCLAIMER preview:"
  head -10 DISCLAIMER | sed 's/^/[validate-apache-compliance]   /'

  DISCLAIMER_LINES=$(wc -l < DISCLAIMER)
  if [[ $DISCLAIMER_LINES -gt 10 ]]; then
    echo "[validate-apache-compliance]   ... ($DISCLAIMER_LINES total lines)"
  fi
else
  if [[ "$INCUBATOR_PROJECT" == "true" ]]; then
    echo "[validate-apache-compliance] ⚠ DISCLAIMER file not found (required for incubator projects)"
  else
    echo "[validate-apache-compliance] ℹ DISCLAIMER file not present (not required)"
  fi
fi

echo ""
echo "[validate-apache-compliance] ========================================="
echo "[validate-apache-compliance] Validation Summary"
echo "[validate-apache-compliance] ========================================="

if [[ "$VALIDATION_PASSED" == "true" ]]; then
  echo "[validate-apache-compliance] ✓ All Apache compliance checks PASSED"
  echo "[validate-apache-compliance]"
  echo "[validate-apache-compliance] Required files present and valid:"
  for FILE in "${REQUIRED_FILES[@]}"; do
    echo "[validate-apache-compliance]   ✓ $FILE"
  done
  echo "[validate-apache-compliance] ========================================="
  exit 0
else
  echo "[validate-apache-compliance] ❌ Some Apache compliance checks FAILED"
  echo "[validate-apache-compliance] Please review the validation output above"
  echo "[validate-apache-compliance] ========================================="
  exit 1
fi
