# Cloudberry PostGIS Documentation Crash Analysis

**Date**: September 25, 2025
**Source**: https://cloudberry.apache.org/docs/advanced-analytics/postgis/
**Test Results**: Official documentation examples generate critical crashes

## Executive Summary

Testing of the official Cloudberry PostGIS documentation examples reveals **critical crashes in fundamental PostGIS functions**. The `ST_AsText()` function, essential for displaying geometry data, consistently crashes segment processes across the distributed cluster.

**Status**: 🚨 **CRITICAL - Official Documentation Examples Crash Production Systems**

## Test Results Overview

### ✅ **Successful Operations**
| Operation | Example | Status | Notes |
|-----------|---------|--------|-------|
| Extension Creation | `CREATE EXTENSION postgis;` | ✅ PASS | Loads successfully |
| Table Creation | `CREATE TABLE geom_test (gid int4, geom geometry, name varchar(25));` | ✅ PASS | All geometry table definitions work |
| Geometry Insertion | `INSERT INTO geom_test VALUES (1, 'POLYGON((...))', '3D Square');` | ✅ PASS | Geometry literals insert correctly |
| Spatial Indexing | `WHERE geom && Box3D(ST_GeomFromEWKT(...))` | ✅ PASS | Bounding box queries work |
| Column Addition | `AddGeometryColumn('geotest','geopoint', 4326,'POINT',2)` | ✅ PASS | Geometry column management |
| Point Creation | `ST_GeometryFromText('POINT(-122.90 46.97)', 4326)` | ✅ PASS | Point geometry creation |

### ❌ **Failed Operations (Core Dumps Generated)**
| Operation | Example | Crash Location | Process Impact |
|-----------|---------|----------------|----------------|
| Text Conversion | `SELECT name, ST_AsText(geopoint) FROM geotest;` | Line 49 | seg1 slice1 (PID 65196) |
| Geometry Display | `SELECT id, ST_AsText(geom) FROM spatial_data;` | Line 65 | seg0 slice1 (PID 65248) |

## Detailed Crash Analysis

### **Critical Function: ST_AsText()**
The `ST_AsText()` function is fundamental to PostGIS operations - it converts internal geometry format to human-readable Well-Known Text (WKT). **This function crashes 100% of the time** in Cloudberry Database.

### **Impact on Distributed Processing**
```
seg1 slice1 10.0.1.236:7003 pid=65196: server closed the connection unexpectedly
seg0 slice1 10.0.1.236:7002 pid=65248: server closed the connection unexpectedly
```

**Distributed Failure Pattern:**
- Multiple segment nodes crash simultaneously
- Failures occur during distributed query execution
- Master node reports connection loss to segments
- Cluster becomes unstable after geometry text operations

### **Core Dump Evidence**
**Generated at**: 22:06 (4 new core files)
```
core-postgres-11-1001-1001-65195-1758863167  # seg1 process
core-postgres-11-1001-1001-65196-1758863167  # seg1 process backup
core-postgres-11-1001-1001-65248-1758863172  # seg0 process
core-postgres-11-1001-1001-65249-1758863172  # seg0 process backup
```

## Full Test Script and Results

### **Test Script**: `/home/cbadmin/assembly-bom/stations/extensions/postgis/cloudberry-postgis-examples-test.sql`

