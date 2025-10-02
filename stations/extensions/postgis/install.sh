#!/bin/sh
# --------------------------------------------------------------------
# File     : stations/extensions/postgis/install.sh
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

# Save PostGIS extensions for final summary
echo ""
echo "==> Checking available extensions..."
if command -v psql >/dev/null 2>&1; then
  # Check if database is accessible
  if psql -q -P pager=off template1 -c "SELECT 1;" >/dev/null 2>&1; then
    echo "    ✓ Database is accessible"

    # Write extensions to a marker file that the final summary can find
    EXTENSIONS_MARKER="/tmp/claude_postgis_extensions.marker"
    echo "# PostGIS Extensions Data" > "$EXTENSIONS_MARKER"

    if psql -q -P pager=off template1 -c \
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
       ORDER BY name;" >> "$EXTENSIONS_MARKER" 2>&1; then

      # Count extensions found
      EXT_COUNT=$(grep -c '|' "$EXTENSIONS_MARKER" 2>/dev/null | awk '{print $1-1}' || echo "0")
      if [ "$EXT_COUNT" -gt 0 ]; then
        echo "    ✓ Found $EXT_COUNT PostGIS extension(s)"
        echo "    ℹ Extension summary will be displayed at end of full assembly"
      else
        echo "    ⚠ No PostGIS extensions found in pg_available_extensions"
      fi
    else
      echo "    ✗ Failed to query pg_available_extensions"
      echo "    ⚠ Extension summary will not be available"
    fi
  else
    echo ""
    echo "❌ ERROR: Database is not running or not accessible"
    echo "   → Start database with: ./assemble.sh -r -c cloudberry -s gpstart"
    echo "   → Extension summary will not be available until database is running"
    echo ""
  fi
else
  echo ""
  echo "❌ ERROR: psql command not found"
  echo "   → Extension summary will not be available"
  echo ""
fi

echo "✅ install step complete for $NAME"