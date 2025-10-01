#!/bin/sh
# --------------------------------------------------------------------
# File     : stations/dependencies/sfcgal/install-sfcgal.sh
# Purpose  : Install step for SFCGAL library
# Inputs   :
#   - NAME              : component name (should be "sfcgal")
# --------------------------------------------------------------------

set -e

[ -f config/env.sh ] && . config/env.sh

# Validate input
if [ -z "$NAME" ]; then
  echo "Error: NAME is not set"
  exit 1
fi

# Navigate to SFCGAL build directory
SFCGAL_BUILD_DIR="$PARTS_DIR/$NAME/SFCGAL-v1.4.1/build"
cd "$SFCGAL_BUILD_DIR" || {
  echo "Error: Directory '$SFCGAL_BUILD_DIR' not found"
  exit 1
}

echo "==> Installing $NAME..."
echo "    Working directory: $SFCGAL_BUILD_DIR"

# Install with parallel jobs
NPROC=$(nproc 2>/dev/null || echo 4)
echo "    Using $NPROC parallel jobs"

sudo make -j"$NPROC" install 2>&1 | tee "install-$(date '+%Y%m%d-%H%M%S').log"

echo "✅ install step complete for $NAME"