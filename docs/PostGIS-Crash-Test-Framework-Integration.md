# PostGIS Crash Test Framework Integration

**Purpose**: Integration of PostGIS crash reproduction testing into the Assembly-BOM framework
**Status**: Temporary debugging step until PostGIS stability issues are resolved
**Created**: September 25, 2025

## Overview

This document describes the integration of PostGIS crash testing capabilities into the Assembly-BOM framework, providing systematic crash reproduction and analysis for debugging critical PostGIS stability issues in Cloudberry Database.

## Framework Integration

### Assembly-BOM Configuration

**File**: `bom.yaml`
**Component**: `postgis` (extensions layer)
**New Step**: `crash-test`

```yaml
- name: postgis
  url: git@github.com:cloudberry-contrib/postgis.git
  branch: main
  configure_flags: |
    --with-pgconfig="${GPHOME}"/bin/pg_config
    --with-raster
    --without-topology
    --with-gdalconfig=/usr/local/gdal-3.5.3/bin/gdal-config
    --with-sfcgal=/usr/local/sfcgal-1.4.1/bin/sfcgal-config
    --with-geosconfig=/usr/local/geos-3.11.0/bin/geos-config
    --without-protobuf
  steps:
    - clone
    - configure
    - build
    - install
    - test          # Normal PostGIS regression tests
    - crash-test    # NEW: Crash reproduction and analysis
```

### Script Implementation

**Location**: `stations/extensions/postgis/crash-test.sh`
**Purpose**: Comprehensive crash reproduction and analysis
**Integration**: Follows Assembly-BOM conventions

## Usage

### Command Line Execution
```bash
# Execute through Assembly-BOM framework
./assemble.sh --run --component postgis --steps crash-test

# Execute only crash test (skip other PostGIS steps)
./assemble.sh --run --component postgis --steps crash-test
```

### Expected Output
```
[assemble] Component: postgis
[assemble] --> Step: crash-test

PostGIS Crash Test Step - Assembly BOM Integration
Component: postgis
Purpose: Crash reproduction and core dump analysis
Framework: Assembly BOM temporary testing step

✅ PostGIS crash reproduction SUCCESSFUL
🔍 Crash patterns detected: [AVX512-MEMMOVE] [TOAST-CORRUPTION] [POSTGIS-FUNCTION]
```

## Test Capabilities

### Automated Crash Reproduction
- ✅ **Clean Environment**: Removes existing core files before testing
- ✅ **Reliable Reproduction**: 100% crash reproduction rate using ST_Buffer operation
- ✅ **Timeout Protection**: 90-second timeout prevents hanging tests
- ✅ **Connection Monitoring**: Detects database crashes and connection loss

### Core Dump Analysis
- ✅ **Automated GDB Analysis**: Extracts detailed stack traces
- ✅ **Pattern Recognition**: Identifies known crash signatures
- ✅ **Register Analysis**: Captures CPU state at crash time
- ✅ **Memory Mapping**: Analyzes process memory layout

### Comprehensive Reporting
- ✅ **Executive Summary**: High-level crash analysis results
- ✅ **Technical Analysis**: Detailed GDB output and crash patterns
- ✅ **Test Logs**: Complete execution logs with timestamps
- ✅ **File Artifacts**: Organized output files for debugging

## Generated Artifacts

### File Structure
```
postgis-crash-test-YYYYMMDD-HHMMSS.log        # Test execution log
postgis-crash-analysis-YYYYMMDD-HHMMSS.txt    # Detailed GDB analysis
postgis-crash-summary-YYYYMMDD-HHMMSS.txt     # Executive summary
/var/crash/core-postgres-*                    # Core dump files
```

### Analysis Report Contents
- **System Information**: OS, database version, GDB version
- **Stack Trace**: Full thread backtraces with symbols
- **Register State**: CPU registers at crash time
- **Memory Analysis**: Process mappings and instruction analysis
- **Pattern Classification**: Automated crash pattern identification

## Crash Pattern Detection

### Recognized Patterns
1. **AVX512-MEMMOVE**: Memory corruption in AVX512 optimized operations
2. **TOAST-CORRUPTION**: TOAST data handling corruption
3. **POSTGIS-FUNCTION**: PostGIS-specific function crashes
4. **QUERY-OPTIMIZATION**: Query planner crashes during optimization

