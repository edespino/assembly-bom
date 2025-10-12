#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/utilities/wal-g/install.sh
# Purpose  : Install script for the 'wal-g' backup utility.
# Inputs   :
#   - NAME           : name of the component (default: wal-g)
#   - INSTALL_PREFIX : installation prefix (default: /usr/local/wal-g)
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
INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/wal-g}"

section "install: $NAME"
start_time=$(date +%s)

# Validate binary exists
if [[ ! -f "$WALG_DIR/main/pg/wal-g" ]]; then
  echo "[install-wal-g] ERROR: Binary not found at $WALG_DIR/main/pg/wal-g"
  exit 1
fi

# Create installation directory
log "Creating installation directory: $INSTALL_PREFIX"
sudo mkdir -p "$INSTALL_PREFIX/bin"

# Install the binary
log "Installing wal-g binary to $INSTALL_PREFIX/bin/"
sudo cp "$WALG_DIR/main/pg/wal-g" "$INSTALL_PREFIX/bin/"
sudo chmod +x "$INSTALL_PREFIX/bin/wal-g"

# Verify installation
if [[ -f "$INSTALL_PREFIX/bin/wal-g" ]]; then
  log "Installation successful"
  log "Binary installed at: $INSTALL_PREFIX/bin/wal-g"

  # Show version info
  if "$INSTALL_PREFIX/bin/wal-g" --version &>/dev/null; then
    VERSION=$("$INSTALL_PREFIX/bin/wal-g" --version 2>&1 || true)
    log "Version: $VERSION"
  fi

  log ""
  log "To use wal-g, add to PATH:"
  log "  export PATH=\"$INSTALL_PREFIX/bin:\$PATH\""
else
  echo "[install-wal-g] ERROR: Installation failed"
  exit 1
fi

section_complete "install-wal-g" "$start_time"
