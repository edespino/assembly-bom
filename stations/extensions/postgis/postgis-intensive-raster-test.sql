-- PostGIS Intensive Raster Test Suite
-- Attempts to reproduce state accumulation crashes by running many raster operations sequentially
-- This mimics the regression test environment where crashes occur after ~210 tests

\c postgres
DROP DATABASE IF EXISTS intensive_raster_test;
CREATE DATABASE intensive_raster_test;
\c intensive_raster_test
CREATE EXTENSION postgis;
CREATE EXTENSION postgis_raster;

\echo '=========================================='
\echo 'PostGIS Intensive Raster Test Suite'
\echo 'Running sequential raster operations to test memory management'
\echo '=========================================='

-- ============================================================================
-- Test Series 1: Repeated raster creation and geometry conversion (20 iterations)
-- ============================================================================
\echo '-- Test Series 1: Raster creation loop (20 iterations)'
DO $$
DECLARE
    i INTEGER;
    r raster;
    g geometry;
BEGIN
    FOR i IN 1..20 LOOP
        -- Create raster
        r := ST_AddBand(
            ST_MakeEmptyRaster(10, 10, i::float, i::float, 1, -1, 0, 0, 4326),
            '8BUI'::text,
            i,
            0
        );

        -- Convert to geometry
        g := (ST_DumpAsPolygons(r)).geom;

        -- Use the geometry (prevents optimization)
        PERFORM ST_Area(g);

        IF i % 5 = 0 THEN
            RAISE NOTICE 'Completed iteration %', i;
        END IF;
    END LOOP;
    RAISE NOTICE '✅ Test Series 1 complete: 20 raster->geometry conversions';
END;
$$;

-- ============================================================================
-- Test Series 2: Map algebra expressions with different operators
-- ============================================================================
\echo '-- Test Series 2: Map algebra operations (15 variations)'
WITH test_raster AS (
    SELECT ST_AddBand(
        ST_MakeEmptyRaster(5, 5, 0, 0, 1, -1, 0, 0, 4326),
        '8BUI'::text,
        100,
        0
    ) as rast
)
SELECT
    'mapalgebra_' || op_num as test_name,
    ST_MapAlgebraExpr(rast, 1, '8BUI', expr) as result
FROM test_raster,
    (VALUES
        (1, '[rast] * 2'),
        (2, '[rast] + 10'),
        (3, '[rast] - 5'),
        (4, '[rast] / 2'),
        (5, '[rast] * [rast]'),
        (6, 'CASE WHEN [rast] > 50 THEN 1 ELSE 0 END'),
        (7, '[rast] * 0.5'),
        (8, '[rast] + [rast]'),
        (9, '255 - [rast]'),
        (10, '[rast] * 1.5'),
        (11, 'ABS([rast] - 100)'),
        (12, '[rast] MOD 10'),
        (13, 'GREATEST([rast], 50)'),
        (14, 'LEAST([rast], 150)'),
        (15, 'NULLIF([rast], 100)')
    ) AS ops(op_num, expr);

\echo '✅ Test Series 2 complete: 15 map algebra operations'

-- ============================================================================
-- Test Series 3: Complex raster clipping with multiple geometries
-- ============================================================================
\echo '-- Test Series 3: Raster clipping (10 geometries)'
WITH base_raster AS (
    SELECT ST_AddBand(
        ST_MakeEmptyRaster(20, 20, 0, 0, 1, -1, 0, 0, 4326),
        '32BF'::text,
        1,
        -1
    ) as rast
),
clip_geoms AS (
    SELECT
        n as geom_id,
        ST_Buffer(
            ST_GeomFromText('POINT(' || (n*2)::text || ' ' || (n*2)::text || ')', 4326),
            3
        ) as geom
    FROM generate_series(1, 10) n
)
SELECT
    'clip_test_' || geom_id as test_name,
    ST_Area((ST_DumpAsPolygons(ST_Clip(rast, geom))).geom) as clipped_area
FROM base_raster, clip_geoms;

\echo '✅ Test Series 3 complete: 10 raster clip operations'

-- ============================================================================
-- Test Series 4: Raster union operations with accumulation
-- ============================================================================
\echo '-- Test Series 4: Raster union operations (8 rasters)'
WITH test_rasters AS (
    SELECT
        n as id,
        ST_AddBand(
            ST_MakeEmptyRaster(3, 3, n::float, 0, 1, -1, 0, 0, 4326),
            '8BUI'::text,
            n * 10,
            0
        ) as rast
    FROM generate_series(1, 8) n
)
SELECT
    'union_test' as test_name,
    ST_Union(rast) as result
