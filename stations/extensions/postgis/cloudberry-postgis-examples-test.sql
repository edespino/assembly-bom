-- PostGIS Examples from Cloudberry Documentation
-- Testing which examples cause crashes
-- https://cloudberry.apache.org/docs/advanced-analytics/postgis/

\echo '=== Starting PostGIS Examples Test ==='

-- Connect to a test database
DROP DATABASE IF EXISTS postgis_examples_test;
CREATE DATABASE postgis_examples_test;
\c postgis_examples_test

-- Enable PostGIS
CREATE EXTENSION postgis;

\echo '=== Example 1: Creating and Inserting Geometric Objects ==='

CREATE TABLE geom_test (
  gid int4,
  geom geometry,
  name varchar(25)
);

INSERT INTO geom_test (gid, geom, name)
  VALUES ( 1, 'POLYGON((0 0 0,0 5 0,5 5 0,5 0 0,0 0 0))', '3D Square');

INSERT INTO geom_test (gid, geom, name)
  VALUES ( 2, 'LINESTRING(1 1 1,5 5 5,7 7 5)', '3D Line');

INSERT INTO geom_test (gid, geom, name)
  VALUES ( 3, 'MULTIPOINT(3 4,8 9)', '2D Aggregate Point');

\echo '--- Testing spatial query with Box3D ---'
SELECT * from geom_test
WHERE geom && Box3D(ST_GeomFromEWKT('LINESTRING(2 2 0, 3 3 0)'));

\echo '=== Example 2: Geo-Referenced Data ==='

CREATE TABLE geotest (id INT4, name VARCHAR(32));

SELECT AddGeometryColumn('geotest','geopoint', 4326,'POINT',2);

INSERT INTO geotest (id, name, geopoint)
  VALUES (1, 'Olympia', ST_GeometryFromText('POINT(-122.90 46.97)', 4326));

INSERT INTO geotest (id, name, geopoint)
  VALUES (2, 'Renton', ST_GeometryFromText('POINT(-122.22 47.50)', 4326));

\echo '--- Testing spatial text output ---'
SELECT name, ST_AsText(geopoint) FROM geotest;

\echo '=== Example 3: Basic Spatial Operations ==='

CREATE TABLE spatial_data (
  id SERIAL PRIMARY KEY,
  geom geometry
);

INSERT INTO spatial_data (geom)
  VALUES
    (ST_GeomFromText('POINT(0 0)')),
    (ST_GeomFromText('POINT(1 1)')),
    (ST_GeomFromText('POLYGON((0 0, 4 0, 4 4, 0 4, 0 0))'));

\echo '--- Testing basic geometry queries ---'
SELECT id, ST_AsText(geom) FROM spatial_data;

\echo '=== Test Complete ==='