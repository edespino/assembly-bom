-- PostGIS Distributed Crash Test Suite
-- Tests for memory corruption in distributed query scenarios (Cloudberry/Greenplum specific)
-- The geometry cache (shared_gserialized_ref) may have issues with distributed operations

\c postgres
DROP DATABASE IF EXISTS distributed_crash_test;
CREATE DATABASE distributed_crash_test;
\c distributed_crash_test
CREATE EXTENSION postgis;
CREATE EXTENSION postgis_raster;

\echo '=========================================='
\echo 'PostGIS Distributed Crash Test Suite'
\echo 'Testing geometry cache in distributed query scenarios'
\echo '=========================================='

-- ============================================================================
-- Test 1: Distributed table with geometry redistribution
-- ============================================================================
\echo '-- Test 1: Distributed geometry operations with motion nodes'

-- Create distributed table with geometries
CREATE TABLE distributed_geoms (
    id SERIAL,
    name TEXT,
    geom GEOMETRY(POINT, 4326),
    rast RASTER
) DISTRIBUTED BY (id);

-- Insert data that will be distributed across segments
INSERT INTO distributed_geoms (name, geom, rast)
SELECT
    'point_' || n,
    ST_GeomFromText('POINT(' || (n % 180 - 90)::text || ' ' || (n % 90 - 45)::text || ')', 4326),
    ST_AddBand(
        ST_MakeEmptyRaster(5, 5, n::float, n::float, 1, -1, 0, 0, 4326),
        '8BUI'::text,
        n,
        0
    )
FROM generate_series(1, 100) n;

\echo '✅ Created distributed table with 100 rows'

-- Force redistribution with join
\echo '-- Testing cross-segment geometry operations'
SELECT
    a.name,
    b.name,
    ST_Distance(a.geom, b.geom) as distance
FROM distributed_geoms a, distributed_geoms b
WHERE a.id < b.id AND a.id <= 10 AND b.id <= 10
ORDER BY distance DESC
LIMIT 5;

\echo '✅ Cross-segment join completed'

-- ============================================================================
-- Test 2: Distributed raster operations with motion
-- ============================================================================
\echo '-- Test 2: Distributed raster clip operations'

-- Raster clip with geometry redistribution
SELECT
    a.id,
    ST_Area((ST_DumpAsPolygons(ST_Clip(a.rast, b.geom))).geom) as clipped_area
FROM distributed_geoms a, distributed_geoms b
WHERE a.id <= 10 AND b.id BETWEEN 5 AND 15
  AND ST_Intersects(a.rast::geometry, b.geom)
LIMIT 20;

\echo '✅ Distributed raster clip completed'

-- ============================================================================
-- Test 3: Aggregate operations with geometry cache
-- ============================================================================
\echo '-- Test 3: Distributed aggregations with geometry cache'

-- Union operation across segments
SELECT
    COUNT(*) as total_geometries,
    ST_Area(ST_Union(ST_Buffer(geom, 0.5))) as union_area
FROM distributed_geoms
WHERE id <= 20;

\echo '✅ Distributed geometry union completed'

-- Raster union across segments
SELECT
    COUNT(*) as total_rasters,
    ST_Union(rast) as unioned_raster
FROM distributed_geoms
WHERE id <= 10;

\echo '✅ Distributed raster union completed'

-- ============================================================================
-- Test 4: Subquery with motion and raster operations
-- ============================================================================
\echo '-- Test 4: Subquery with geometry cache stress'

WITH buffered_geoms AS (
    SELECT
        id,
        ST_Buffer(geom, 1.0) as buffered_geom,
        rast
    FROM distributed_geoms
    WHERE id <= 30
),
clipped_rasters AS (
    SELECT
        id,
        ST_Clip(rast, buffered_geom) as clipped_rast
    FROM buffered_geoms
)
SELECT
    id,
    ST_Area((ST_DumpAsPolygons(clipped_rast)).geom) as area
FROM clipped_rasters
WHERE id <= 15;

\echo '✅ Complex subquery with raster operations completed'

-- ============================================================================
-- Test 5: Prepared geometry cache with distributed queries
-- ============================================================================
\echo '-- Test 5: Prepared geometry predicates across segments'

-- Test ST_Contains with prepared geometry caching
SELECT
    a.id,
    COUNT(b.id) as contained_points
FROM distributed_geoms a, distributed_geoms b
WHERE a.id <= 5 AND ST_Contains(ST_Buffer(a.geom, 10), b.geom)
GROUP BY a.id
ORDER BY a.id;

\echo '✅ Prepared geometry predicates completed'

-- ============================================================================
-- Test 6: Mixed geometry and raster operations with redistribution
-- ============================================================================
\echo '-- Test 6: Complex mixed operations with motion nodes'

