#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Get component name from environment (exported by assemble.sh)
COMPONENT_NAME="${NAME:?Missing NAME environment variable}"

# Environment variables from BOM
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${COMPONENT_NAME}-artifacts}"
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"

# Paths
ARTIFACT_PATH="$PARTS_DIR/$ARTIFACTS_DIR"
COMPONENT_DIR="$PARTS_DIR/$COMPONENT_NAME"

echo "[extract-discovered] ========================================="
echo "[extract-discovered] Extract Discovered Artifacts"
echo "[extract-discovered] ========================================="
echo "[extract-discovered] Component:     $COMPONENT_NAME"
echo "[extract-discovered] Source:        $ARTIFACT_PATH"
echo "[extract-discovered] Destination:   $COMPONENT_DIR"
echo ""

# Check for discovered artifacts list
if [[ ! -f "$ARTIFACT_PATH/.discovered-src-artifacts" ]] || [[ ! -f "$ARTIFACT_PATH/.discovered-bin-artifacts" ]]; then
  echo "[extract-discovered] ❌ No discovered artifacts found"
  echo "[extract-discovered] Please run discover-and-verify-apache-release step first"
  exit 1
fi

# Read discovered artifacts
mapfile -t SRC_ARTIFACTS < <(cat "$ARTIFACT_PATH/.discovered-src-artifacts")
mapfile -t BIN_ARTIFACTS < <(cat "$ARTIFACT_PATH/.discovered-bin-artifacts")

echo "[extract-discovered] Source artifacts to extract: ${#SRC_ARTIFACTS[@]}"
echo "[extract-discovered] Binary artifacts to extract: ${#BIN_ARTIFACTS[@]}"
echo ""

# Create component directory
mkdir -p "$COMPONENT_DIR"
cd "$COMPONENT_DIR"

