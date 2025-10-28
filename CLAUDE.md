# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Assembly BOM is a Software Bill of Materials (SBOM) development tool supporting multiple products through separate BOM configurations:

- **Cloudberry Database Ecosystem** (`cloudberry-bom.yaml`, default) - Complete database build with geospatial dependencies
- **Apache Release Validation** (`apache-bom.yaml`) - Cryptographic verification of Apache Software Foundation releases

See README.md for user documentation and architecture overview.

## AI Development Workflow

### Essential Commands for Development
```bash
# List available BOM files
./assemble.sh -B

# Cloudberry development (default BOM)
./assemble.sh --dry-run --component <component>
./assemble.sh --run --component <component> --steps <step> --force

# Apache release validation
./assemble.sh -b apache-bom.yaml --run --component <component>
./assemble.sh -b apache-bom.yaml -l

# Lint and typecheck (run after code changes)
# NOTE: Check README or ask user for specific linting commands if not found
```

### Code Analysis and Modification Guidelines
- **Station Scripts**: Follow naming pattern `stations/{layer}/{component}/{step}.sh`
- **Generic Fallbacks**: Located in `stations/generic/` for common build patterns
- **Apache Scripts**: All Apache-specific scripts prefixed with `apache-` in `stations/generic/`
- **Environment Setup**: Check `config/env.sh` for shared variables and paths
- **Component Definition**: Components defined in BOM files (`cloudberry-bom.yaml`, `apache-bom.yaml`) with steps, flags, and dependencies
- **BOM Selection**: Use `--bom-file` or `-b` flag to specify alternate BOM files

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
PostGIS has memory corruption issues in distributed query scenarios. The crash testing framework provides systematic reproduction:

**Files**:
- `stations/extensions/postgis/crash-test.sh` - Automated crash reproduction and analysis
- `stations/extensions/postgis/postgis-distributed-crash-test.sql` - ⚠️ **Reproduces crash** (distributed queries)
- `stations/extensions/postgis/postgis-intensive-raster-test.sql` - ✅ Stress test (85+ ops, passes)
- `stations/extensions/postgis/postgis-crash-test.sql` - ✅ Basic validation (passes)
- `stations/extensions/postgis/POSTGIS-CRASH-ANALYSIS.md` - Technical root cause analysis

**Usage**:
```bash
./assemble.sh --run --component postgis --steps crash-test
```

**Expected Behavior**: This step **intentionally triggers memory corruption** in distributed queries:
- Tests 1-4: Basic operations ✅ pass
- Test 5: ST_Contains with cross-segment joins ❌ **crashes** (mcxt.c:933)
- Test 7: ST_Intersection with TOAST geometries ❌ **crashes** (mcxt.c:933)
- Generates core dumps for automated analysis
- Detects crash patterns: `[MEMORY-CONTEXT-CORRUPTION] [GEOMETRY-CACHE] [DISTRIBUTED-GEOMETRY]`

**Root Cause**: PostGIS geometry cache (`shared_gserialized_ref`) assumes single-process memory management. In Cloudberry/Greenplum, geometries cross segment boundaries via motion nodes, causing memory context validation failures.

