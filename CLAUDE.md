# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Assembly BOM is a Software Bill of Materials (SBOM) development tool for the Cloudberry Database ecosystem. See README.md for user documentation and architecture overview.

## AI Development Workflow

### Essential Commands for Development
```bash
# Lint and typecheck (run after code changes)
# NOTE: Check README or ask user for specific linting commands if not found

# Build validation
./assemble.sh --dry-run --component <component>

# Component debugging
./assemble.sh --run --component <component> --steps <step> --force
```

### Code Analysis and Modification Guidelines
- **Station Scripts**: Follow naming pattern `stations/{layer}/{component}/{step}-{component}.sh`
- **Generic Fallbacks**: Located in `stations/generic/` for common build patterns
- **Environment Setup**: Check `config/env.sh` for shared variables and paths
- **Component Definition**: All components defined in `bom.yaml` with steps, flags, and dependencies

## Critical System Dependencies

### PostGIS Geospatial Stack Requirements
```bash
# Critical packages for PostGIS dependency chain
sudo dnf install -y gmp-devel mpfr-devel sqlite-devel protobuf-c protobuf-c-devel
sudo dnf install -y libxslt docbook-style-xsl --enablerepo=epel
```

**Dependency Build Order** (essential for PostGIS):
```
CGAL 5.6.1 → SFCGAL 1.4.1 → GEOS 3.11.0 → PROJ 6.0.0 → GDAL 3.5.3 → PostGIS 3.3.2
```

**Key Technical Details**:
- **CGAL/SFCGAL**: Require GMP/MPFR for computational geometry
- **PROJ**: Uses SQLite for coordinate reference system database
- **PostGIS**: Uses modern pkg-config detection (PKG_CONFIG_PATH) instead of deprecated --with-projdir
- **Environment Paths**: Automatically configured in `config/env.sh` for library discovery

## PostGIS Development and Debugging

### Crash Testing Framework
PostGIS has known stability issues. The crash testing framework provides systematic reproduction:

**Files**:
- `stations/extensions/postgis/crash-test-postgis.sh` - Comprehensive crash reproduction
- `stations/extensions/postgis/postgis-crash-test.sql` - ST_Buffer crash scenario
- `stations/extensions/postgis/cloudberry-postgis-examples-test.sql` - Documentation examples

**Usage**:
```bash
./assemble.sh --run --component postgis --steps crash-test
```

**Expected Behavior**: This step intentionally crashes the database for debugging purposes and generates core dumps for analysis.

### PostGIS Testing Configuration
- **Tiger Geocoder**: Requires plpython3u extension setup in template1
- **Regression Test Patch**: Applied during build to use template1 instead of template0
- **Test Flags**: `--tiger --sfcgal --raster --extension` enabled by default
- **Core Dump Analysis**: Automated GDB analysis with pattern recognition

## Common Development Issues

### Environment and Path Management
- **PARTS_DIR**: Defaults to `$HOME/bom-parts/`, configurable via environment
- **INSTALL_PREFIX**: Per-component prefixes like `/usr/local/cloudberry`, `/usr/local/geos-3.11.0`
- **Library Discovery**: LD_LIBRARY_PATH, PKG_CONFIG_PATH, CMAKE_PREFIX_PATH automatically configured

### Build System Patterns
- **Generic Scripts**: Automatically handle tarball extraction, MD5 validation, CMake/autotools builds
- **Component Overrides**: Component-specific scripts take precedence over generic ones
- **Step Dependencies**: Clone → configure → build → install → test pattern
- **Force Rebuilds**: `--force` flag cleans existing source and rebuilds from scratch

### Extension Build Notes
- **PGXS System**: PostgreSQL extensions use `USE_PGXS=1` and `postgres-extension.sh`
- **Cloudberry Integration**: Extensions use `--with-pgconfig="${GPHOME}"/bin/pg_config`
- **Test Skipping**: Most extensions have `DISABLE_EXTENSION_TESTS=true` to avoid regression test issues

## Debugging and Analysis

### Log Analysis
- Build logs stored in `logs/` with timestamps
- Component-specific logs: `logs/<component>-<step>-<timestamp>.log`
- Error patterns: Look for configure failures, missing dependencies, compilation errors

### PostGIS Stability Issues
**Known Crash Patterns**:
- **AVX512-MEMMOVE**: Memory corruption in AVX512 optimized operations
- **TOAST-CORRUPTION**: TOAST data handling issues with large geometries
- **POSTGIS-FUNCTION**: ST_AsText(), ST_Buffer() crashes in distributed queries

**Core Dump Analysis**: Automated pattern recognition in crash-test-postgis.sh identifies these signatures.

## File Organization

### Critical Files for AI Development
- `bom.yaml` - Component definitions and build configuration
- `stations/generic/common.sh` - Shared logging and utility functions
- `config/env.sh` - Environment setup with library paths
- `stations/extensions/postgis/test-postgis.sh` - Comprehensive PostGIS testing

### Station Script Discovery Pattern
1. Look for `stations/{layer}/{component}/{step}-{component}.sh`
2. Fallback to `stations/generic/{step}.sh`
3. Import `stations/generic/common.sh` for logging functions

## Testing and Validation

### Component Testing Levels
- **Unit Tests**: Component-specific (e.g., cloudberry unittest)
- **Integration Tests**: Cross-component compatibility
- **Regression Tests**: Extension-specific test suites
- **Stability Tests**: Crash reproduction and core dump analysis

### Test Configuration Management
- **Cloudberry**: Multiple test configs (default, optimizer-off, PAX storage)
- **PostGIS**: Comprehensive regression suite with tiger geocoder, SFCGAL, raster
- **Dependencies**: Basic functionality validation

## Development Best Practices

### When Modifying Station Scripts
1. Maintain existing logging patterns using `common.sh` functions
2. Preserve error handling and exit codes
3. Keep component-specific logic in component directories
4. Update both script and documentation if changing interfaces

### When Adding New Components
1. Add to appropriate layer in `bom.yaml` (dependencies → core → extensions)
2. Create component directory: `stations/{layer}/{component}/`
3. Override generic steps as needed
4. Test build pipeline thoroughly
5. Document any special requirements or known issues

### Environment Considerations
- PostGIS stack requires significant disk space and build time (GDAL ~8-12 minutes)
- Debug builds of Cloudberry include assertions and extended logging
- Core dumps require appropriate system configuration for collection

---

**Note**: This file focuses on AI development guidance. For user documentation, build instructions, and architecture overview, see README.md.