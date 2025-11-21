#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Get component name from environment (exported by assemble.sh)
COMPONENT_NAME="${NAME:?Missing NAME environment variable}"

# Environment variables from BOM
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
RELEASE_URL="${RELEASE_URL:-}"
RELEASE_VERSION="${RELEASE_VERSION:-}"
RELEASE_CANDIDATE="${RELEASE_CANDIDATE:-}"

echo "[validate-release-structure] ========================================="
echo "[validate-release-structure] Apache Release Structure Validation"
echo "[validate-release-structure] ========================================="
echo "[validate-release-structure] Component: $COMPONENT_NAME"
echo "[validate-release-structure] Release URL: ${RELEASE_URL:-not set}"
echo ""

# Validation results
VALIDATION_PASSED=true

echo "[validate-release-structure] ========================================="
echo "[validate-release-structure] Step 1: Validating RC Designation"
echo "[validate-release-structure] ========================================="

if [[ -n "$RELEASE_URL" ]]; then
  # Extract version directory from URL (last path component)
  VERSION_DIR=$(basename "$RELEASE_URL")
  echo "[validate-release-structure] Version directory: $VERSION_DIR"

  # Check if version directory contains RC designation (rc1, rc2, RC1, RC2, etc.)
  if [[ "$VERSION_DIR" =~ -[Rr][Cc][0-9]+ ]]; then
    echo "[validate-release-structure] ✅ PASS: Release URL contains RC designation"
    echo "[validate-release-structure]    URL: $RELEASE_URL"
  else
    echo "[validate-release-structure] ❌ FAIL: Release URL missing RC designation"
    echo "[validate-release-structure]"
    echo "[validate-release-structure]   Current URL:"
    echo "[validate-release-structure]     $RELEASE_URL"
    echo "[validate-release-structure]"
    echo "[validate-release-structure]   Version directory: $VERSION_DIR"
    echo "[validate-release-structure]"
    echo "[validate-release-structure]   Why this is a problem:"
    echo "[validate-release-structure]   - Release candidates MUST be identified as RC1, RC2, etc."
    echo "[validate-release-structure]   - Without RC designation, it appears to be a final release"
    echo "[validate-release-structure]   - Makes it impossible to distinguish between multiple iterations"
    echo "[validate-release-structure]   - Violates Apache release staging conventions"
    echo "[validate-release-structure]   - Users cannot identify which candidate is being voted on"
    echo "[validate-release-structure]"
    echo "[validate-release-structure]   Expected format:"
    echo "[validate-release-structure]     ${RELEASE_URL}-rc1"
    echo "[validate-release-structure]     ${RELEASE_URL}-rc2"
    echo "[validate-release-structure]"
    echo "[validate-release-structure]   Note: Even if this is the first/only candidate, it should be labeled RC1"
    echo "[validate-release-structure]"
    echo "[validate-release-structure]   Reference:"
    echo "[validate-release-structure]   - Apache Release Guide: https://www.apache.org/legal/release-policy.html"
    echo "[validate-release-structure]   - Release Management Best Practices"
    echo "[validate-release-structure]"
    VALIDATION_PASSED=false
  fi
else
  echo "[validate-release-structure] ⚠ WARNING: RELEASE_URL not set - cannot validate RC designation"
fi

echo ""
echo "[validate-release-structure] ========================================="
echo "[validate-release-structure] Step 2: Validating Source Tarball Count"
echo "[validate-release-structure] ========================================="

