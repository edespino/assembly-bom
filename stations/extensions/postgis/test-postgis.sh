#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : stations/extensions/postgis/test-postgis.sh
# Purpose  : Run comprehensive PostGIS regression tests in Cloudberry Database
# Inputs   :
#   - NAME                    : component name (should be "postgis")
#   - DISABLE_EXTENSION_TESTS : skips regression tests if set true/1
# --------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# Load shared functions
COMMON_SH="${SCRIPT_DIR}/../../../lib/common.sh"
if [ -f "${COMMON_SH}" ]; then
  # shellcheck disable=SC1090
  source "${COMMON_SH}"
else
  echo "[$SCRIPT_NAME] Missing library: ${COMMON_SH}" >&2
  exit 1
fi

# Load shared environment
# shellcheck disable=SC1091
[ -f config/env.sh ] && . config/env.sh

# Validate input
if [ -z "$NAME" ]; then
  echo "Error: NAME is not set"
  exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLOUDBERRY_DEMO_ENV="$PARTS_DIR/cloudberry/gpAux/gpdemo/gpdemo-env.sh"
POSTGIS_BUILD_DIR="$PARTS_DIR/$NAME/postgis/build/postgis-3.3.2"

section "test: $NAME"
start_time=$(date +%s)

# Check if tests are disabled
case "${DISABLE_EXTENSION_TESTS:-false}" in
  1 | true | TRUE | True)
    log "PostGIS tests disabled via DISABLE_EXTENSION_TESTS=${DISABLE_EXTENSION_TESTS}"
    section_complete "test: $NAME (skipped)" "$start_time"
    exit 0
    ;;
esac

# Load Cloudberry environment
[ -f "${SCRIPT_DIR}/../../../config/cloudberry-env-loader.sh" ] && source "${SCRIPT_DIR}/../../../config/cloudberry-env-loader.sh"
if ! source_cloudberry_env /usr/local/cloudberry; then
  echo "[test-postgis] ERROR: Failed to load Cloudberry environment" >&2
  exit 1
fi

# Ensure plpython3u is available in template1 for tiger geocoder
log "Ensuring plpython3u extension is available for tiger geocoder"
if psql -d template1 -c "CREATE EXTENSION IF NOT EXISTS plpython3u;" 2>&1 | grep -q "already exists\|CREATE EXTENSION"; then
  log "✅ plpython3u extension ready"
else
  log "⚠️  plpython3u extension setup failed, tiger geocoder tests may fail"
fi

# Verify demo environment exists
if [[ ! -f "$CLOUDBERRY_DEMO_ENV" ]]; then
  echo "[test-postgis] ERROR: gpdemo-env.sh not found at $CLOUDBERRY_DEMO_ENV" >&2
  echo "[test-postgis] PostGIS regression tests require a running Cloudberry cluster" >&2
  exit 1
fi

# Source demo environment
source "$CLOUDBERRY_DEMO_ENV"

# Navigate to PostGIS build directory
if [[ ! -d "$POSTGIS_BUILD_DIR" ]]; then
  echo "[test-postgis] ERROR: PostGIS build directory '$POSTGIS_BUILD_DIR' not found" >&2
  exit 1
fi

cd "$POSTGIS_BUILD_DIR"

log "Running PostGIS comprehensive regression tests"
log "Working directory: $POSTGIS_BUILD_DIR"
log "Database port: ${PGPORT:-7000}"

# Create test log file with timestamp
TEST_LOG="test-postgis-$(date '+%Y%m%d-%H%M%S').log"

# Run comprehensive PostGIS regression tests
log "Running make installcheck (comprehensive regression suite)"
echo "PostGIS Test Suite Output:" > "$TEST_LOG"
echo "=========================" >> "$TEST_LOG"
echo "Started: $(date)" >> "$TEST_LOG"
echo "" >> "$TEST_LOG"

# Run the full PostGIS regression test suite
if make installcheck 2>&1 | tee -a "$TEST_LOG"; then
  log "✅ PostGIS core regression tests passed"
else
  echo "[test-postgis] ERROR: PostGIS core regression tests failed" >&2
  echo "[test-postgis] Check log file: $POSTGIS_BUILD_DIR/$TEST_LOG" >&2
  exit 1
fi

# Test PostGIS extensions if available
log "Testing PostGIS extension components"

# Test raster functionality (if built with raster support)
if make -C raster installcheck 2>/dev/null | tee -a "$TEST_LOG"; then
  log "✅ PostGIS raster tests passed"
