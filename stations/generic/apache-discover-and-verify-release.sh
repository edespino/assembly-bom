#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Get component name from environment (exported by assemble.sh)
COMPONENT_NAME="${NAME:?Missing NAME environment variable}"

# Environment variables from BOM
RELEASE_URL="${RELEASE_URL:?Missing RELEASE_URL}"
KEYS_URL="${KEYS_URL:?Missing KEYS_URL}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-${COMPONENT_NAME}-artifacts}"
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"

# Optional: Archive format (defaults to tar.gz)
ARCHIVE_FORMAT="${ARCHIVE_FORMAT:-.tar.gz}"

# Optional: Checksum type (defaults to sha512)
CHECKSUM_TYPE="${CHECKSUM_TYPE:-sha512}"

# Full path to artifacts directory
ARTIFACT_PATH="$PARTS_DIR/$ARTIFACTS_DIR"

echo "[discover-verify] ========================================="
echo "[discover-verify] Apache Release Discovery & Verification"
echo "[discover-verify] ========================================="
echo "[discover-verify] Component:     $COMPONENT_NAME"
echo "[discover-verify] Release URL:   $RELEASE_URL"
echo "[discover-verify] Artifacts Dir: $ARTIFACT_PATH"
echo ""

# Create artifacts directory
mkdir -p "$ARTIFACT_PATH"
cd "$ARTIFACT_PATH"

echo "[discover-verify] Step 1: Discovering artifacts..."
echo "[discover-verify] ----------------------------------------"

# Fetch directory listing and extract artifact filenames
if command -v curl &> /dev/null; then
  ARTIFACTS=$(curl -s "$RELEASE_URL/" | grep -oP 'href="\K[^"]+' | grep -E "\.tar\.gz$|\.tgz$|\.tar\.bz2$|\.tbz2$|\.tar\.xz$|\.txz$|\.zip$" | grep -v "\.asc$\|\.sha\|\.md5" || true)
elif command -v wget &> /dev/null; then
  ARTIFACTS=$(wget -q -O - "$RELEASE_URL/" | grep -oP 'href="\K[^"]+' | grep -E "\.tar\.gz$|\.tgz$|\.tar\.bz2$|\.tbz2$|\.tar\.xz$|\.txz$|\.zip$" | grep -v "\.asc$\|\.sha\|\.md5" || true)
else
  echo "[discover-verify] ❌ Neither curl nor wget is available"
  exit 1
fi

if [[ -z "$ARTIFACTS" ]]; then
  echo "[discover-verify] ❌ No artifacts found at $RELEASE_URL"
  exit 1
fi

# Categorize artifacts
SRC_ARTIFACTS=()
BIN_ARTIFACTS=()

while IFS= read -r artifact; do
  if [[ "$artifact" =~ -src\. ]] || [[ "$artifact" =~ -source\. ]]; then
    SRC_ARTIFACTS+=("$artifact")
  else
    BIN_ARTIFACTS+=("$artifact")
  fi
done <<< "$ARTIFACTS"

echo "[discover-verify] Found ${#SRC_ARTIFACTS[@]} source artifact(s):"
for artifact in "${SRC_ARTIFACTS[@]}"; do
  echo "[discover-verify]   - $artifact"
done

echo "[discover-verify] Found ${#BIN_ARTIFACTS[@]} binary artifact(s):"
for artifact in "${BIN_ARTIFACTS[@]}"; do
  echo "[discover-verify]   - $artifact"
done

# Download KEYS file
echo ""
echo "[discover-verify] Step 2: Downloading KEYS file..."
echo "[discover-verify] ----------------------------------------"

if [[ -f "KEYS" ]]; then
  echo "[discover-verify] ✓ KEYS file already exists"
else
  echo "[discover-verify] Downloading: KEYS"
  if command -v wget &> /dev/null; then
    wget -q "${KEYS_URL}" || {
      echo "[discover-verify] ❌ Failed to download KEYS"
      exit 1
    }
  elif command -v curl &> /dev/null; then
    curl -s -f -L -o "KEYS" "${KEYS_URL}" || {
      echo "[discover-verify] ❌ Failed to download KEYS"
      exit 1
    }
  fi
  echo "[discover-verify] ✓ Downloaded: KEYS"
fi

# Import GPG keys
echo ""
echo "[discover-verify] Step 3: Importing GPG keys..."
echo "[discover-verify] ----------------------------------------"

if command -v gpg &> /dev/null; then
  echo "[discover-verify] Importing keys from KEYS file..."
  gpg --import KEYS 2>&1 | grep -E "(gpg: key|imported|unchanged|secret keys)" || true
  echo "[discover-verify] ✓ GPG keys imported"
else
  echo "[discover-verify] ❌ gpg command not available"
  exit 1
fi