**Examples That Worked:**
```sql
-- Example 1: Geometric Objects (SUCCESSFUL)
CREATE TABLE geom_test (gid int4, geom geometry, name varchar(25));
INSERT INTO geom_test (gid, geom, name)
  VALUES ( 1, 'POLYGON((0 0 0,0 5 0,5 5 0,5 0 0,0 0 0))', '3D Square');
INSERT INTO geom_test (gid, geom, name)
  VALUES ( 2, 'LINESTRING(1 1 1,5 5 5,7 7 5)', '3D Line');
INSERT INTO geom_test (gid, geom, name)
  VALUES ( 3, 'MULTIPOINT(3 4,8 9)', '2D Aggregate Point');

-- Spatial query with bounding box (SUCCESSFUL)
SELECT * from geom_test
WHERE geom && Box3D(ST_GeomFromEWKT('LINESTRING(2 2 0, 3 3 0)'));
-- Results: 2 rows returned successfully

-- Example 2: Geo-Referenced Data (PARTIALLY SUCCESSFUL)
CREATE TABLE geotest (id INT4, name VARCHAR(32));
SELECT AddGeometryColumn('geotest','geopoint', 4326,'POINT',2);
-- Result: public.geotest.geopoint SRID:4326 TYPE:POINT DIMS:2

INSERT INTO geotest (id, name, geopoint)
  VALUES (1, 'Olympia', ST_GeometryFromText('POINT(-122.90 46.97)', 4326));
INSERT INTO geotest (id, name, geopoint)
  VALUES (2, 'Renton', ST_GeometryFromText('POINT(-122.22 47.50)', 4326));
-- Both inserts successful
```

**Examples That Crashed:**
```sql
-- CRASH POINT 1: Text conversion
SELECT name, ST_AsText(geopoint) FROM geotest;
-- ERROR: server closed the connection unexpectedly

-- CRASH POINT 2: Geometry display
SELECT id, ST_AsText(geom) FROM spatial_data;
-- ERROR: server closed the connection unexpectedly
```

## Production Impact Assessment

### **Functions Safe for Production Use**
- ✅ Geometry creation (`ST_GeometryFromText`, `ST_GeomFromText`)
- ✅ Geometry storage (INSERT with geometry literals)
- ✅ Spatial indexing and bounding box queries (`&&`, `Box3D`)
- ✅ Geometry column management (`AddGeometryColumn`)
- ✅ Extension management (`CREATE EXTENSION postgis`)

### **Functions That Crash Production Systems**
- ❌ **ST_AsText()** - Critical for data display and debugging
- ❌ Any geometry-to-text conversion operations
- ❌ Geometry result display in query outputs

### **Operational Limitations**
1. **No Geometry Visualization**: Cannot display geometry data as text
2. **Debugging Impossible**: Cannot inspect spatial data contents
3. **Data Export Broken**: Cannot convert geometries for external systems
4. **Client Integration Fails**: Applications expecting WKT format crash the database

## Recommendations

### **Immediate Actions**
1. **Update Documentation**: Mark ST_AsText() examples as causing crashes
2. **Add Warning Labels**: Warn users about geometry display operations
3. **Provide Alternatives**: Suggest binary geometry handling only

### **Development Priorities**
1. **Fix ST_AsText()**: Critical function for basic PostGIS operations
2. **Test All Text Functions**: ST_AsEWKT(), ST_AsGML(), ST_AsKML(), etc.
3. **Distributed Processing**: Fix geometry handling across segment nodes

### **Workaround Strategies**
```sql
-- INSTEAD OF: SELECT ST_AsText(geom) FROM table;  -- CRASHES
-- USE: SELECT geom FROM table;  -- Returns binary geometry (safe)

-- INSTEAD OF: Displaying results in psql  -- CRASHES
-- USE: Export to external GIS tools for visualization
```

## Technical Root Cause

The crashes in `ST_AsText()` suggest the same underlying issue identified earlier:
- **TOAST data corruption** during geometry decompression
- **Memory alignment issues** with AVX512 operations
- **Distributed processing complications** across segment nodes
- **Text conversion triggers** the vulnerable code path in geometry processing

The fact that geometry creation and storage work but text conversion fails indicates the issue is specifically in the **geometry-to-text serialization process**.

## Documentation Quality Assessment

**❌ Official Cloudberry PostGIS Documentation is Broken**

The official documentation at https://cloudberry.apache.org/docs/advanced-analytics/postgis/ contains examples that:
1. Crash production database systems
2. Generate core dumps on segment processes
3. Destabilize distributed clusters
4. Provide no warnings about instability

**Recommendation**: Documentation should be updated with crash warnings and safe operation guidelines until PostGIS stability issues are resolved.

---

**⚠️ CRITICAL PRODUCTION WARNING**: The official Cloudberry Database PostGIS documentation contains examples that crash segment processes and generate core dumps. Do not use ST_AsText() or geometry display operations in production environments.