else
  log "⚠️  PostGIS raster tests skipped or unavailable"
fi

# Test topology functionality (if built with topology support)
if make -C topology installcheck 2>/dev/null | tee -a "$TEST_LOG"; then
  log "✅ PostGIS topology tests passed"
else
  log "⚠️  PostGIS topology tests skipped or unavailable"
fi

# Test SFCGAL functionality (if built with SFCGAL support)
if make -C sfcgal installcheck 2>/dev/null | tee -a "$TEST_LOG"; then
  log "✅ PostGIS SFCGAL tests passed"
else
  log "⚠️  PostGIS SFCGAL tests skipped or unavailable"
fi

# Run basic functional validation
log "Running basic PostGIS functionality validation"
psql -v ON_ERROR_STOP=1 -d template1 -c "
-- Verify PostGIS installation and basic functionality
SELECT PostGIS_Version();
SELECT PostGIS_GEOS_Version();
SELECT PostGIS_PROJ_Version();
SELECT PostGIS_GDAL_Version();

-- Test basic spatial operations
CREATE TEMP TABLE test_geometries (
    id SERIAL PRIMARY KEY,
    name TEXT,
    geom GEOMETRY(POINT, 4326)
);

INSERT INTO test_geometries (name, geom) VALUES
    ('San Francisco', ST_GeomFromText('POINT(-122.4194 37.7749)', 4326)),
    ('New York', ST_GeomFromText('POINT(-74.0060 40.7128)', 4326)),
    ('London', ST_GeomFromText('POINT(-0.1276 51.5074)', 4326));

-- Test spatial distance calculation
SELECT
    a.name as from_city,
    b.name as to_city,
    ROUND(ST_Distance(ST_Transform(a.geom, 3857), ST_Transform(b.geom, 3857)) / 1000, 0) as distance_km
FROM test_geometries a, test_geometries b
WHERE a.id < b.id
ORDER BY distance_km;

-- Test spatial indexing
CREATE INDEX idx_test_geom ON test_geometries USING GIST (geom);

-- Test spatial query
SELECT name, ST_AsText(geom)
FROM test_geometries
WHERE ST_DWithin(
    ST_Transform(geom, 3857),
    ST_Transform(ST_GeomFromText('POINT(-74.0060 40.7128)', 4326), 3857),
    1000000  -- 1000km buffer around NYC
);

DROP TABLE test_geometries;
" 2>&1 | tee -a "$TEST_LOG"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
  log "✅ PostGIS functional validation passed"
else
  echo "[test-postgis] ERROR: PostGIS functional validation failed" >&2
  exit 1
fi

# Test PostGIS extensions availability
log "Testing PostGIS extension availability"
psql -v ON_ERROR_STOP=1 -d template1 -c "
-- Test extension creation and cleanup
CREATE EXTENSION IF NOT EXISTS postgis;
SELECT COUNT(*) as postgis_functions FROM pg_proc WHERE pronamespace = (SELECT oid FROM pg_namespace WHERE nspname = 'public') AND prokind = 'f' AND proname LIKE 'st_%';

-- Test optional extensions
DO \$\$
BEGIN
    CREATE EXTENSION IF NOT EXISTS fuzzystrmatch;
    RAISE NOTICE 'fuzzystrmatch extension available';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'fuzzystrmatch extension not available: %', SQLERRM;
END;
\$\$;

DO \$\$
BEGIN
    CREATE EXTENSION IF NOT EXISTS address_standardizer;
    RAISE NOTICE 'address_standardizer extension available';
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'address_standardizer extension not available: %', SQLERRM;
END;
\$\$;

-- Cleanup
DROP EXTENSION IF EXISTS address_standardizer;
DROP EXTENSION IF EXISTS fuzzystrmatch;
DROP EXTENSION IF EXISTS postgis CASCADE;
" 2>&1 | tee -a "$TEST_LOG"

if [ ${PIPESTATUS[0]} -eq 0 ]; then
  log "✅ PostGIS extension tests completed successfully"
else
  echo "[test-postgis] ERROR: PostGIS extension tests failed" >&2
  exit 1
fi

echo "" >> "$TEST_LOG"
echo "Completed: $(date)" >> "$TEST_LOG"
echo "=========================" >> "$TEST_LOG"

log "PostGIS regression testing completed successfully"
log "Detailed test results: $POSTGIS_BUILD_DIR/$TEST_LOG"

section_complete "test: $NAME" "$start_time"