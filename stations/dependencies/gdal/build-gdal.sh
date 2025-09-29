#!/bin/sh
# --------------------------------------------------------------------
# File     : stations/dependencies/gdal/build-gdal.sh
# Purpose  : Build step for GDAL library
# Inputs   :
#   - NAME              : component name (should be "gdal")
# --------------------------------------------------------------------

set -e

[ -f config/env.sh ] && . config/env.sh

# Validate input
if [ -z "$NAME" ]; then
  echo "Error: NAME is not set"
  exit 1
fi

# Navigate to GDAL extracted directory
GDAL_EXTRACT_DIR="$PARTS_DIR/$NAME/gdal-3.5.3"
cd "$GDAL_EXTRACT_DIR" || {
  echo "Error: Directory '$GDAL_EXTRACT_DIR' not found"
  exit 1
}

echo "==> Building $NAME..."
echo "    Working directory: $GDAL_EXTRACT_DIR"

# Build with parallel jobs
NPROC=$(nproc 2>/dev/null || echo 4)
echo "    Using $NPROC parallel jobs"

make -j"$NPROC" 2>&1 | tee "build-$(date '+%Y%m%d-%H%M%S').log"

echo "✅ build step complete for $NAME"