### PostGIS Testing Configuration
- **Tiger Geocoder**: Requires plpython3u extension - automatically created in template1 during test step
- **Regression Test Filtering**: `postgis-cloudberry-test-filters.patch` applied during build for Cloudberry compatibility:
  - Filters autovacuum warnings (Cloudberry doesn't support autovacuum)
  - Removes segment identifiers from error messages (seg0 slice1 IP:port pid=...)
  - Strips source file locations from errors for consistency (file.c:line)
  - Removes statistics notices and hints
  - Changes test database template from template0 to template1 (enables plpython3u)
- **Test Flags**: `--tiger --sfcgal --raster --extension` enabled by default
- **Core Dump Analysis**: Automated GDB analysis with pattern recognition
- **Expected Test Results**: With filtering patch, most cosmetic differences resolved; remaining failures mainly due to row ordering in distributed queries

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
**Known Crash Patterns** (automatically detected by crash-test.sh):
- **MEMORY-CONTEXT-CORRUPTION**: mcxt.c:933 assertion failure (PRIMARY ISSUE)
- **GEOMETRY-CACHE**: PostGIS geometry cache corruption in `shared_gserialized_ref`
- **DISTRIBUTED-GEOMETRY**: ST_Contains, ST_Intersection crashes in cross-segment joins
- **MOTION-NODE**: Geometry data crossing segment boundaries
- **TOAST-CORRUPTION**: Large TOAST geometries with distributed operations

**Status**:
- ❌ Distributed queries with geometry joins: **CRASH CONFIRMED** (upstream bug)
- ✅ Single-segment queries: **WORK CORRECTLY**
- ✅ Simple geometry operations: **WORK CORRECTLY**

**Workaround**: Avoid cross-segment geometry joins in production. Use replicated tables for small geometry reference data.

**Core Dump Analysis**: Automated pattern recognition in crash-test.sh identifies crash signatures and generates detailed GDB analysis reports.

## Apache Release Validation Framework

### Overview
The Apache validation framework provides automated cryptographic verification and compliance validation for Apache Software Foundation releases.

### Apache-Specific Generic Scripts
All Apache scripts are prefixed with `apache-` and located in `stations/generic/`:

- **`apache-discover-and-verify-release.sh`** - Discovery-based validation
  - Auto-discovers all artifacts (src/bin) from `RELEASE_URL`
  - Downloads KEYS file from `KEYS_URL` and imports GPG keys
  - Verifies GPG signatures (.asc files) for all artifacts
  - Verifies SHA512 checksums (.sha512 files) for all artifacts
  - Categorizes artifacts: `-src` or `-source` = source, others = binary
  - Saves artifact lists to `.discovered-src-artifacts` and `.discovered-bin-artifacts`

- **`apache-extract-discovered.sh`** - Artifact extraction
  - Reads discovered artifact lists
  - Auto-detects archive format (tar.gz, tar.bz2, tar.xz, zip)
  - Extracts all source and binary artifacts

- **`apache-validate-compliance.sh`** - Apache compliance validation
  - **Incubator Detection**: Auto-detects incubator projects by checking:
    - RELEASE_URL contains "/incubator/" (primary detection method)
    - Component name contains "incubating"
    - Directory name contains "incubating"
  - **Incubator Requirements** (enforced when detected):
    - Artifact names MUST contain "incubating"
    - Directory names MUST contain "incubating"
    - DISCLAIMER or DISCLAIMER-WIP file required
    - LICENSE and NOTICE with correct content
    - KEYS_URL must point to release tree (downloads.apache.org or dist/release), not dev tree (dist/dev)
    - Reference: https://incubator.apache.org/policy/incubation.html
  - **Standard Requirements** (all projects):
    - LICENSE file (Apache License 2.0)
    - NOTICE file (ASF attribution, copyright with current year)

- **`apache-rat.sh`** - Apache Release Audit Tool (RAT) for license header validation
  - **Purpose**: Automated scanning of source files for Apache license headers
  - **Requirements**: Maven (mvn) must be installed
  - **Process**:
    - Runs `mvn apache-rat:check` in extracted source directory
    - Parses results from Maven output and `target/rat.txt`
    - Identifies files missing Apache license headers
    - Categorizes files: approved, generated, JavaDoc, unknown/unapproved
    - Creates detailed reports for review
  - **Output Files**:
    - `target/rat.txt` - Full RAT report from Maven plugin
    - `target/rat-summary.txt` - Concise summary with statistics
    - `target/rat-unknown-licenses.txt` - List of files missing headers (if any)
  - **Common Findings**:
    - Documentation files (.md, .rst, .txt) often excluded
    - Configuration files (.yaml, .json, .xml) may need exclusions
    - Test data and generated code typically excluded
    - README, LICENSE, NOTICE files don't need headers
  - **Integration**: Add as step in apache-bom.yaml after apache-validate-compliance
  - **Manual Review**: Results require review as some files legitimately don't need headers

### Apache License Compliance Review Toolkit

**Purpose**: Deep license compliance review for Apache source releases, going beyond basic file validation to detect licensing issues that would block releases.

**Files**:
- **`stations/generic/apache-review-license-compliance.sh`** - Automated license scanner
  - Searches for derived/copied code with attribution comments ("derived from", "based on", "adapted from")
  - Finds non-ASF copyright statements requiring LICENSE file attribution
  - Detects files with multiple/duplicate license headers
  - Identifies assembly/uber JARs and analyzes bundled dependencies
  - Extracts package lists from JARs to identify third-party libraries
  - Checks for common missing licenses (argonaut, shapeless, jansi, hawtjni, etc.)
  - Creates timestamped output directory with detailed findings

- **`docs/Apache-Release-Review-Guide.md`** - Comprehensive review methodology
  - 4-phase review process (Verification → Automated Scanning → Manual Review → Documentation)
  - Time estimates for each phase (15-120 minutes total)
  - Common issues to watch for (critical/major/minor severity)
  - Assembly JAR deep-dive procedures
  - Vote casting guidelines (+1/-1 with proper justification)
  - Command examples and tips for efficient reviews

- **`docs/Apache-Release-Review-Template.md`** - Structured review document
  - Comprehensive checklist for all compliance areas
  - Artifact verification section (signatures, checksums)
  - License compliance tracking (source files, third-party code, assembly JARs)
  - Build verification results
  - Issue documentation by severity
  - Vote recommendation with justification

**Usage**:
```bash
# Run automated scanner on extracted source
cd $HOME/bom-parts/toree/toree-0.6.0-incubating-src
$HOME/assembly-bom/stations/generic/apache-review-license-compliance.sh

# Review output
ls -la license-review-*/
cat license-review-*/non-asf-copyrights.txt
cat license-review-*/assembly-jars.txt

# Document findings
cp $HOME/assembly-bom/docs/Apache-Release-Review-Template.md my-review.md
# Fill in template with findings
```

**Critical Issues Detected**:
- **Missing LICENSE attributions** - Embedded third-party code (e.g., Guava ClassPath.java) not mentioned in LICENSE
- **Assembly JAR licensing** - Bundled libraries missing proper licenses in META-INF
- **Duplicate headers** - Files with both ASF and original license (should keep only original if also Apache 2.0)
- **Category-X licenses** - Accidental bundling of incompatible licenses (JSON, BSD-4-Clause, GPL)

**Example from Toree 0.6.0-rc1**:
- Found: ClassPath.java derived from Guava v32.1.2 (lines 73-78 state derivation)
- Issue: Not mentioned in root LICENSE file
- Also had: Duplicate license headers (both ASF and Guava)
- Result: -1 binding vote, release blocked

**When to Use**:
- Reviewing Apache Incubator source releases before voting
- Preparing release candidates for vote
- Investigating license compliance issues
- Auditing assembly/uber JARs for bundled dependencies

**Integration with BOM**:
Can be added as a manual review step or integrated into apache-bom.yaml for systematic reviews.

### Component-Specific Build Scripts

Some Apache projects have custom build requirements that override generic build steps:

**Apache GeaFlow:**
- **Build Command**: `./build.sh --module=geaflow --output=package`
- **Location**: `stations/core/geaflow/build.sh`
- **Process**: Runs Maven reactor build for all 103 modules
- **Duration**: Approximately 10-20 minutes for full build
- **Output**: Package directory with built artifacts
- **Build Log**: Saved to `/tmp/geaflow-build.log`
- **Summary**: Generated at `build-summary.txt` in source directory

### Apache BOM Configuration
Environment variables required for Apache components:
- `RELEASE_VERSION` - Version number (e.g., "1.11.0")
- `RELEASE_CANDIDATE` - RC number (e.g., "rc6")
- `RELEASE_URL` - Full URL to release artifacts directory
- `KEYS_URL` - Full URL to KEYS file

### Discovery-Based Architecture
The framework requires **no hardcoding** of artifact names. It dynamically:
1. Fetches directory listing from `RELEASE_URL`
2. Identifies all archive artifacts (.tar.gz, .tar.bz2, .tar.xz, .zip)
3. Categorizes as source (contains `-src` or `-source`) or binary
4. Validates all discovered artifacts automatically

This approach handles varying numbers of artifacts per project without configuration changes.

## File Organization

### Critical Files for AI Development
- `cloudberry-bom.yaml` - Cloudberry Database component definitions and build configuration (default)
- `apache-bom.yaml` - Apache release validation component definitions
- `stations/generic/common.sh` - Shared logging and utility functions
- `stations/generic/apache-*.sh` - Apache-specific validation scripts
- `config/env.sh` - Environment setup with library paths
- `stations/extensions/postgis/test.sh` - Comprehensive PostGIS testing

### Station Script Discovery Pattern
1. Look for `stations/{layer}/{component}/{step}.sh`
2. Fallback to `stations/generic/{step}.sh`
3. For Apache components, use `stations/generic/apache-{step}.sh`
4. Import `stations/generic/common.sh` for logging functions

## Testing and Validation

### Component Testing Levels
- **Unit Tests**: Component-specific (e.g., cloudberry unittest)
- **Integration Tests**: Cross-component compatibility
- **Regression Tests**: Extension-specific test suites
- **Stability Tests**: Crash reproduction and core dump analysis
- **Cryptographic Validation**: Apache release signature and checksum verification

### Test Configuration Management
- **Cloudberry**: Multiple test configs (default, optimizer-off, PAX storage)
- **PostGIS**: Comprehensive regression suite with tiger geocoder, SFCGAL, raster
- **Dependencies**: Basic functionality validation
- **Apache Releases**: GPG signature verification, SHA512 checksums, compliance validation

## Development Best Practices

### When Modifying Station Scripts
1. Maintain existing logging patterns using `common.sh` functions
2. Preserve error handling and exit codes
3. Keep component-specific logic in component directories
4. Update both script and documentation if changing interfaces

### When Adding New Components

**For Cloudberry Ecosystem Components:**
1. Add to appropriate layer in `cloudberry-bom.yaml` (dependencies → core → extensions)
2. Create component directory: `stations/{layer}/{component}/`
3. Override generic steps as needed
4. Test build pipeline thoroughly
5. Document any special requirements or known issues

**For Apache Release Validation:**
1. Add to `apache-bom.yaml` under `components.core`
2. Set required environment variables: `RELEASE_VERSION`, `RELEASE_CANDIDATE`, `RELEASE_URL`, `KEYS_URL`
3. Use standard Apache steps: `apache-discover-and-verify-release`, `apache-extract-discovered`, `apache-validate-compliance`, `apache-rat`
4. Optional: Add `build` step if project has custom build requirements (create `stations/core/<component>/build.sh`)
5. No component-specific scripts needed for validation - discovery-based validation handles all artifacts automatically
6. Test with: `./assemble.sh -b apache-bom.yaml --run --component <component>`

**For New Product Categories:**
1. Create new BOM file: `{product}-bom.yaml`
2. Follow pattern: `{project}-bom.yaml` naming convention
3. Define product name and component structure
4. Create product-specific generic scripts with appropriate prefix (e.g., `maven-*.sh`, `npm-*.sh`)
5. Test with: `./assemble.sh -b {product}-bom.yaml -l`

### Environment Considerations
- PostGIS stack requires significant disk space and build time (GDAL ~8-12 minutes)
- Debug builds of Cloudberry include assertions and extended logging
- Core dumps require appropriate system configuration for collection

---

**Note**: This file focuses on AI development guidance. For user documentation, build instructions, and architecture overview, see README.md.