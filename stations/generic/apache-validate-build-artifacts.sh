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

# Find all extracted source directories (ending in -src)
mapfile -t SOURCE_DIRS < <(find "$COMPONENT_DIR" -maxdepth 1 -type d -name "*-src" | sort)

if [[ ${#SOURCE_DIRS[@]} -eq 0 ]]; then
  echo "[validate-build-artifacts] ❌ No extracted source directories found"
  echo "[validate-build-artifacts] Please run extract step first"
  exit 1
fi

echo "[validate-build-artifacts] Found ${#SOURCE_DIRS[@]} source director(ies):"
for dir in "${SOURCE_DIRS[@]}"; do
  echo "[validate-build-artifacts]   - $(basename "$dir")"
done
echo ""

# Auto-detect incubator project
if [[ "$INCUBATOR_PROJECT" == "auto" ]]; then
  RELEASE_URL="${RELEASE_URL:-}"
  # Use first directory for detection
  FIRST_SOURCE_DIR="${SOURCE_DIRS[0]}"
  if [[ "$COMPONENT_NAME" == *"incubating"* ]] || \
     [[ "$FIRST_SOURCE_DIR" == *"incubating"* ]] || \
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
  echo "[validate-build-artifacts]   All built artifacts MUST contain 'incubating' in filename"
  echo "[validate-build-artifacts]   This includes: JAR files, Python wheels, source distributions"
  echo "[validate-build-artifacts]   Reference: https://incubator.apache.org/policy/incubation.html"
else
  echo "[validate-build-artifacts] ℹ Not an incubator project"
  echo "[validate-build-artifacts]   Artifact naming requirements do not apply"
  echo "[validate-build-artifacts] ========================================="
  echo "[validate-build-artifacts] ✓ Validation SKIPPED (not required)"
  exit 0
fi

# Global validation tracking
GLOBAL_VALIDATION_PASSED=true
GLOBAL_COMPLIANT_ARTIFACTS=0
GLOBAL_NONCOMPLIANT_ARTIFACTS=0
GLOBAL_VIOLATIONS=()

# Process each source directory
for EXTRACTED_DIR in "${SOURCE_DIRS[@]}"; do
  echo ""
  echo "[validate-build-artifacts] ========================================"
  echo "[validate-build-artifacts] Checking: $(basename "$EXTRACTED_DIR")"
  echo "[validate-build-artifacts] ========================================"

  # Change to extracted directory
  cd "$EXTRACTED_DIR"

  # Detect project type
  IS_MAVEN=false
  IS_PYTHON=false

  if [[ -f "pom.xml" ]]; then
    IS_MAVEN=true
    echo "[validate-build-artifacts] ℹ Maven project detected"
  fi

  if [[ -f "pyproject.toml" ]]; then
    IS_PYTHON=true
    echo "[validate-build-artifacts] ℹ Python project detected"
  fi

  if [[ "$IS_MAVEN" == "false" ]] && [[ "$IS_PYTHON" == "false" ]]; then
    if [[ -f "go.mod" ]]; then
      echo "[validate-build-artifacts] ℹ Go project - no JARs/wheels expected"
    else
      echo "[validate-build-artifacts] ℹ Unknown build system - skipping validation"
    fi
    continue
  fi

  echo ""

  # Collect artifacts to validate
  ARTIFACT_FILES=()

  # Maven: Find JAR files
  if [[ "$IS_MAVEN" == "true" ]]; then
    while IFS= read -r -d '' jar_file; do
      jar_basename=$(basename "$jar_file")

      # Skip test JARs and originals
      if [[ "$jar_basename" == *"-test-jar.jar" ]] ||
         [[ "$jar_basename" == *"-tests.jar" ]] ||
         [[ "$jar_basename" == "original-"* ]]; then
        continue
      fi

      ARTIFACT_FILES+=("$jar_file")
    done < <(find . -path "*/target/*.jar" -type f -print0 2>/dev/null || true)

    TOTAL_JARS=$(find . -type f -name "*.jar" 2>/dev/null | wc -l)
    echo "[validate-build-artifacts] Found $TOTAL_JARS total JAR file(s)"
    echo "[validate-build-artifacts] Checking ${#ARTIFACT_FILES[@]} project JAR(s) (excluding test/original)"
  fi

  # Python: Find wheel and source distribution files
  if [[ "$IS_PYTHON" == "true" ]]; then
    if [[ -d "dist" ]]; then
      while IFS= read -r -d '' whl_file; do
        ARTIFACT_FILES+=("$whl_file")
      done < <(find dist -name "*.whl" -type f -print0 2>/dev/null || true)

      while IFS= read -r -d '' tar_gz_file; do
        # Only check tar.gz files (source distributions)
        ARTIFACT_FILES+=("$tar_gz_file")
      done < <(find dist -name "*.tar.gz" -type f -print0 2>/dev/null || true)

      WHL_COUNT=$(find dist -name "*.whl" 2>/dev/null | wc -l)
      SDIST_COUNT=$(find dist -name "*.tar.gz" 2>/dev/null | wc -l)
      echo "[validate-build-artifacts] Found $WHL_COUNT wheel file(s) and $SDIST_COUNT source distribution(s)"
    else
      echo "[validate-build-artifacts] ⚠ No dist/ directory found"
      echo "[validate-build-artifacts]   Python build may not have run"
    fi
  fi

  if [[ ${#ARTIFACT_FILES[@]} -eq 0 ]]; then
    echo "[validate-build-artifacts] ⚠ No artifacts found for validation"
    echo "[validate-build-artifacts]   Build may not have produced artifacts"
    continue
  fi

  echo ""

  # Validate each artifact
  for artifact_file in "${ARTIFACT_FILES[@]}"; do
    artifact_basename=$(basename "$artifact_file")

    # Check if filename contains "incubating"
    if [[ "$artifact_basename" == *"incubating"* ]]; then
      echo "[validate-build-artifacts] ✓ $artifact_basename"
      ((GLOBAL_COMPLIANT_ARTIFACTS++)) || true
    else
      echo "[validate-build-artifacts] ❌ $artifact_basename (MISSING 'incubating')"
      GLOBAL_VIOLATIONS+=("$artifact_file")
      GLOBAL_VALIDATION_PASSED=false
      ((GLOBAL_NONCOMPLIANT_ARTIFACTS++)) || true
    fi
  done

done  # End of source directory loop

# Overall summary
echo ""
echo "[validate-build-artifacts] ========================================="
echo "[validate-build-artifacts] Overall Validation Summary"
echo "[validate-build-artifacts] ========================================="
echo "[validate-build-artifacts] Source directories checked: ${#SOURCE_DIRS[@]}"
echo "[validate-build-artifacts] Total artifacts: $((GLOBAL_COMPLIANT_ARTIFACTS + GLOBAL_NONCOMPLIANT_ARTIFACTS))"
echo "[validate-build-artifacts] Compliant: $GLOBAL_COMPLIANT_ARTIFACTS"
echo "[validate-build-artifacts] Non-compliant: $GLOBAL_NONCOMPLIANT_ARTIFACTS"
echo ""

if [[ "$GLOBAL_VALIDATION_PASSED" == "true" ]]; then
  echo "[validate-build-artifacts] ========================================="
  echo "[validate-build-artifacts] RESULT: ✅ PASS"
  echo "[validate-build-artifacts] ========================================="
  echo "[validate-build-artifacts]"
  echo "[validate-build-artifacts] All artifacts comply with incubator naming requirements"
  echo "[validate-build-artifacts] ========================================="
  exit 0
else
  echo "[validate-build-artifacts] ========================================="
  echo "[validate-build-artifacts] RESULT: ❌ FAIL - Naming Violations"
  echo "[validate-build-artifacts] ========================================="
  echo ""
  echo "[validate-build-artifacts] The following artifacts are missing 'incubating' in their names:"
  echo ""
  for violation in "${GLOBAL_VIOLATIONS[@]}"; do
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
  echo "[validate-build-artifacts] - All release artifacts must include 'incubating' in their names"
  echo "[validate-build-artifacts] - This applies to:"
  echo "[validate-build-artifacts]   • JAR files (Maven artifacts)"
  echo "[validate-build-artifacts]   • Python wheel files (.whl)"
  echo "[validate-build-artifacts]   • Python source distributions (.tar.gz)"
  echo "[validate-build-artifacts] - Examples:"
  echo "[validate-build-artifacts]   • my-artifact-1.0.0-incubating.jar (Maven)"
  echo "[validate-build-artifacts]   • my_package-1.0.0.incubating-py3-none-any.whl (Python)"
  echo "[validate-build-artifacts]"
  echo "[validate-build-artifacts] To fix this issue:"
  echo "[validate-build-artifacts] Maven projects:"
  echo "[validate-build-artifacts]   1. Update pom.xml to use version '1.7.0-incubating'"
  echo "[validate-build-artifacts]   2. Ensure all module POMs inherit the version"
  echo "[validate-build-artifacts]   3. Rebuild: mvn clean install"
  echo "[validate-build-artifacts]"
  echo "[validate-build-artifacts] Python projects:"
  echo "[validate-build-artifacts]   1. Update pyproject.toml version to '1.7.0.incubating'"
  echo "[validate-build-artifacts]   2. Rebuild: python3 -m build"
  echo ""
  echo "[validate-build-artifacts] Reference: https://incubator.apache.org/policy/incubation.html"
  echo "[validate-build-artifacts] ========================================="
  exit 1
fi
