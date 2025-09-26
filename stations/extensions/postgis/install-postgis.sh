#!/bin/sh
# --------------------------------------------------------------------
# File     : stations/extensions/postgis/install-postgis.sh
# Purpose  : Install step for PostGIS extension
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

echo "==> Installing $NAME..."
echo "    Working directory: $POSTGIS_BUILD_DIR"

# Install with parallel jobs
NPROC=$(nproc 2>/dev/null || echo 4)
echo "    Using $NPROC parallel jobs"

INSTALL_LOG="install-$(date '+%Y%m%d-%H%M%S').log"
sudo make -j"$NPROC" install 2>&1 | tee "$INSTALL_LOG"

# Save PostGIS extensions for final summary only
if command -v psql >/dev/null 2>&1; then
  # Write extensions to a marker file that the final summary can find
  EXTENSIONS_MARKER="/tmp/claude_postgis_extensions.marker"
  echo "# PostGIS Extensions Data" > "$EXTENSIONS_MARKER"
  psql -q -P pager=off template1 -c \
    "SELECT
       name,
       default_version,
       installed_version,
       CASE WHEN installed_version IS NOT NULL THEN 'INSTALLED' ELSE 'AVAILABLE' END as status
     FROM pg_available_extensions
     WHERE name LIKE '%postgis%'
        OR name LIKE '%address%'
        OR name LIKE '%tiger%'
        OR name IN ('fuzzystrmatch')
     ORDER BY name;" >> "$EXTENSIONS_MARKER" 2>/dev/null
fi

echo "✅ install step complete for $NAME"