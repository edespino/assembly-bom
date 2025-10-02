#!/bin/sh
# --------------------------------------------------------------------
# File     : stations/dependencies/geos/configure.sh
# Purpose  : Configure step for GEOS library using CMake
# Inputs   :
#   - NAME              : component name (should be "geos")
#   - CONFIGURE_FLAGS   : CMake flags from bom.yaml
#   - INSTALL_PREFIX    : defaults to /usr/local/$NAME
# --------------------------------------------------------------------

set -e

[ -f config/env.sh ] && . config/env.sh

# Validate input
if [ -z "$NAME" ]; then
  echo "Error: NAME is not set"
  exit 1
fi

# Navigate to GEOS extracted directory
GEOS_EXTRACT_DIR="$PARTS_DIR/$NAME/geos-3.11.0"
cd "$GEOS_EXTRACT_DIR" || {
  echo "Error: Directory '$GEOS_EXTRACT_DIR' not found"
  exit 1
}

INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/$NAME}"

echo "==> Configuring $NAME..."
echo "    Working directory: $GEOS_EXTRACT_DIR"
echo "    INSTALL_PREFIX=$INSTALL_PREFIX"
echo "    CONFIGURE_FLAGS:"
echo "$CONFIGURE_FLAGS"

# Create build directory and configure with CMake
mkdir -p build
cd build

# Build CMake command
CMD="cmake $CONFIGURE_FLAGS .."

echo "    Running: $CMD"
# shellcheck disable=SC2086
eval $CMD 2>&1 | tee "configure-$(date '+%Y%m%d-%H%M%S').log"

echo "✅ configure step complete for $NAME"