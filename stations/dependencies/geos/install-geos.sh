#!/bin/sh
# --------------------------------------------------------------------
# File     : stations/dependencies/geos/install-geos.sh
# Purpose  : Install step for GEOS library
# Inputs   :
#   - NAME              : component name (should be "geos")
# --------------------------------------------------------------------

set -e

[ -f config/env.sh ] && . config/env.sh

# Validate input
if [ -z "$NAME" ]; then
  echo "Error: NAME is not set"
  exit 1
fi

# Navigate to GEOS build directory
GEOS_BUILD_DIR="$PARTS_DIR/$NAME/geos-3.11.0/build"
cd "$GEOS_BUILD_DIR" || {
  echo "Error: Directory '$GEOS_BUILD_DIR' not found"
  exit 1
}

echo "==> Installing $NAME..."
echo "    Working directory: $GEOS_BUILD_DIR"

# Install with parallel jobs
NPROC=$(nproc 2>/dev/null || echo 4)
echo "    Using $NPROC parallel jobs"

sudo make -j"$NPROC" install 2>&1 | tee "install-$(date '+%Y%m%d-%H%M%S').log"

echo "✅ install step complete for $NAME"