# Check for multiple source tarballs (Apache policy violation)
ARTIFACTS_DIR="$PARTS_DIR/${COMPONENT_NAME}-artifacts"
if [[ -f "$ARTIFACTS_DIR/.discovered-src-artifacts" ]]; then
  SRC_COUNT=$(wc -l < "$ARTIFACTS_DIR/.discovered-src-artifacts")
  
  echo "[validate-release-structure] Discovered source tarballs: $SRC_COUNT"
  echo ""

  if [[ $SRC_COUNT -eq 1 ]]; then
    SRC_ARTIFACT=$(cat "$ARTIFACTS_DIR/.discovered-src-artifacts")
    echo "[validate-release-structure] ✅ PASS: Single source tarball in release"
    echo "[validate-release-structure]    Artifact: $SRC_ARTIFACT"
  elif [[ $SRC_COUNT -gt 1 ]]; then
    echo "[validate-release-structure] ❌ FAIL: Multiple source tarballs in single release"
    echo "[validate-release-structure]"
    echo "[validate-release-structure]   Apache Release Policy Violation!"
    echo "[validate-release-structure]"
    echo "[validate-release-structure]   Found $SRC_COUNT source tarballs:"
    while IFS= read -r artifact; do
      echo "[validate-release-structure]     - $artifact"
    done < "$ARTIFACTS_DIR/.discovered-src-artifacts"
    echo "[validate-release-structure]"
    echo "[validate-release-structure]   Why this is a problem:"
    echo "[validate-release-structure]   - Apache releases are defined by Git repository, not umbrella projects"
    echo "[validate-release-structure]   - Each repository requires a separate release vote"
    echo "[validate-release-structure]   - Bundling multiple repositories violates release independence"
    echo "[validate-release-structure]   - Users cannot verify which repository produced each tarball"
    echo "[validate-release-structure]   - Makes source code traceability impossible"
    echo "[validate-release-structure]"
    echo "[validate-release-structure]   Correct approach:"
    echo "[validate-release-structure]   - Create separate release votes for each repository"
    echo "[validate-release-structure]   - Each vote includes ONE source tarball from ONE repository"
    echo "[validate-release-structure]   - Example for this project:"
    echo "[validate-release-structure]       [VOTE] Release Apache ${COMPONENT_NAME%-*} Core 1.x.x-incubating (RC1)"
    echo "[validate-release-structure]       [VOTE] Release Apache ${COMPONENT_NAME%-*} Component2 1.x.x-incubating (RC1)"
    echo "[validate-release-structure]       [VOTE] Release Apache ${COMPONENT_NAME%-*} Component3 1.x.x-incubating (RC1)"
    echo "[validate-release-structure]"
    echo "[validate-release-structure]   Reference:"
    echo "[validate-release-structure]   - Apache Release Policy: https://www.apache.org/legal/release-policy.html"
    echo "[validate-release-structure]   - Section: 'What Must Every ASF Release Contain'"
    echo "[validate-release-structure]   - 'Releases are identified by a unique version number'"
    echo "[validate-release-structure]"
    VALIDATION_PASSED=false
  else
    echo "[validate-release-structure] ⚠ WARNING: No source artifacts found in discovery"
    echo "[validate-release-structure]    This may indicate the discover step hasn't run yet"
  fi
else
  echo "[validate-release-structure] ⚠ WARNING: No discovered artifacts file found"
  echo "[validate-release-structure]    Expected: $ARTIFACTS_DIR/.discovered-src-artifacts"
  echo "[validate-release-structure]    Please run apache-discover-and-verify-release first"
fi

echo ""
echo "[validate-release-structure] ========================================="
echo "[validate-release-structure] Validation Summary"
echo "[validate-release-structure] ========================================="
echo ""

if [[ "$VALIDATION_PASSED" == "true" ]]; then
  echo "[validate-release-structure] ========================================="
  echo "[validate-release-structure] RESULT: ✅ PASS"
  echo "[validate-release-structure] ========================================="
  echo "[validate-release-structure]"
  echo "[validate-release-structure] Release structure complies with Apache policies"
  echo "[validate-release-structure] - RC designation present in URL"
  echo "[validate-release-structure] - Single source tarball (one repository per vote)"
  echo "[validate-release-structure] ========================================="
  exit 0
else
  echo "[validate-release-structure] ========================================="
  echo "[validate-release-structure] RESULT: ❌ FAIL - Policy Violations"
  echo "[validate-release-structure] ========================================="
  echo "[validate-release-structure]"
  echo "[validate-release-structure] Release structure violates Apache policies"
  echo "[validate-release-structure]"
  echo "[validate-release-structure] This release cannot proceed to vote in its current form."
  echo "[validate-release-structure] The release manager must restructure the release to comply"
  echo "[validate-release-structure] with Apache release policies before a valid vote can occur."
  echo "[validate-release-structure]"
  echo "[validate-release-structure] Review the detailed findings above for specific violations."
  echo "[validate-release-structure] ========================================="
  exit 1
fi
