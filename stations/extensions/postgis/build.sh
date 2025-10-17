#!/bin/sh
# --------------------------------------------------------------------
# File     : stations/extensions/postgis/build.sh
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

# Debug: Show environment CFLAGS if set
if [ -n "${CFLAGS:-}" ]; then
  echo "    Environment CFLAGS: ${CFLAGS}"
  echo "    Passing to make as CFLAGS_EXTRA"
  make -j"$NPROC" CFLAGS_EXTRA="${CFLAGS}" 2>&1 | tee "build-$(date '+%Y%m%d-%H%M%S').log"
else
  make -j"$NPROC" 2>&1 | tee "build-$(date '+%Y%m%d-%H%M%S').log"
fi

# Apply patch for Cloudberry-specific test filtering and plpython3u fix
# Determine script directory (works for both direct execution and sourcing)
if [ -n "${BASH_SOURCE[0]:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
PATCH_FILE="${SCRIPT_DIR}/postgis-cloudberry-test-filters.patch"

if [ -f "$PATCH_FILE" ]; then
  # Check if patch is already applied by looking for Cloudberry-specific filtering
  if grep -q "# Cloudberry-specific filtering" regress/run_test.pl 2>/dev/null; then
    echo "    PostGIS Cloudberry test filters already applied"
  else
    echo "    Applying PostGIS Cloudberry test filters and template1 fix..."
    patch -p1 < "$PATCH_FILE" || {
      echo "Warning: Failed to apply PostGIS Cloudberry test filter patch"
      echo "This may cause test failures due to autovacuum warnings and error message format differences"
    }
  fi
else
  echo "Warning: PostGIS Cloudberry test filter patch not found at $PATCH_FILE"
fi

echo "✅ build step complete for $NAME"