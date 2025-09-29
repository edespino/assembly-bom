#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Validate inputs
COMPONENT_NAME="${1:?Missing component name}"
REPO_URL="${2:?Missing repository URL}"
BRANCH="${3:?Missing branch name}"

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$COMPONENT_NAME"

echo "[clone] Component: $COMPONENT_NAME"
echo "[clone] URL:       $REPO_URL"
echo "[clone] Version:   $BRANCH"

# Auto-detect source type based on URL
detect_source_type() {
  local url="$1"
  if [[ "$url" =~ \.(tar\.gz|tgz)$ ]]; then
    echo "tar.gz"
  elif [[ "$url" =~ \.(tar\.bz2|tbz2)$ ]]; then
    echo "tar.bz2"
  elif [[ "$url" =~ \.(tar\.xz|txz)$ ]]; then
    echo "tar.xz"
  elif [[ "$url" =~ \.zip$ ]]; then
    echo "zip"
  elif [[ "$url" =~ ^git@ ]] || [[ "$url" =~ \.git$ ]] || [[ "$url" =~ github\.com|gitlab\.com|bitbucket\.org ]]; then
    echo "git"
  else
    echo "unknown"
  fi
}

# Handle Git repositories
handle_git_repository() {
  if [[ -d "$COMPONENT_DIR/.git" ]]; then
    echo "[clone] $COMPONENT_NAME already exists. Fetching latest from $BRANCH..."
    git -C "$COMPONENT_DIR" fetch origin
    git -C "$COMPONENT_DIR" checkout "$BRANCH"
    git -C "$COMPONENT_DIR" pull
  else
    echo "[clone] Cloning $COMPONENT_NAME into $COMPONENT_DIR"
    git clone --branch "$BRANCH" "$REPO_URL" "$COMPONENT_DIR"
  fi

  # Always update submodules to ensure consistency
  echo "[clone] Initializing submodules (if any)..."
  git -C "$COMPONENT_DIR" submodule update --init --recursive || true
}

# Verify MD5 checksum if available
verify_md5_checksum() {
  local filename="$1"
  local md5_url="${REPO_URL}.md5"
  local md5_file="${filename}.md5"

  echo "[clone] Attempting to download MD5 checksum from $md5_url..."

  # Try to download MD5 checksum file
  if command -v wget &> /dev/null; then
    if wget -q -O "$md5_file" "$md5_url" 2>/dev/null; then
      echo "[clone] ✓ MD5 checksum file downloaded successfully"
    else
      echo "[clone] ⚠ MD5 checksum file not available, skipping validation"
      return 0
    fi
  elif command -v curl &> /dev/null; then
    if curl -s -f -L -o "$md5_file" "$md5_url" 2>/dev/null; then
      echo "[clone] ✓ MD5 checksum file downloaded successfully"
    else
      echo "[clone] ⚠ MD5 checksum file not available, skipping validation"
      return 0
    fi
  else
    echo "[clone] ⚠ No download tool available for MD5 validation"
    return 0
  fi

  # Verify the checksum
  if command -v md5sum &> /dev/null; then
    # Parse MD5 file format: "MD5 (filename) = hash", "hash  filename", or just "hash"
    local expected_md5=$(cat "$md5_file" | sed -n 's/.*= \([a-f0-9]*\).*/\1/p; s/^\([a-f0-9]*\)  .*/\1/p; /^[a-f0-9]*$/p' | head -1)
    local actual_md5=$(md5sum "$filename" | cut -d' ' -f1)

    if [[ "$expected_md5" == "$actual_md5" ]]; then
      echo "[clone] ✓ MD5 checksum verification passed"
      rm -f "$md5_file"  # Clean up the checksum file
      return 0
    else
      echo "[clone] ❌ MD5 checksum verification failed!"
      echo "[clone]    Expected: $expected_md5"
      echo "[clone]    Actual:   $actual_md5"
      rm -f "$filename" "$md5_file"  # Clean up both files
      exit 1
    fi
  else
    echo "[clone] ⚠ md5sum command not available, skipping validation"
    rm -f "$md5_file"  # Clean up the checksum file
    return 0
  fi
}

# Handle tarball downloads
handle_tarball() {
  local filename=$(basename "$REPO_URL")
  local extract_dir

  # Create component directory
  mkdir -p "$COMPONENT_DIR"
  cd "$COMPONENT_DIR"

  # Check if already downloaded and extracted
  if [[ -f "$filename" ]] && [[ -n "$(find . -maxdepth 1 -type d -not -name '.' | head -1)" ]]; then
    echo "[clone] $COMPONENT_NAME already exists and extracted"
    return
  fi

  # Download the tarball
  echo "[clone] Downloading $filename..."
  if command -v wget &> /dev/null; then
    wget -q -O "$filename" "$REPO_URL"
  elif command -v curl &> /dev/null; then
    curl -s -L -o "$filename" "$REPO_URL"
  else
    echo "[clone] ❌ Neither wget nor curl is available for downloading"
    exit 1
  fi

  # Verify MD5 checksum if available
  verify_md5_checksum "$filename"

  # Extract based on file type
  echo "[clone] Extracting $filename..."
  case "$SOURCE_TYPE" in
    "tar.gz")
      tar -xzf "$filename"
      ;;
    "tar.bz2")
      tar -xjf "$filename"
      ;;
    "tar.xz")
      tar -xJf "$filename"
      ;;
  esac

  # Find the extracted directory (usually component-version)
  extract_dir=$(find . -maxdepth 1 -type d -not -name '.' | head -1)
  if [[ -z "$extract_dir" ]]; then
    echo "[clone] ❌ No directory found after extraction"
    exit 1
  fi

  echo "[clone] Extracted to: $extract_dir"
  echo "[clone] Archive file: $filename (kept for reference)"
}

# Handle ZIP archives
handle_zip_archive() {
  local filename=$(basename "$REPO_URL")

  # Create component directory
  mkdir -p "$COMPONENT_DIR"
  cd "$COMPONENT_DIR"

  # Check if already downloaded and extracted
  if [[ -f "$filename" ]] && [[ -n "$(find . -maxdepth 1 -type d -not -name '.' | head -1)" ]]; then
    echo "[clone] $COMPONENT_NAME already exists and extracted"
    return
  fi

  # Download the zip file
  echo "[clone] Downloading $filename..."
  if command -v wget &> /dev/null; then
    wget -q -O "$filename" "$REPO_URL"
  elif command -v curl &> /dev/null; then
    curl -s -L -o "$filename" "$REPO_URL"
  else
    echo "[clone] ❌ Neither wget nor curl is available for downloading"
    exit 1
  fi

  # Extract zip file
  echo "[clone] Extracting $filename..."
  unzip -q "$filename"

  # Find the extracted directory
  extract_dir=$(find . -maxdepth 1 -type d -not -name '.' | head -1)
  if [[ -z "$extract_dir" ]]; then
    echo "[clone] ❌ No directory found after extraction"
    exit 1
  fi

  echo "[clone] Extracted to: $extract_dir"
  echo "[clone] Archive file: $filename (kept for reference)"
}

# Main logic - determine source type and handle accordingly
SOURCE_TYPE=$(detect_source_type "$REPO_URL")
echo "[clone] Source type: $SOURCE_TYPE"

case "$SOURCE_TYPE" in
  "git")
    handle_git_repository
    ;;
  "tar.gz"|"tar.bz2"|"tar.xz")
    handle_tarball
    ;;
  "zip")
    handle_zip_archive
    ;;
  *)
    echo "[clone] ❌ Unsupported source type for URL: $REPO_URL"
    exit 1
    ;;
esac
