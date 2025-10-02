#!/bin/sh
# --------------------------------------------------------------------
# File     : stations/extensions/postgis/configure.sh
# Purpose  : Configure step for PostGIS extension
# Inputs   :
#   - NAME              : component name (should be "postgis")
#   - CONFIGURE_FLAGS   : flags from bom.yaml
#   - INSTALL_PREFIX    : defaults to /usr/local/$NAME
# --------------------------------------------------------------------

set -e

[ -f config/env.sh ] && . config/env.sh

# Validate input
if [ -z "$NAME" ]; then
  echo "Error: NAME is not set"
  exit 1
fi

# Navigate to PostGIS build directory
POSTGIS_BUILD_DIR="$PARTS_DIR/$NAME/postgis/build/postgis-3.3.2"
cd "$POSTGIS_BUILD_DIR" || {
  echo "Error: Directory '$POSTGIS_BUILD_DIR' not found"
  exit 1
}

INSTALL_PREFIX="${INSTALL_PREFIX:-/usr/local/$NAME}"

echo "==> Configuring $NAME..."
echo "    Working directory: $POSTGIS_BUILD_DIR"
echo "    INSTALL_PREFIX=$INSTALL_PREFIX"
echo "    CONFIGURE_FLAGS:"
echo "$CONFIGURE_FLAGS"

# Run autogen.sh first (PostGIS-specific requirement)
echo "    Running autogen.sh..."
./autogen.sh 2>&1 | tee "autogen-$(date '+%Y%m%d-%H%M%S').log"

# Build configure command without prefix (PostGIS installs to PostgreSQL directories)
CMD="./configure $CONFIGURE_FLAGS"

echo "    Running: $CMD"
# shellcheck disable=SC2086
eval $CMD 2>&1 | tee "configure-$(date '+%Y%m%d-%H%M%S').log"

echo "✅ configure step complete for $NAME"