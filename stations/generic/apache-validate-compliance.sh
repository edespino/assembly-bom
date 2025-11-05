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
  RELEASE_URL="${RELEASE_URL:-}"
  if [[ "$COMPONENT_NAME" == *"incubating"* ]] || \
     [[ "$EXTRACTED_DIR" == *"incubating"* ]] || \
     [[ "$RELEASE_URL" == *"/incubator/"* ]]; then
    INCUBATOR_PROJECT="true"
  else
    INCUBATOR_PROJECT="false"
  fi
fi

# Add DISCLAIMER to required files for incubator projects
# Note: Apache Incubator Policy allows DISCLAIMER or DISCLAIMER-WIP
if [[ "$INCUBATOR_PROJECT" == "true" ]]; then
  echo "[validate-apache-compliance] ⚠ Incubator project detected - additional requirements apply"
  echo "[validate-apache-compliance]   - DISCLAIMER or DISCLAIMER-WIP file required"
  echo "[validate-apache-compliance]   - Artifact names must contain 'incubating'"
  echo "[validate-apache-compliance]   - Directory names must contain 'incubating'"
  echo "[validate-apache-compliance]   - LICENSE and NOTICE with correct content"
  echo "[validate-apache-compliance]   Reference: https://incubator.apache.org/policy/incubation.html"
else
  OPTIONAL_FILES+=("DISCLAIMER")
fi

echo "[validate-apache-compliance] ========================================="
echo "[validate-apache-compliance] Step 1: Validating Naming Conventions"
echo "[validate-apache-compliance] ========================================="

# Check incubator naming requirements
if [[ "$INCUBATOR_PROJECT" == "true" ]]; then
  # Get the directory name (basename of EXTRACTED_DIR)
  DIR_NAME=$(basename "$EXTRACTED_DIR")

  # Check if directory name contains "incubating"
  if [[ "$DIR_NAME" == *"incubating"* ]]; then
    echo "[validate-apache-compliance] ✓ Directory name contains 'incubating': $DIR_NAME"
  else
    echo "[validate-apache-compliance] ❌ Directory name MUST contain 'incubating': $DIR_NAME"
    echo "[validate-apache-compliance]   Apache Incubator policy requires 'incubating' in artifact names"
    VALIDATION_PASSED=false
  fi

  # Check artifact naming by looking at discovered artifacts list
  ARTIFACTS_DIR="$PARTS_DIR/${COMPONENT_NAME}-artifacts"
  if [[ -f "$ARTIFACTS_DIR/.discovered-src-artifacts" ]]; then
    while IFS= read -r artifact; do
      if [[ "$artifact" == *"incubating"* ]]; then
        echo "[validate-apache-compliance] ✓ Source artifact contains 'incubating': $artifact"
      else
        echo "[validate-apache-compliance] ❌ Source artifact MUST contain 'incubating': $artifact"
        echo "[validate-apache-compliance]   Apache Incubator policy requires 'incubating' in artifact names"
        VALIDATION_PASSED=false
      fi
    done < "$ARTIFACTS_DIR/.discovered-src-artifacts"
  fi
fi

echo ""
echo "[validate-apache-compliance] ========================================="
echo "[validate-apache-compliance] Step 2: Checking Required Files"
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

# For incubator projects, check for DISCLAIMER or DISCLAIMER-WIP
if [[ "$INCUBATOR_PROJECT" == "true" ]]; then
  if [[ -f "DISCLAIMER" ]] || [[ -f "DISCLAIMER-WIP" ]]; then
    if [[ -f "DISCLAIMER" ]]; then
      FILE_SIZE=$(stat -f%z "DISCLAIMER" 2>/dev/null || stat -c%s "DISCLAIMER" 2>/dev/null)
      echo "[validate-apache-compliance] ✓ DISCLAIMER exists (${FILE_SIZE} bytes)"
    else
      FILE_SIZE=$(stat -f%z "DISCLAIMER-WIP" 2>/dev/null || stat -c%s "DISCLAIMER-WIP" 2>/dev/null)
      echo "[validate-apache-compliance] ✓ DISCLAIMER-WIP exists (${FILE_SIZE} bytes)"
    fi
  else
    echo "[validate-apache-compliance] ❌ DISCLAIMER or DISCLAIMER-WIP is MISSING (required for incubator)"
    VALIDATION_PASSED=false
  fi
fi

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
echo "[validate-apache-compliance] Step 3: Validating LICENSE Content"
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
echo "[validate-apache-compliance] Step 4: Validating NOTICE Content"
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

  # Temporarily disable pipefail to avoid SIGPIPE issues with grep -q
  set +o pipefail
  if grep -i "Copyright" NOTICE | grep -q "$CURRENT_YEAR"; then
    set -o pipefail
    echo "[validate-apache-compliance] ✓ NOTICE copyright includes current year ($CURRENT_YEAR)"
  else
    set -o pipefail
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
echo "[validate-apache-compliance] Step 5: Validating DISCLAIMER Content"
echo "[validate-apache-compliance] ========================================="

