-- PostGIS Crash Test Case
-- This will reliably crash Cloudberry Database with SIGSEGV

-- Connect to database and enable PostGIS
\c postgres
DROP DATABASE IF EXISTS crash_test;
CREATE DATABASE crash_test;
\c crash_test
CREATE EXTENSION postgis;

-- Simple crash: ST_Buffer operation
SELECT ST_AsText(ST_Buffer(ST_GeomFromText('POINT(0 0)', 4326), 0.1));

-- Alternative crash: Polygon area calculation
-- SELECT ST_Area(ST_GeomFromText('POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))', 4326));

-- Alternative crash: Spatial relationship test
-- SELECT ST_Within(
--     ST_GeomFromText('POINT(0.5 0.5)', 4326),
--     ST_GeomFromText('POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))', 4326)
-- );