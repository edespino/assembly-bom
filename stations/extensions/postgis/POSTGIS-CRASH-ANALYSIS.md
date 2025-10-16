# PostGIS Memory Corruption Analysis

## Executive Summary

PostGIS 3.3.2 exhibits memory corruption issues in **distributed query scenarios** specific to Cloudberry Database / Greenplum. The root cause is the geometry cache (`shared_gserialized_ref`) incorrectly managing memory contexts during cross-segment operations.

## Crash Pattern Identification

### Symptoms
- **Error**: `FailedAssertion("false", File: "mcxt.c", Line: 933)`
- **Function**: `MemoryContextContains` assertion failure
- **Location**: PostGIS geometry cache in `shared_gserialized_ref`
- **Trigger**: Cross-segment distributed queries with geometry operations

### Reproduction Results

| Test Type | Status | Notes |
|-----------|--------|-------|
| Simple geometry operations | ✅ PASS | ST_Buffer, ST_AsText work correctly |
| Isolated raster operations | ✅ PASS | 85+ sequential operations complete |
| **Distributed geometry joins** | ❌ **CRASH** | ST_Contains with cross-segment data |
| **TOAST + distributed ops** | ❌ **CRASH** | ST_Intersection with large geometries |
| Non-distributed operations | ✅ PASS | All operations work on single segment |

## Root Cause Analysis

### Technical Details

**File**: `shared_gserialized.c`
**Function**: `shared_gserialized_ref`
**Issue**: Geometry cache holds references to memory allocated in different PostgreSQL memory contexts

**Failure Scenario**:
1. Query coordinator creates geometry in its memory context
2. Geometry is serialized and sent to segment server
3. Segment deserializes geometry into its local memory context
4. PostGIS geometry cache tries to validate memory context ownership
5. Assertion fails: cached pointer not in expected context

### Why Only Distributed Queries Fail

**Single-segment operations** (PostgreSQL, standalone operations):
- All memory allocated in same backend process
- Geometry cache correctly tracks memory contexts
- No context boundary crossings

**Distributed operations** (Cloudberry/Greenplum):
- Geometries cross process boundaries via motion nodes
- Memory contexts differ between coordinator and segments
- Cache assumes single-process memory model
- **Result**: `MemoryContextContains` assertion failure

## Test Files

### 1. Basic Crash Test
**File**: `stations/extensions/postgis/postgis-crash-test.sql`
**Purpose**: Validate basic geometry and raster operations
**Result**: ✅ All tests pass (no distributed operations)

### 2. Intensive Raster Test
**File**: `stations/extensions/postgis/postgis-intensive-raster-test.sql`
**Purpose**: Stress test with 85+ sequential raster operations
**Result**: ✅ All tests pass (single-session operations)

### 3. Distributed Crash Test ⚠️
**File**: `stations/extensions/postgis/postgis-distributed-crash-test.sql`
**Purpose**: Reproduce memory corruption in distributed scenarios
**Result**: ❌ **Successfully reproduces crash**

#### Specific Failure Points:

**Test 5** - Prepared geometry predicates:
```sql
SELECT a.id, COUNT(b.id) as contained_points
FROM distributed_geoms a, distributed_geoms b
WHERE a.id <= 5 AND ST_Contains(ST_Buffer(a.geom, 10), b.geom)
GROUP BY a.id;
```
**Error**: `FailedAssertion("false", File: "mcxt.c", Line: 933)` on seg0

**Test 7** - TOAST geometries with cross-segment intersection:
```sql
SELECT a.id, ST_Area(ST_Intersection(a.large_geom, b.large_geom))
FROM toast_geoms a, toast_geoms b
WHERE ST_Intersects(a.large_geom, b.large_geom);
```
**Error**: `FailedAssertion("false", File: "mcxt.c", Line: 933)` on seg2

## Upstream Issue

This is an **upstream PostGIS bug** specific to distributed PostgreSQL implementations (Greenplum, Cloudberry). The issue exists in:
- PostGIS geometry cache implementation
- Assumption of single-process memory management
- Lack of distributed query awareness

**Not fixable at Assembly BOM level** - requires PostGIS upstream changes to:
1. Detect distributed query environment
2. Disable geometry cache for cross-segment operations, OR
3. Implement distributed-safe caching mechanism

## Workarounds

### For Users

1. **Avoid cross-segment geometry joins** with complex predicates
2. **Disable parallel execution** for geometry operations:
   ```sql
   SET max_parallel_workers_per_gather = 0;
   ```
3. **Use replicated tables** for small geometry reference data
4. **Simplify geometries** before joins to avoid TOAST

### For Developers

1. **Test in distributed mode** - Single-node tests won't catch these issues
2. **Monitor for assertion failures** in segment logs
3. **Limit geometry cache usage** in distributed contexts

## Testing Recommendations

### Run Tests
```bash
# Basic validation (should pass)
./assemble.sh --run --component postgis -s crash-test

# Distributed crash reproduction (will fail on Tests 5 & 7)
source ~/bom-parts/cloudberry/gpAux/gpdemo/gpdemo-env.sh
psql -f stations/extensions/postgis/postgis-distributed-crash-test.sql
```

### Expected Results
- Basic crash test: ✅ All pass
- Intensive raster test: ✅ All pass
- Distributed crash test: ❌ Fails on Tests 5 & 7 (expected behavior)

## Impact Assessment

### Severity: **MEDIUM**

**Affected Operations**:
- ❌ Cross-segment geometry joins with spatial predicates
- ❌ Large TOAST geometries in distributed queries
- ❌ Aggregate operations across segments with geometry cache
- ✅ Single-segment queries (work correctly)
- ✅ Simple geometry operations (work correctly)
- ✅ Non-cached operations (work correctly)

### Production Impact:
- **Low** for read-only single-segment queries
- **Low** for simple geometry operations without joins
- **HIGH** for complex spatial analytics requiring cross-segment joins
- **HIGH** for applications using prepared geometry predicates

## Resolution Status

- ✅ **Root cause identified**: Geometry cache + distributed queries
- ✅ **Reproduction test created**: `postgis-distributed-crash-test.sql`
- ✅ **Workarounds documented**: Avoid cross-segment operations
- ❌ **Upstream fix required**: PostGIS needs distributed query awareness
- ⏸️ **Assembly BOM status**: Tests document known issues, no code fix possible

## Related Files

- `stations/extensions/postgis/postgis-crash-test.sql` - Basic validation
- `stations/extensions/postgis/postgis-intensive-raster-test.sql` - Stress testing
- `stations/extensions/postgis/postgis-distributed-crash-test.sql` - Crash reproduction
- `stations/extensions/postgis/crash-test.sh` - Test automation
- `CLAUDE.md` - Developer documentation with known issues

## References

- PostGIS Version: 3.3.2
- Cloudberry Version: 3.0.0-devel+dev.2138.g37fce691d3d
- GDB Backtrace: Core files in `/var/crash/`
- Assertion: `mcxt.c:933` in `MemoryContextContains`

---

**Last Updated**: 2025-10-15
**Status**: Documented, awaiting upstream PostGIS fix
