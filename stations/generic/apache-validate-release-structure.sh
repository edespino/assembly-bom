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
echo "[validate-release-structure] Step 2: Validating Source Artifacts"
echo "[validate-release-structure] ========================================="

# A single release vote may cover several source artifacts of the same project.
# The vote email names that set. Count is not a policy failure. Each artifact
# is checked on its own. Do not drop an artifact the vote email names.
ARTIFACTS_DIR="$PARTS_DIR/${COMPONENT_NAME}-artifacts"
INCUBATOR_RELEASE=false
if [[ "$RELEASE_URL" == *"/incubator/"* ]] || [[ "${RELEASE_VERSION:-}" == *incubating* ]]; then
  INCUBATOR_RELEASE=true
fi

read_artifact_names() {
  local list_file="$1"
  local -n _out=$2
  _out=()
  [[ -f "$list_file" ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    _out+=("$line")
  done < "$list_file"
}

if [[ -f "$ARTIFACTS_DIR/.discovered-src-artifacts" ]]; then
  read_artifact_names "$ARTIFACTS_DIR/.discovered-src-artifacts" SRC_ARTIFACTS
  SRC_COUNT=${#SRC_ARTIFACTS[@]}

  echo "[validate-release-structure] Discovered source tarballs: $SRC_COUNT"
  echo ""

  if [[ $SRC_COUNT -eq 0 ]]; then
    echo "[validate-release-structure] ❌ FAIL: No source artifacts found"
    echo "[validate-release-structure]    A source release must contain at least one source tarball"
    VALIDATION_PASSED=false
  else
    echo "[validate-release-structure] ✅ PASS: $SRC_COUNT source artifact(s) in this release"
    echo "[validate-release-structure]    Multiple source artifacts are allowed in one release vote."
    echo "[validate-release-structure]    Each artifact is validated on its own."
    echo ""

    for artifact in "${SRC_ARTIFACTS[@]}"; do
      echo "[validate-release-structure] Artifact: $artifact"

      if [[ "$artifact" != *-src.* && "$artifact" != *-source.* ]]; then
        echo "[validate-release-structure] ❌ FAIL: Not a source artifact name: $artifact"
        VALIDATION_PASSED=false
      else
        echo "[validate-release-structure] ✅ PASS: Source artifact name"
      fi

      if [[ "$INCUBATOR_RELEASE" == true ]]; then
        if [[ "$artifact" == *incubating* ]]; then
          echo "[validate-release-structure] ✅ PASS: Filename contains 'incubating'"
        else
          echo "[validate-release-structure] ❌ FAIL: Incubating source artifact must contain 'incubating': $artifact"
          VALIDATION_PASSED=false
        fi
      fi

      if [[ -f "$ARTIFACTS_DIR/$artifact" ]]; then
        echo "[validate-release-structure] ✅ PASS: Artifact file is present"
      else
        echo "[validate-release-structure] ❌ FAIL: Artifact file missing: $ARTIFACTS_DIR/$artifact"
        VALIDATION_PASSED=false
      fi

      if [[ -f "$ARTIFACTS_DIR/$artifact.asc" && -f "$ARTIFACTS_DIR/$artifact.sha512" ]]; then
        echo "[validate-release-structure] ✅ PASS: Signature and SHA512 files are present"
      else
        echo "[validate-release-structure] ❌ FAIL: Missing .asc or .sha512 for $artifact"
        VALIDATION_PASSED=false
      fi
      echo ""
    done
  fi
else
  echo "[validate-release-structure] ❌ FAIL: No discovered artifacts file found"
  echo "[validate-release-structure]    Expected: $ARTIFACTS_DIR/.discovered-src-artifacts"
  echo "[validate-release-structure]    Please run apache-discover-and-verify-release first"
  VALIDATION_PASSED=false
fi

echo "[validate-release-structure] ========================================="
echo "[validate-release-structure] Step 3: Unexpected binaries in the release directory"
echo "[validate-release-structure] ========================================="

if [[ -f "$ARTIFACTS_DIR/.discovered-bin-artifacts" ]]; then
  read_artifact_names "$ARTIFACTS_DIR/.discovered-bin-artifacts" BIN_ARTIFACTS
  if [[ ${#BIN_ARTIFACTS[@]} -eq 0 ]]; then
    echo "[validate-release-structure] ✅ PASS: No binary artifacts in the release directory"
  else
    echo "[validate-release-structure] ❌ FAIL: Unexpected binary artifacts in the release directory"
    for artifact in "${BIN_ARTIFACTS[@]}"; do
      echo "[validate-release-structure]     - $artifact"
    done
    echo "[validate-release-structure]    A source release vote does not include convenience binaries."
    VALIDATION_PASSED=false
  fi
else
  echo "[validate-release-structure] ⚠ WARNING: No discovered binary list found"
  echo "[validate-release-structure]    Expected: $ARTIFACTS_DIR/.discovered-bin-artifacts"
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
  echo "[validate-release-structure] - Each source artifact checked on its own"
  echo "[validate-release-structure] - No unexpected binary artifacts in the release directory"
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
