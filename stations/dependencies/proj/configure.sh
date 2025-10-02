#!/bin/sh
# --------------------------------------------------------------------
# File     : stations/dependencies/proj/configure.sh
# Purpose  : Configure step for PROJ library using autotools
# Inputs   :
#   - NAME              : component name (should be "proj")
#   - CONFIGURE_FLAGS   : configure flags from bom.yaml
#   - INSTALL_PREFIX    : defaults to /usr/local/$NAME
# --------------------------------------------------------------------

set -e

[ -f config/env.sh ] && . config/env.sh

# Validate input
if [ -z "$NAME" ]; then
  echo "Error: NAME is not set"
  exit 1
fi

# Navigate to PROJ extracted directory
PROJ_EXTRACT_DIR="$PARTS_DIR/$NAME/proj-6.0.0"
cd "$PROJ_EXTRACT_DIR" || {
  echo "Error: Directory '$PROJ_EXTRACT_DIR' not found"
  exit 1
}

INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/$NAME}"

echo "==> Configuring $NAME..."
echo "    Working directory: $PROJ_EXTRACT_DIR"
echo "    INSTALL_PREFIX=$INSTALL_PREFIX"
echo "    CONFIGURE_FLAGS:"
echo "$CONFIGURE_FLAGS"

# Build configure command
CMD="./configure $CONFIGURE_FLAGS"

echo "    Running: $CMD"
# shellcheck disable=SC2086
eval $CMD 2>&1 | tee "configure-$(date '+%Y%m%d-%H%M%S').log"

echo "✅ configure step complete for $NAME"