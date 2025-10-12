#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/utilities/wal-g/build.sh
# Purpose  : Build script for the 'wal-g' backup utility.
# Inputs   :
#   - NAME           : name of the component (default: wal-g)
#   - BUILD_FLAGS    : build flags from bom.yaml (USE_BROTLI, USE_LIBSODIUM, USE_LZO)
# --------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# Load shared functions
COMMON_SH="${SCRIPT_DIR}/../../../lib/common.sh"
if [ -f "${COMMON_SH}" ]; then
  # shellcheck disable=SC1090
  source "${COMMON_SH}"
else
  echo "[$SCRIPT_NAME] Missing library: ${COMMON_SH}" >&2
  exit 1
fi

# shellcheck disable=SC1091
[ -f config/env.sh ] && source config/env.sh

NAME="${NAME:-wal-g}"
WALG_DIR="$PARTS_DIR/$NAME"

section "build: $NAME"
start_time=$(date +%s)

# Validate wal-g source directory
if [[ ! -f "$WALG_DIR/Makefile" ]]; then
  echo "[build-wal-g] ERROR: No Makefile found in $WALG_DIR"
  exit 1
fi
cd "$WALG_DIR"

# Export build flags from bom.yaml
if [[ -n "${BUILD_FLAGS:-}" ]]; then
  log "Applying build flags: $BUILD_FLAGS"
  # Parse multi-line build flags and export them
  while IFS= read -r flag; do
    if [[ -n "$flag" ]]; then
      export "$flag"
      log "  - $flag"
    fi
  done <<< "$BUILD_FLAGS"
fi

# Check for required dependencies
log "Checking dependencies..."

# Check for Go compiler
if ! command -v go &> /dev/null; then
  echo "[build-wal-g] ERROR: Go compiler not found. Install Go 1.15+ to build wal-g"
  exit 1
fi
GO_VERSION=$(go version | awk '{print $3}')
log "  - Go compiler: $GO_VERSION"

# Check for optional compression libraries
if [[ "${USE_BROTLI:-0}" == "1" ]]; then
  if pkg-config --exists libbrotlienc 2>/dev/null; then
    log "  - Brotli: enabled"
  else
    echo "[build-wal-g] WARNING: USE_BROTLI=1 but libbrotlienc not found"
    echo "[build-wal-g] Install with: sudo dnf install brotli-devel"
  fi
fi

if [[ "${USE_LIBSODIUM:-0}" == "1" ]]; then
  # Check for locally-built libsodium first, then system libsodium
  if [[ -f /opt/libsodium/lib/pkgconfig/libsodium.pc ]]; then
    export PKG_CONFIG_PATH="/opt/libsodium/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
    export LD_LIBRARY_PATH="/opt/libsodium/lib:${LD_LIBRARY_PATH:-}"
    export CPATH="/opt/libsodium/include:${CPATH:-}"
    log "  - Libsodium: enabled (using /opt/libsodium)"
  elif pkg-config --exists libsodium 2>/dev/null; then
    log "  - Libsodium: enabled (using system libsodium)"
  else
    echo "[build-wal-g] WARNING: USE_LIBSODIUM=1 but libsodium not found"
    echo "[build-wal-g] Build it with: ./assemble.sh --run --component libsodium"
  fi
fi

if [[ "${USE_LZO:-0}" == "1" ]]; then
  if pkg-config --exists lzo2 2>/dev/null; then
    log "  - LZO: enabled"
  else
    echo "[build-wal-g] ERROR: USE_LZO=1 but lzo2 development headers not found"
    echo "[build-wal-g] Install with: sudo dnf install lzo-devel"
    exit 1
  fi
fi

# Install Go dependencies
log "Installing Go dependencies..."
make deps 2>&1 | tee "make-${NAME}-deps-$(date '+%Y%m%d-%H%M%S').log"

# Build wal-g for Greenplum/Cloudberry
log "Building $NAME for Greenplum/Cloudberry..."
cd main/gp

# Prepare build tags
BUILD_TAGS=""
[[ "${USE_BROTLI:-0}" == "1" ]] && BUILD_TAGS="$BUILD_TAGS brotli"
[[ "${USE_LIBSODIUM:-0}" == "1" ]] && BUILD_TAGS="$BUILD_TAGS libsodium"
[[ "${USE_LZO:-0}" == "1" ]] && BUILD_TAGS="$BUILD_TAGS lzo"
BUILD_TAGS=$(echo "$BUILD_TAGS" | xargs)  # trim whitespace

# Prepare version ldflags (fix Makefile shell expansion issue)
BUILD_DATE=$(date -u +%Y.%m.%d_%H:%M:%S)
GIT_REVISION=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
# Get the highest version tag at HEAD, or use the branch name from bom.yaml
WAL_G_VERSION=$(git tag -l --points-at HEAD 2>/dev/null | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
[[ -z "$WAL_G_VERSION" ]] && WAL_G_VERSION="${BRANCH:-v3.0.7}"

LDFLAGS="-s -w"
LDFLAGS="$LDFLAGS -X github.com/wal-g/wal-g/cmd/gp.buildDate=$BUILD_DATE"
LDFLAGS="$LDFLAGS -X github.com/wal-g/wal-g/cmd/gp.gitRevision=$GIT_REVISION"
LDFLAGS="$LDFLAGS -X github.com/wal-g/wal-g/cmd/gp.walgVersion=$WAL_G_VERSION"

log "Build tags: $BUILD_TAGS"
log "Version: $WAL_G_VERSION (git: $GIT_REVISION, built: $BUILD_DATE)"

go build -mod vendor -tags "$BUILD_TAGS" -ldflags "$LDFLAGS" -o wal-g 2>&1 | tee "$WALG_DIR/make-${NAME}-build-$(date '+%Y%m%d-%H%M%S').log"
cd "$WALG_DIR"

# Verify the binary was created
if [[ ! -f "main/gp/wal-g" ]]; then
  echo "[build-wal-g] ERROR: Binary not found at main/gp/wal-g"
  exit 1
fi

log "Build successful: $(file main/gp/wal-g)"

section_complete "build-wal-g" "$start_time"