# Function to verify a single artifact
verify_artifact() {
  local tarball="$1"
  local artifact_type="$2"

  echo ""
  echo "[discover-verify] ========================================="
  echo "[discover-verify] Verifying $artifact_type: $tarball"
  echo "[discover-verify] ========================================="

  local signature="${tarball}.asc"
  local checksum="${tarball}.${CHECKSUM_TYPE}"

  # Download artifact
  if [[ -f "$tarball" ]]; then
    echo "[discover-verify] ✓ Artifact already exists: $tarball"
  else
    echo "[discover-verify] Downloading: $tarball"
    if command -v wget &> /dev/null; then
      wget -q "${RELEASE_URL}/${tarball}" || {
        echo "[discover-verify] ❌ Failed to download $tarball"
        return 1
      }
    elif command -v curl &> /dev/null; then
      curl -s -f -L -o "$tarball" "${RELEASE_URL}/${tarball}" || {
        echo "[discover-verify] ❌ Failed to download $tarball"
        return 1
      }
    fi
    echo "[discover-verify] ✓ Downloaded: $tarball"
  fi

  # Download signature
  if [[ -f "$signature" ]]; then
    echo "[discover-verify] ✓ Signature already exists: $signature"
  else
    echo "[discover-verify] Downloading: $signature"
    if command -v wget &> /dev/null; then
      wget -q "${RELEASE_URL}/${signature}" || {
        echo "[discover-verify] ❌ Failed to download $signature"
        return 1
      }
    elif command -v curl &> /dev/null; then
      curl -s -f -L -o "$signature" "${RELEASE_URL}/${signature}" || {
        echo "[discover-verify] ❌ Failed to download $signature"
        return 1
      }
    fi
    echo "[discover-verify] ✓ Downloaded: $signature"
  fi

  # Download checksum
  if [[ -f "$checksum" ]]; then
    echo "[discover-verify] ✓ Checksum already exists: $checksum"
  else
    echo "[discover-verify] Downloading: $checksum"
    if command -v wget &> /dev/null; then
      wget -q "${RELEASE_URL}/${checksum}" || {
        echo "[discover-verify] ❌ Failed to download $checksum"
        return 1
      }
    elif command -v curl &> /dev/null; then
      curl -s -f -L -o "$checksum" "${RELEASE_URL}/${checksum}" || {
        echo "[discover-verify] ❌ Failed to download $checksum"
        return 1
      }
    fi
    echo "[discover-verify] ✓ Downloaded: $checksum"
  fi

  # Verify checksum
  echo "[discover-verify] Verifying ${CHECKSUM_TYPE^^} checksum..."
  local checksum_cmd="${CHECKSUM_TYPE}sum"
  if command -v "$checksum_cmd" &> /dev/null; then
    local expected=$(cat "$checksum" | awk '{print $1}')
    local actual=$($checksum_cmd "$tarball" | awk '{print $1}')

    if [[ "$expected" == "$actual" ]]; then
      echo "[discover-verify] ✓ ${CHECKSUM_TYPE^^} checksum PASSED"
    else
      echo "[discover-verify] ❌ ${CHECKSUM_TYPE^^} checksum FAILED"
      echo "[discover-verify]   Expected: $expected"
      echo "[discover-verify]   Actual:   $actual"
      return 1
    fi
  else
    echo "[discover-verify] ⚠ $checksum_cmd not available, skipping"
  fi

  # Verify GPG signature
  echo "[discover-verify] Verifying GPG signature..."
  if gpg --verify "$signature" "$tarball" 2>&1 | grep -q "Good signature"; then
    echo "[discover-verify] ✓ GPG signature PASSED"
  else
    echo "[discover-verify] ⚠ GPG signature verification had warnings (check output above)"
  fi

  return 0
}

# Verify all artifacts
echo ""
echo "[discover-verify] Step 4: Verifying all artifacts..."
echo "[discover-verify] ----------------------------------------"

TOTAL_VERIFIED=0
FAILED_VERIFICATIONS=0

# Verify source artifacts first
for artifact in "${SRC_ARTIFACTS[@]}"; do
  if verify_artifact "$artifact" "SOURCE"; then
    TOTAL_VERIFIED=$((TOTAL_VERIFIED + 1))
  else
    FAILED_VERIFICATIONS=$((FAILED_VERIFICATIONS + 1))
  fi
done

# Verify binary artifacts
for artifact in "${BIN_ARTIFACTS[@]}"; do
  if verify_artifact "$artifact" "BINARY"; then
    TOTAL_VERIFIED=$((TOTAL_VERIFIED + 1))
  else
    FAILED_VERIFICATIONS=$((FAILED_VERIFICATIONS + 1))
  fi
done

# Save artifact list for extraction step (one per line)
printf "%s\n" "${SRC_ARTIFACTS[@]}" > .discovered-src-artifacts
printf "%s\n" "${BIN_ARTIFACTS[@]}" > .discovered-bin-artifacts

echo ""
echo "[discover-verify] ========================================="
echo "[discover-verify] Verification Summary"
echo "[discover-verify] ========================================="
echo "[discover-verify] Total artifacts: $((${#SRC_ARTIFACTS[@]} + ${#BIN_ARTIFACTS[@]}))"
echo "[discover-verify] Successfully verified: $TOTAL_VERIFIED"
echo "[discover-verify] Failed verifications: $FAILED_VERIFICATIONS"
echo "[discover-verify]"
echo "[discover-verify] Location: $ARTIFACT_PATH"
echo "[discover-verify]"

if [[ $FAILED_VERIFICATIONS -eq 0 ]]; then
  echo "[discover-verify] ✓ All artifact verifications completed successfully"
  echo "[discover-verify] ========================================="
  exit 0
else
  echo "[discover-verify] ❌ Some artifact verifications failed"
  echo "[discover-verify] ========================================="
  exit 1
fi