# Check for DISCLAIMER or DISCLAIMER-WIP
DISCLAIMER_FILE=""
if [[ -f "DISCLAIMER" ]]; then
  DISCLAIMER_FILE="DISCLAIMER"
elif [[ -f "DISCLAIMER-WIP" ]]; then
  DISCLAIMER_FILE="DISCLAIMER-WIP"
fi

if [[ -n "$DISCLAIMER_FILE" ]]; then
  # Check for incubation mention
  if grep -qi "incubat" "$DISCLAIMER_FILE"; then
    echo "[validate-apache-compliance] ✓ $DISCLAIMER_FILE contains incubation status"
  else
    echo "[validate-apache-compliance] ⚠ $DISCLAIMER_FILE does not mention incubation"
    if [[ "$INCUBATOR_PROJECT" == "true" ]]; then
      VALIDATION_PASSED=false
    fi
  fi

  # Show first 10 lines
  echo "[validate-apache-compliance]"
  echo "[validate-apache-compliance] $DISCLAIMER_FILE preview:"
  head -10 "$DISCLAIMER_FILE" | sed 's/^/[validate-apache-compliance]   /'

  DISCLAIMER_LINES=$(wc -l < "$DISCLAIMER_FILE")
  if [[ $DISCLAIMER_LINES -gt 10 ]]; then
    echo "[validate-apache-compliance]   ... ($DISCLAIMER_LINES total lines)"
  fi
else
  if [[ "$INCUBATOR_PROJECT" == "true" ]]; then
    echo "[validate-apache-compliance] ❌ DISCLAIMER or DISCLAIMER-WIP not found (required for incubator)"
    echo "[validate-apache-compliance]   Reference: https://incubator.apache.org/policy/incubation.html"
  else
    echo "[validate-apache-compliance] ℹ DISCLAIMER file not present (not required)"
  fi
fi

echo ""
echo "[validate-apache-compliance] ========================================="
echo "[validate-apache-compliance] Step 6: Validating KEYS File Location"
echo "[validate-apache-compliance] ========================================="

# Check KEYS_URL for incubator projects
if [[ "$INCUBATOR_PROJECT" == "true" ]]; then
  KEYS_URL="${KEYS_URL:-}"

  if [[ -z "$KEYS_URL" ]]; then
    echo "[validate-apache-compliance] ⚠ KEYS_URL not set (required for signature verification)"
  else
    echo "[validate-apache-compliance] KEYS_URL: $KEYS_URL"

    # Check if KEYS_URL points to dev tree instead of release tree
    if [[ "$KEYS_URL" == *"/dist/dev/incubator/"* ]]; then
      echo "[validate-apache-compliance] ❌ KEYS_URL points to dev tree instead of release tree"
      echo "[validate-apache-compliance]"
      echo "[validate-apache-compliance]   Current (INCORRECT):"
      echo "[validate-apache-compliance]     $KEYS_URL"
      echo "[validate-apache-compliance]"
      echo "[validate-apache-compliance]   Should be one of:"
      echo "[validate-apache-compliance]     https://downloads.apache.org/incubator/$COMPONENT_NAME/KEYS (preferred)"
      echo "[validate-apache-compliance]     https://dist.apache.org/repos/dist/release/incubator/$COMPONENT_NAME/KEYS"
      echo "[validate-apache-compliance]"
      echo "[validate-apache-compliance]   Why this matters:"
      echo "[validate-apache-compliance]   - KEYS files should be maintained in the release tree, not dev tree"
      echo "[validate-apache-compliance]   - Having KEYS in both locations causes sync issues"
      echo "[validate-apache-compliance]   - Keys used for signing must never be removed (needed for archived releases)"
      echo "[validate-apache-compliance]   - Once release is approved, KEYS should be moved from dev to release tree"
      echo "[validate-apache-compliance]"
      echo "[validate-apache-compliance]   Reference: Apache release management best practices"
      VALIDATION_PASSED=false
    elif [[ "$KEYS_URL" == *"/dist/release/incubator/"* ]] || [[ "$KEYS_URL" == *"downloads.apache.org/incubator/"* ]]; then
      echo "[validate-apache-compliance] ✓ KEYS_URL correctly points to release tree"

      # Suggest preferred format if using dist.apache.org
      if [[ "$KEYS_URL" == *"/dist/release/incubator/"* ]]; then
        echo "[validate-apache-compliance]"
        echo "[validate-apache-compliance]   Note: Current URL works, but preferred format is:"
        echo "[validate-apache-compliance]     https://downloads.apache.org/incubator/$COMPONENT_NAME/KEYS"
      fi
    else
      echo "[validate-apache-compliance] ⚠ KEYS_URL format not recognized"
      echo "[validate-apache-compliance]   Expected format for incubator projects:"
      echo "[validate-apache-compliance]     https://downloads.apache.org/incubator/<project>/KEYS (preferred)"
      echo "[validate-apache-compliance]     https://dist.apache.org/repos/dist/release/incubator/<project>/KEYS"
    fi
  fi
else
  echo "[validate-apache-compliance] ℹ KEYS file location check only applies to incubator projects"
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