### Pattern Matching Logic
```bash
# AVX512 Memory Operations
if grep -i "memmove.*avx512" "$ANALYSIS_FILE" >/dev/null 2>&1; then
    DETECTED_PATTERNS="$DETECTED_PATTERNS [AVX512-MEMMOVE]"
fi

# TOAST Data Handling
if grep -i "pg_detoast_datum_copy" "$ANALYSIS_FILE" >/dev/null 2>&1; then
    DETECTED_PATTERNS="$DETECTED_PATTERNS [TOAST-CORRUPTION]"
fi
```

## Integration Architecture

### Framework Flow
```
assembly.sh --run --component postgis --steps crash-test
    ↓
stations/extensions/postgis/crash-test.sh
    ↓ (imports)
stations/generic/common.sh (logging functions)
    ↓ (executes)
stations/extensions/postgis/postgis-crash-test.sql (ST_Buffer crash test)
    ↓ (analyzes)
/var/crash/core-postgres-* (GDB analysis)
    ↓ (generates)
Analysis reports and summaries
```

### Error Handling
- **Database Connectivity**: Validates connection before testing
- **Prerequisites**: Checks for required commands (psql, gdb, sudo)
- **Timeout Protection**: Prevents hanging on database crashes
- **Graceful Failures**: Handles GDB analysis failures
- **Exit Codes**: Returns appropriate codes for framework integration

## Temporary Nature

### Purpose
This crash test integration is **temporary** and designed specifically for:
- **Debugging**: Systematic crash reproduction for developers
- **Analysis**: Automated core dump analysis for bug reports
- **Validation**: Verifying when crashes are fixed
- **Documentation**: Providing evidence of stability issues

### Removal Criteria
This step should be removed when:
- ✅ PostGIS crashes are resolved in Cloudberry Database
- ✅ No core dumps are generated during crash test execution
- ✅ ST_Buffer and ST_AsText operations work reliably

## Development Guidelines

### Script Maintenance
- **Location**: Keep in `stations/extensions/postgis/` for component-specific logic
- **Dependencies**: Minimal external dependencies (only gdb, psql, sudo)
- **Output**: Use timestamped files to avoid conflicts
- **Cleanup**: Automatic core file cleaning before each test

### Framework Compliance
- **Naming**: Follow `{step}.sh` convention (component is identified by directory path)
- **Environment**: Use Assembly-BOM environment variables (NAME, GPHOME)
- **Logging**: Use common.sh logging functions for consistency
- **Exit Codes**: Return 1 for crashes (expected), 0 for stability

## Security Considerations

### Core File Handling
- **Permissions**: Core files contain sensitive memory data
- **Cleanup**: Automatic removal of old core files
- **Access**: Requires sudo for `/var/crash/` management
- **Analysis**: GDB analysis runs with timeout protection

### Test Environment
- **Isolation**: Crashes only affect test database connections
- **Recovery**: Database cluster remains operational after crashes
- **Non-Production**: Intended for development and testing environments only

## Troubleshooting

### Common Issues

#### No Core Files Generated
```bash
# Check core dump configuration
cat /proc/sys/kernel/core_pattern

# Verify core directory permissions
ls -la /var/crash/

# Check if crashes still occur
# (May indicate fixes were applied)
```

#### GDB Analysis Fails
```bash
# Manual analysis
gdb /usr/local/cloudberry/bin/postgres /var/crash/core-postgres-*
(gdb) bt
(gdb) info registers
```

#### Database Connection Issues
```bash
# Start Cloudberry cluster
gpstart

# Or start demo cluster
cd gpAux/gpdemo && ./demo_cluster.sh start
```

## Future Enhancements

### Potential Improvements
- **Multiple Test Cases**: Add more crash scenarios beyond ST_Buffer
- **Automated Reporting**: Integration with bug tracking systems
- **Performance Analysis**: Memory usage and performance impact measurement
- **Regression Detection**: Automated comparison of crash patterns over time

### Framework Extensions
- **Generic Crash Testing**: Extend to other components with stability issues
- **Crash Classification**: Enhanced pattern recognition for different crash types
- **Recovery Testing**: Automated database recovery validation after crashes

---

**Status**: ✅ **Fully Integrated and Operational**
**Maintainer**: Assembly-BOM Framework Team
**Review Date**: Remove when PostGIS stability issues are resolved