# Function to extract a single artifact
extract_artifact() {
  local tarball="$1"
  local artifact_type="$2"

  echo ""
  echo "[extract-discovered] ========================================="
  echo "[extract-discovered] Extracting $artifact_type: $tarball"
  echo "[extract-discovered] ========================================="

  # Verify tarball exists
  if [[ ! -f "$ARTIFACT_PATH/$tarball" ]]; then
    echo "[extract-discovered] ❌ Artifact not found: $ARTIFACT_PATH/$tarball"
    return 1
  fi

  # Determine archive format from filename
  local archive_format
  if [[ "$tarball" =~ \.tar\.gz$ ]] || [[ "$tarball" =~ \.tgz$ ]]; then
    archive_format="tar.gz"
  elif [[ "$tarball" =~ \.tar\.bz2$ ]] || [[ "$tarball" =~ \.tbz2$ ]]; then
    archive_format="tar.bz2"
  elif [[ "$tarball" =~ \.tar\.xz$ ]] || [[ "$tarball" =~ \.txz$ ]]; then
    archive_format="tar.xz"
  elif [[ "$tarball" =~ \.zip$ ]]; then
    archive_format="zip"
  else
    echo "[extract-discovered] ❌ Unknown archive format for: $tarball"
    return 1
  fi

  # Check if already extracted
  # Determine expected extracted directory name by peeking into the tarball
  local expected_dir=""
  case "$archive_format" in
    "tar.gz"|"tar.bz2"|"tar.xz")
      # Get first directory entry, handling paths that start with ./
      expected_dir=$(tar -tf "$ARTIFACT_PATH/$tarball" | head -1 | sed 's|^\./||' | cut -d'/' -f1)
      ;;
    "zip")
      expected_dir=$(unzip -l "$ARTIFACT_PATH/$tarball" | awk 'NR==4 {print $4}' | sed 's|^\./||' | cut -d'/' -f1)
      ;;
  esac

  if [[ -n "$expected_dir" ]] && [[ "$expected_dir" != "." ]] && [[ -d "$expected_dir" ]]; then
    echo "[extract-discovered] ⚠ Artifact appears to be already extracted"
    echo "[extract-discovered] Existing: $expected_dir"
    echo "[extract-discovered] Skipping extraction (use --force to re-extract)"
    return 0
  fi

  echo "[extract-discovered] Extracting from $ARTIFACT_PATH/$tarball..."

  # Extract based on format
  case "$archive_format" in
    "tar.gz")
      tar -xzf "$ARTIFACT_PATH/$tarball"
      ;;
    "tar.bz2")
      tar -xjf "$ARTIFACT_PATH/$tarball"
      ;;
    "tar.xz")
      tar -xJf "$ARTIFACT_PATH/$tarball"
      ;;
    "zip")
      unzip -q "$ARTIFACT_PATH/$tarball"
      ;;
    *)
      echo "[extract-discovered] ❌ Unsupported format: $archive_format"
      return 1
      ;;
  esac

  # Find the extracted directory
  local extracted_dir=$(find . -maxdepth 1 -type d -not -path "$COMPONENT_DIR" -newer "$ARTIFACT_PATH/$tarball" | head -1)

  if [[ -z "$extracted_dir" ]]; then
    # Fallback: try to find by name pattern
    extracted_dir=$(find . -maxdepth 1 -type d -name "${base_name}*" | head -1)
  fi

  if [[ -z "$extracted_dir" ]]; then
    echo "[extract-discovered] ❌ No directory found after extraction"
    return 1
  fi

  extracted_dir="${extracted_dir#./}"

  echo "[extract-discovered] ✓ Extracted successfully"
  echo "[extract-discovered] Directory: $extracted_dir"
  echo "[extract-discovered] Full path: $COMPONENT_DIR/$extracted_dir"

  # Show preview
  echo "[extract-discovered] Contents preview:"
  ls -la "$extracted_dir" 2>/dev/null | head -10 | sed 's/^/[extract-discovered]   /' || echo "[extract-discovered]   (unable to list contents)"
  local total_items=$(find "$extracted_dir" -maxdepth 1 2>/dev/null | wc -l)
  echo "[extract-discovered]   ... ($total_items total items)"

  return 0
}

TOTAL_EXTRACTED=0
FAILED_EXTRACTIONS=0

# Extract source artifacts
for artifact in "${SRC_ARTIFACTS[@]}"; do
  [[ -z "$artifact" ]] && continue
  if extract_artifact "$artifact" "SOURCE"; then
    TOTAL_EXTRACTED=$((TOTAL_EXTRACTED + 1))
  else
    FAILED_EXTRACTIONS=$((FAILED_EXTRACTIONS + 1))
  fi
done

# Extract binary artifacts
for artifact in "${BIN_ARTIFACTS[@]}"; do
  [[ -z "$artifact" ]] && continue
  if extract_artifact "$artifact" "BINARY"; then
    TOTAL_EXTRACTED=$((TOTAL_EXTRACTED + 1))
  else
    FAILED_EXTRACTIONS=$((FAILED_EXTRACTIONS + 1))
  fi
done

echo ""
echo "[extract-discovered] ========================================="
echo "[extract-discovered] Extraction Summary"
echo "[extract-discovered] ========================================="
echo "[extract-discovered] Total artifacts extracted: $TOTAL_EXTRACTED"
echo "[extract-discovered] Failed extractions: $FAILED_EXTRACTIONS"
echo "[extract-discovered]"
echo "[extract-discovered] Location: $COMPONENT_DIR"
echo "[extract-discovered]"

if [[ $FAILED_EXTRACTIONS -eq 0 ]]; then
  echo "[extract-discovered] ✓ All extraction steps completed successfully"
  echo "[extract-discovered] ========================================="
  exit 0
else
  echo "[extract-discovered] ❌ Some extraction steps failed"
  echo "[extract-discovered] ========================================="
  exit 1
fi
