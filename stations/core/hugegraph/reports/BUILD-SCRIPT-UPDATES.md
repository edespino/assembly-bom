# HugeGraph Build Script - Automation Updates

**Date:** 2025-11-21  
**Script:** `/home/cbadmin/assembly-bom/stations/core/hugegraph/build.sh`

## Overview

Updated the HugeGraph build script to **automatically build all projects** without manual commands, including:
- Maven projects (root and subdirectories)
- Go projects in subdirectories
- Python projects (via separate `build-python.sh`)

## Key Features

### 1. Automatic Project Detection

The script now automatically detects and classifies build systems:

- **Root Maven projects** - `pom.xml` at root level
- **Maven subdirectories** - Scans for `*/pom.xml` files
- **Go subdirectories** - Scans for `*/go.mod` files
- **Python projects** - Detects `pyproject.toml` (delegates to `build-python.sh`)

### 2. Maven Build Handling

#### Root Maven Builds
- Builds entire project reactor from root
- **Automatically skips** subdirectory Maven builds if root build succeeds
- Prevents duplicate builds of modules already built by reactor

#### Subdirectory Maven Builds
- **Only executed** when no root `pom.xml` exists
- Builds each Maven subdirectory independently
- Example: `apache-hugegraph-computer/computer/`

### 3. Go Build Support

#### Automatic Go Builds
- Detects Go modules in subdirectories via `go.mod`
- Uses `Makefile` for build automation (`make all`)
- Automatic dependency updates for Go 1.25 compatibility:
  - Checks for `sonic` library version
  - Updates `sonic` < v1.14.0 to latest (v1.14.2+)
  - Runs `go mod tidy` after updates

#### Go Binary Detection
- Finds executables in build output
- Reports binary count and sizes
- Example: `vermeer` (62MB)

### 4. Java 11 Environment

Automatically configures Java 11 for all Maven builds:
```bash
export JAVA_HOME="/usr/lib/jvm/java-11-openjdk-11.0.25.0.9-7.el9.x86_64"
export PATH="$JAVA_HOME/bin:$PATH"
```

**Why Java 11:** HugeGraph dependencies require Java 11+ (will fail with Java 8)

## Usage

### Single Command Build
```bash
./assemble.sh -b apache-bom.yaml -c hugegraph -r -s build
```

This single command now:
1. Builds apache-hugegraph-incubating (Maven reactor, 39 JARs)
2. Builds apache-hugegraph-toolchain (Maven reactor, 10 JARs)
3. Builds apache-hugegraph-computer/computer (Maven, 9 JARs)
4. Builds apache-hugegraph-computer/vermeer (Go, 1 binary)
5. Skips apache-hugegraph-ai (Python - use build-python.sh)

### With Python
```bash
./assemble.sh -b apache-bom.yaml -c hugegraph -r -s build,build-python
```

## Build Results

### Successful Builds (Automated)

| Project | Type | Artifacts | Build Time |
|---------|------|-----------|------------|
| apache-hugegraph-incubating | Maven (Root) | 39 JARs | ~10 min |
| apache-hugegraph-toolchain | Maven (Root) | 10 JARs | ~30 sec |
| apache-hugegraph-computer/computer | Maven (Subdir) | 9 JARs | ~37 sec |
| apache-hugegraph-computer/vermeer | Go (Subdir) | 1 binary (62MB) | ~3 sec |
| apache-hugegraph-ai | Python | 2 artifacts | ~7 sec |

**Total:** 60 artifacts (58 JARs + 2 Python)

### Key Improvements

1. **No Manual Commands Required**
   - Before: Had to manually cd to subdirectories and run builds
   - After: Single command builds everything

2. **Intelligent Build Strategy**
   - Detects root vs subdirectory structure
   - Avoids duplicate builds
   - Respects Maven reactor patterns

3. **Go 1.25 Compatibility**
   - Automatically fixes `sonic` dependency issues
   - No manual `go get` or `go mod tidy` needed

4. **Comprehensive Logging**
   - Separate log files for each build
   - Clear progress indicators
   - Artifact counts and sizes

## Script Architecture

### Build Flow
```
For each source directory:
  1. Detect build systems (root/subdirs)
  2. Set Java 11 environment
  3. Build root Maven (if exists)
     → Skip Maven subdirs if root succeeded
  4. Build Maven subdirs (if no root)
  5. Build Go subdirs (with Makefile)
  6. Report results
```

### Error Handling
- Continues on individual build failures
- Tracks overall success/failure status
- Generates detailed logs for debugging
- Exit code 1 if any build fails

## Technical Details

### Maven Build Command
```bash
mvn clean install -DskipTests
```

### Go Build Commands
```bash
# Dependency check
go get github.com/bytedance/sonic@latest  # If < v1.14.0
go mod tidy

# Build
make all  # Runs: make generate-assets && make build
```

### Build Logs
Logs are stored in `/tmp/` with descriptive names:
- `/tmp/hugegraph-build-<directory>.log`
- `/tmp/hugegraph-build-<directory>-<subdir>.log`

## Known Limitations

1. **Python Projects**: Must use separate `build-python.sh` script
2. **Go without Makefile**: Skipped (requires Makefile)
3. **Nested Subdirectories**: Only scans one level deep for subdirs

## Future Enhancements

Potential improvements:
- Support for Go projects without Makefile
- Deeper subdirectory scanning (2+ levels)
- Parallel Maven reactor builds
- Build caching/incremental builds

---

**Script Location:** `/home/cbadmin/assembly-bom/stations/core/hugegraph/build.sh`  
**Python Script:** `/home/cbadmin/assembly-bom/stations/core/hugegraph/build-python.sh`