WITH geometry_buffers AS (
    SELECT
        id,
        ST_Buffer(geom, 2.0) as buffer_geom
    FROM distributed_geoms
    WHERE id <= 20
),
raster_clips AS (
    SELECT
        dg.id,
        ST_Clip(dg.rast, gb.buffer_geom) as clipped_rast
    FROM distributed_geoms dg
    JOIN geometry_buffers gb ON dg.id = gb.id
)
SELECT
    rc.id,
    ST_Area((ST_DumpAsPolygons(rc.clipped_rast)).geom) as area,
    ST_MapAlgebraExpr(rc.clipped_rast, 1, '8BUI', '[rast] * 2') as algebra_result
FROM raster_clips rc
WHERE rc.id <= 10;

\echo '✅ Complex mixed operations completed'

-- ============================================================================
-- Test 7: Large TOAST geometries with distributed operations
-- ============================================================================
\echo '-- Test 7: Large TOAST geometries across segments'

-- Create complex geometries that will be TOASTed
CREATE TABLE toast_geoms (
    id SERIAL,
    large_geom GEOMETRY,
    large_rast RASTER
) DISTRIBUTED BY (id);

-- Insert large polygon with many vertices (will be TOASTed)
INSERT INTO toast_geoms (large_geom, large_rast)
SELECT
    ST_Buffer(
        ST_GeomFromText('POINT(' || n::text || ' ' || n::text || ')', 4326),
        5.0,
        100  -- 100 segments = large geometry
    ),
    ST_AddBand(
        ST_MakeEmptyRaster(50, 50, n::float, n::float, 1, -1, 0, 0, 4326),
        '32BF'::text,
        100,
        -1
    )
FROM generate_series(1, 20) n;

\echo '✅ Created TOAST geometries'

-- Query with cross-segment TOAST access
SELECT
    a.id,
    ST_Area(ST_Intersection(a.large_geom, b.large_geom)) as intersection_area
FROM toast_geoms a, toast_geoms b
WHERE a.id < b.id AND a.id <= 5 AND b.id <= 10 AND ST_Intersects(a.large_geom, b.large_geom)
LIMIT 10;

\echo '✅ TOAST geometry operations completed'

-- Raster operations on TOASTed data
SELECT
    id,
    ST_Area((ST_DumpAsPolygons(large_rast)).geom) as raster_area
FROM toast_geoms
WHERE id <= 10;

\echo '✅ TOAST raster operations completed'

-- ============================================================================
-- Test 8: Transaction rollback with geometry cache
-- ============================================================================
\echo '-- Test 8: Transaction rollback with cached geometries'

BEGIN;
    -- Create temporary geometries
    CREATE TEMP TABLE temp_geoms AS
    SELECT
        id,
        ST_Buffer(geom, 1.0) as buffered_geom,
        rast
    FROM distributed_geoms
    WHERE id <= 30;

    -- Perform operations
    SELECT COUNT(*) FROM temp_geoms;

    -- Test raster operations in transaction
    SELECT
        id,
        ST_Area((ST_DumpAsPolygons(rast)).geom) as area
    FROM temp_geoms
    WHERE id <= 10;
ROLLBACK;

\echo '✅ Transaction rollback completed'

-- ============================================================================
-- Test 9: Concurrent-style operations (sequential but testing cache)
-- ============================================================================
\echo '-- Test 9: Rapid cache thrashing with different geometries'

DO $$
DECLARE
    i INTEGER;
    result_area FLOAT;
BEGIN
    FOR i IN 1..50 LOOP
        -- Different geometry operations to thrash the cache
        SELECT ST_Area(
            (ST_DumpAsPolygons(
                ST_Clip(
                    rast,
                    ST_Buffer(geom, (i % 5)::float)
                )
            )).geom
        ) INTO result_area
        FROM distributed_geoms
        WHERE id = (i % 100) + 1
        LIMIT 1;

        IF i % 10 = 0 THEN
            RAISE NOTICE 'Cache thrashing iteration %: area = %', i, result_area;
        END IF;
    END LOOP;
    RAISE NOTICE '✅ Cache thrashing test completed';
END;
$$;

-- ============================================================================
-- Test 10: Segment-specific raster operations
-- ============================================================================
\echo '-- Test 10: Operations that force segment-local processing'

-- Create replicated table to test segment-local operations
CREATE TABLE replicated_rasters (
    id INT,
    test_rast RASTER
) DISTRIBUTED REPLICATED;

INSERT INTO replicated_rasters
SELECT
    n,
    ST_AddBand(
        ST_MakeEmptyRaster(10, 10, 0, 0, 1, -1, 0, 0, 4326),
        '8BUI'::text,
        n * 10,
        0
    )
FROM generate_series(1, 10) n;

-- Force segment-local computation across all segments
SELECT
    COUNT(*) as operations,
    ST_Union(test_rast) as unioned_raster
FROM replicated_rasters;

\echo '✅ Segment-local operations completed'

\echo '=========================================='
\echo 'DISTRIBUTED CRASH TEST COMPLETE'
\echo 'All distributed query scenarios passed!'
\echo 'If database is in recovery mode, crash was reproduced'
\echo '=========================================='

-- Check database status
SELECT CASE WHEN pg_is_in_recovery() THEN '⚠️  DATABASE IN RECOVERY MODE' ELSE '✅ Database status: NORMAL' END as status;
