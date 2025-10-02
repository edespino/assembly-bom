#!/bin/sh
# --------------------------------------------------------------------
# File     : stations/dependencies/sfcgal/build.sh
# Purpose  : Build step for SFCGAL library
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

echo "==> Building $NAME..."
echo "    Working directory: $SFCGAL_BUILD_DIR"

# Build with parallel jobs
NPROC=$(nproc 2>/dev/null || echo 4)
echo "    Using $NPROC parallel jobs"

make -j"$NPROC" 2>&1 | tee "build-$(date '+%Y%m%d-%H%M%S').log"

echo "✅ build step complete for $NAME"