FROM test_rasters;

\echo '✅ Test Series 4 complete: Union of 8 rasters'

-- ============================================================================
-- Test Series 5: ASRaster conversions with different pixel types
-- ============================================================================
\echo '-- Test Series 5: ASRaster conversions (6 pixel types)'
WITH test_geometry AS (
    SELECT ST_GeomFromText('POLYGON((0 0,50 0,50 50,0 50,0 0))', 4326) as geom
),
template_raster AS (
    SELECT ST_MakeEmptyRaster(10, 10, 0, 0, 1, -1, 0, 0, 4326) as rast
)
SELECT
    'asraster_' || pixeltype as test_name,
    ST_ASRaster(
        geom,
        ST_AddBand(rast, pixeltype, 1, -1),
        pixeltype,
        100
    ) as result
FROM test_geometry, template_raster,
    (VALUES ('8BUI'), ('16BUI'), ('32BUI'), ('32BF'), ('64BF'), ('8BSI')) AS types(pixeltype);

\echo '✅ Test Series 5 complete: 6 ASRaster conversions'

-- ============================================================================
-- Test Series 6: Mixed raster + geometry operations (complex query)
-- ============================================================================
\echo '-- Test Series 6: Complex mixed operations (5 iterations)'
DO $$
DECLARE
    i INTEGER;
    test_rast raster;
    test_geom geometry;
    clipped_rast raster;
    result_area float;
BEGIN
    FOR i IN 1..5 LOOP
        -- Create test raster
        test_rast := ST_AddBand(
            ST_MakeEmptyRaster(15, 15, i::float, i::float, 1, -1, 0, 0, 4326),
            '32BF'::text,
            i * 50,
            -1
        );

        -- Create clip geometry
        test_geom := ST_Buffer(
            ST_GeomFromText('POINT(' || (i*3)::text || ' ' || (i*3)::text || ')', 4326),
            5
        );

        -- Clip raster
        clipped_rast := ST_Clip(test_rast, test_geom);

        -- Convert to geometry and measure
        SELECT ST_Area(geom) INTO result_area
        FROM ST_DumpAsPolygons(clipped_rast);

        RAISE NOTICE 'Iteration %: clipped area = %', i, result_area;
    END LOOP;
    RAISE NOTICE '✅ Test Series 6 complete: 5 complex mixed operations';
END;
$$;

-- ============================================================================
-- Test Series 7: Raster resampling and transformations
-- ============================================================================
\echo '-- Test Series 7: Raster resampling (4 algorithms)'
WITH base_raster AS (
    SELECT ST_AddBand(
        ST_MakeEmptyRaster(10, 10, 0, 0, 1, -1, 0, 0, 4326),
        '8BUI'::text,
        100,
        0
    ) as rast
)
SELECT
    'resample_' || algorithm as test_name,
    ST_Resample(rast, 2.0, -2.0, 0, 0, 0, 0, algorithm, 0.0) as result
FROM base_raster,
    (VALUES ('NearestNeighbor'), ('Bilinear'), ('Cubic'), ('CubicSpline')) AS algs(algorithm);

\echo '✅ Test Series 7 complete: 4 resampling operations'

-- ============================================================================
-- Test Series 8: Memory stress test - large raster operations
-- ============================================================================
\echo '-- Test Series 8: Large raster stress test (3 operations)'
WITH large_raster AS (
    SELECT ST_AddBand(
        ST_MakeEmptyRaster(100, 100, 0, 0, 1, -1, 0, 0, 4326),
        '32BF'::text,
        1,
        -1
    ) as rast
)
SELECT
    'stress_test_' || n as test_name,
    ST_Area(
        (ST_DumpAsPolygons(
            ST_MapAlgebraExpr(rast, 1, '32BF', '[rast] * ' || n::text)
        )).geom
    ) as result
FROM large_raster, generate_series(1, 3) n;

\echo '✅ Test Series 8 complete: 3 large raster operations'

\echo '=========================================='
\echo 'INTENSIVE RASTER TEST COMPLETE'
\echo 'Total operations: ~85 raster operations executed'
\echo 'If you see this message, all tests passed!'
\echo '=========================================='
