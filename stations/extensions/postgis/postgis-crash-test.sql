-- PostGIS Crash Test Suite
-- Tests for memory corruption issues in PostGIS geometry/raster operations

-- Connect to database and enable PostGIS
\c postgres
DROP DATABASE IF EXISTS crash_test;
CREATE DATABASE crash_test;
\c crash_test
CREATE EXTENSION postgis;
CREATE EXTENSION postgis_raster;

-- ============================================================================
-- Test 1: Simple geometry operation (previously crashed, now fixed)
-- ============================================================================
\echo '-- Test 1: ST_Buffer operation'
SELECT ST_AsText(ST_Buffer(ST_GeomFromText('POINT(0 0)', 4326), 0.1));

-- ============================================================================
-- Test 2: Raster + Geometry combination (memory corruption issue)
-- ============================================================================
\echo '-- Test 2: Complex raster clip with geometry (known to crash)'
-- This reproduces the crash from regression test #3457
-- Error: MemoryContextContains assertion failure in shared_gserialized_ref
SELECT
    'raster_clip_test' as test_name,
    ST_Area(
        (ST_DumpAsPolygons(
            ST_Clip(
                ST_ASRaster(
                    ST_GeomFromText('POLYGON((0 0,100 0,100 100,0 100,0 0))', 4326),
                    ST_Addband(
                        ST_MakeEmptyRaster(10, 10, 0, 0, 1, -1, 0, 0, 4326),
                        '32BF'::text,
                        1,
                        -1
                    ),
                    '32BF'::text,
                    100
                ),
                ST_GeomFromText('POLYGON((10 10,90 10,90 90,10 90,10 10))', 4326)
            )
        )).geom
    ) as area;

-- ============================================================================
-- Test 3: Simpler raster operation (may also crash)
-- ============================================================================
\echo '-- Test 3: Raster map algebra expression'
-- This reproduces crashes from rt_mapalgebraexpr tests
WITH raster_data AS (
    SELECT
        ST_AddBand(
            ST_MakeEmptyRaster(5, 5, 0, 0, 1, -1, 0, 0, 4326),
            '8BUI'::text,
            1,
            0
        ) as rast
)
SELECT
    'mapalgebra_test' as test_name,
    ST_MapAlgebraExpr(rast, 1, '8BUI', '[rast] * 2') as result
FROM raster_data;

-- ============================================================================
-- Test 4: Raster union operation (causes memory issues)
-- ============================================================================
\echo '-- Test 4: Raster union with geometry cache'
WITH test_rasters AS (
    SELECT 1 as id,
           ST_AddBand(ST_MakeEmptyRaster(2, 2, 0, 0, 1, -1, 0, 0, 4326), '8BUI'::text, 1, 0) as rast
    UNION ALL
    SELECT 2 as id,
           ST_AddBand(ST_MakeEmptyRaster(2, 2, 1, -1, 1, -1, 0, 0, 4326), '8BUI'::text, 2, 0) as rast
)
SELECT
    'union_test' as test_name,
    ST_Union(rast) as result
FROM test_rasters;

\echo '-- Crash test complete (if you see this, tests passed!)'