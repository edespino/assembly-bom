#!/bin/sh
# --------------------------------------------------------------------
# File     : stations/extensions/postgis/build-postgis.sh
# Purpose  : Build step for PostGIS extension
# Inputs   :
#   - NAME              : component name (should be "postgis")
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

echo "==> Building $NAME..."
echo "    Working directory: $POSTGIS_BUILD_DIR"

# Build with parallel jobs
NPROC=$(nproc 2>/dev/null || echo 4)
echo "    Using $NPROC parallel jobs"

make -j"$NPROC" 2>&1 | tee "build-$(date '+%Y%m%d-%H%M%S').log"

# Apply patch to fix plpython3u dependency issue in regression tests
PATCH_FILE="$(dirname "$(readlink -f "$0")")/postgis-plpython-fix.patch"
if [ -f "$PATCH_FILE" ]; then
  echo "    Applying PostGIS regression test fix for plpython3u..."
  patch -p1 < "$PATCH_FILE" || {
    echo "Warning: Failed to apply PostGIS regression test patch"
    echo "This may cause tiger geocoder tests to fail"
  }
else
  echo "Warning: PostGIS regression test patch not found at $PATCH_FILE"
fi

echo "✅ build step complete for $NAME"