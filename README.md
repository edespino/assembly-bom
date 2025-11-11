# 🔩 Assembly BOM

**Assembly BOM** is a Software Bill of Materials (SBOM) development tool that provides systematic build orchestration for software projects. It uses declarative BOM files to define components, dependencies, and build steps — enabling reproducible, portable builds with release engineering discipline.

Primary use cases:
- **Cloudberry Database Ecosystem** (`cloudberry-bom.yaml`) - Complete database build with geospatial dependencies
- **Warehouse-PG Database** (`warehouse-pg-bom.yaml`) - Warehouse-PG WHPG_7_2_STABLE branch build and validation
- **Apache Release Validation** (`apache-bom.yaml`) - Cryptographic verification of Apache Software Foundation releases

---

## 🎯 Overview

Assembly BOM brings industry-standard SBOM practices to development workflows, providing:

- **Dependency Tracking**: Complete visibility into all components and versions
- **Supply Chain Security**: Know exactly what's in your build
- **Reproducible Builds**: Deterministic component assembly
- **Component Lifecycle Management**: Build → test → integration workflows
- **Release Engineering Discipline**: Professional build orchestration

---

## 📁 Project Structure

```
assembly-bom/
├── assemble.sh                           # Main build orchestrator
├── cloudberry-bom.yaml                   # Cloudberry Database SBOM (default)
├── warehouse-pg-bom.yaml                 # Warehouse-PG Database SBOM
├── apache-bom.yaml                       # Apache release validation SBOM
├── config/
│   ├── bootstrap.sh                      # Toolchain setup
│   ├── env.sh                           # Environment configuration
│   └── cloudberry-env-loader.sh        # Cloudberry environment
├── stations/                            # Component build pipeline
│   ├── core/
│   │   └── cloudberry/                  # Core database engine
│   ├── extensions/
│   │   ├── pxf/                         # Platform Extension Framework
│   │   └── postgis/                     # PostGIS geospatial extension
│   ├── dependencies/
│   │   ├── cgal/                        # Computational Geometry
│   │   ├── sfcgal/                      # 3D geometry operations
│   │   ├── geos/                        # Geometry engine
│   │   ├── proj/                        # Coordinate transformations
│   │   └── gdal/                        # Geospatial data abstraction
│   └── generic/                         # Shared build utilities
├── docs/                                # Documentation and guides
└── parts/ -> $HOME/bom-parts/          # Source code checkouts
```

---

## 🏗️ Component Architecture

### Build Order (Dependency Hierarchy)
1. **Dependencies** - External libraries (CGAL, SFCGAL, GEOS, PROJ, GDAL)
2. **Core** - Cloudberry Database engine
3. **Extensions** - Database extensions (PostGIS, PXF)

### Station-Based Pipeline
- **Component-Specific Scripts**: `stations/{layer}/{component}/{step}-{component}.sh`
- **Generic Fallbacks**: `stations/generic/{step}.sh`
- **Shared Utilities**: Common logging, environment setup, build patterns

---

## 📋 Multiple BOM Files

Assembly BOM supports multiple BOM configurations for different products and workflows:

### List Available BOMs
```bash
# Show all available BOM files
./assemble.sh -B
# or
./assemble.sh --list-boms
```

**Output:**
```
[assemble] Available BOM files:

  apache-bom.yaml
    Product: apache-releases
  cloudberry-bom.yaml (default)
    Product: cloudberry
  warehouse-pg-bom.yaml
    Product: cloudberry

Usage: ./assemble.sh -b <bom-file> [options]
```

### Select BOM File
```bash
# Use default (cloudberry-bom.yaml)
./assemble.sh -l

# Use Apache release validation BOM
./assemble.sh -b apache-bom.yaml -l
# or
./assemble.sh --bom-file apache-bom.yaml -l
```

---

## ✍️ BOM Structure Examples

### Cloudberry Database BOM (`cloudberry-bom.yaml`)

```yaml
products:
  cloudberry:
    components:
      core:
        - name: cloudberry
          url: https://github.com/apache/cloudberry.git
          branch: main
          configure_flags: |
            --disable-external-fts
            --enable-debug
            --enable-cassert
            --enable-debug-extensions
            --enable-gpcloud
            --enable-gpfdist
            --with-gssapi
            --with-ldap
            --with-openssl
          steps:
            - clone
            - configure
            - build
            - install
            - create-demo-cluster
            - unittest
            - installcheck

      extensions:
        - name: pxf
          url: https://github.com/apache/cloudberry-pxf.git
          branch: upstream
          steps:
            - clone
            - build
            - install-test

        - name: postgis
          url: https://github.com/cloudberry-contrib/postgis.git
          branch: main
          configure_flags: |
            --with-pgconfig="${GPHOME}"/bin/pg_config
            --with-raster
            --without-topology
            --with-gdalconfig=/usr/local/gdal-3.5.3/bin/gdal-config
            --with-sfcgal=/usr/local/sfcgal-1.4.1/bin/sfcgal-config
            --with-geosconfig=/usr/local/geos-3.11.0/bin/geos-config
          steps:
            - clone
            - configure
            - build
            - install
            - test
            - crash-test

      dependencies:
        - name: cgal
          url: https://github.com/CGAL/cgal/releases/download/v5.6.1/CGAL-5.6.1.tar.xz
          branch: "v5.6.1"
          configure_flags: |
            -DCMAKE_BUILD_TYPE=Release
            -DCMAKE_INSTALL_PREFIX=/usr/local/cgal-5.6.1

        - name: geos
          url: https://download.osgeo.org/geos/geos-3.11.0.tar.bz2
          configure_flags: |
            -DCMAKE_INSTALL_PREFIX=/usr/local/geos-3.11.0

        # ... additional dependencies
```

### Apache Release Validation BOM (`apache-bom.yaml`)

```yaml
products:
  apache-releases:
    components:
      core:
        - name: resilientdb
          env:
            RELEASE_VERSION: "1.11.0"
            RELEASE_CANDIDATE: "rc6"
            RELEASE_URL: "https://dist.apache.org/repos/dist/dev/incubator/resilientdb/1.11.0-rc6/resilientdb"
            KEYS_URL: "https://dist.apache.org/repos/dist/dev/incubator/resilientdb/KEYS"
          steps:
            - apache-discover-and-verify-release
            - apache-extract-discovered
            - apache-validate-compliance

        - name: toree
          env:
            RELEASE_VERSION: "0.6.0"
            RELEASE_CANDIDATE: "rc1"
            RELEASE_URL: "https://dist.apache.org/repos/dist/dev/incubator/toree/0.6.0-incubating-rc1/toree"
            KEYS_URL: "https://dist.apache.org/repos/dist/release/incubator/toree/KEYS"
          steps:
            - apache-discover-and-verify-release
            - apache-extract-discovered
            - apache-validate-compliance
```

**Apache-Specific Steps:**
- `apache-discover-and-verify-release` - Auto-discovers artifacts, verifies GPG signatures and SHA512 checksums
- `apache-extract-discovered` - Extracts all discovered source and binary artifacts
- `apache-validate-compliance` - Validates LICENSE, NOTICE (current year), DISCLAIMER files, and KEYS file location (incubator projects)

---

## ⚙️ Quick Start

### 1. Prerequisites
```bash
# Install system dependencies (RHEL/CentOS/Rocky Linux)
sudo dnf install -y gmp-devel mpfr-devel sqlite-devel protobuf-c protobuf-c-devel
sudo dnf install -y libxslt docbook-style-xsl
```

### 2. List Available BOMs
```bash
# Show all available BOM files
./assemble.sh -B
```

### 3. Cloudberry Database Build
```bash
# Show all components and build order (uses cloudberry-bom.yaml by default)
./assemble.sh -l

# Show detailed component information
./assemble.sh -D

# Build entire Cloudberry ecosystem
./assemble.sh --run

# Build specific components
./assemble.sh --run --component cloudberry
./assemble.sh --run --component cloudberry,pxf,postgis

# Build with custom steps
./assemble.sh --run --component cloudberry --steps configure,build

# Force rebuild (cleans existing repos)
./assemble.sh --run --force

# Dry run (show what would be executed)
./assemble.sh --dry-run
```

### 4. Apache Release Validation
```bash
# List Apache release components
./assemble.sh -b apache-bom.yaml -l

# Validate Apache ResilientDB 1.11.0-rc6
./assemble.sh -b apache-bom.yaml --run --component resilientdb

# Validate all Apache releases
./assemble.sh -b apache-bom.yaml --run

# Show validation details
./assemble.sh -b apache-bom.yaml -D -c resilientdb
```

**Validation Process:**
1. Auto-discovers all artifacts (source + binary tarballs) from release URL
2. Downloads KEYS file and imports GPG keys
3. Verifies GPG signatures (.asc files) for all artifacts
4. Verifies SHA512 checksums for all artifacts
5. Extracts all artifacts
6. Validates LICENSE, NOTICE (with current year check), and DISCLAIMER files

### 5. Individual Station Execution
```bash
# Run individual build steps directly
NAME=cloudberry INSTALL_PREFIX=/usr/local/cloudberry ./stations/core/cloudberry/build.sh
NAME=pxf ./stations/extensions/pxf/build.sh
NAME=postgis ./stations/extensions/postgis/build.sh
```

---

## 🧪 Testing Framework

### Cloudberry Database Tests
```bash
# Unit tests
./assemble.sh --run --component cloudberry --steps unittest

# Integration tests (default optimizer settings)
./assemble.sh --run --component cloudberry --steps installcheck

# PAX storage engine tests
./assemble.sh --run --component cloudberry --steps pax-test
```

### PostGIS Stability Testing
```bash
# Standard PostGIS regression tests
./assemble.sh --run --component postgis --steps test

# PostGIS crash reproduction testing (debugging)
./assemble.sh --run --component postgis --steps crash-test
```

---

## 🔧 System Requirements

### Required Packages
```bash
# Development tools
bash, git, yq (v4+)

# Cloudberry Database dependencies
gcc, make, readline-devel, zlib-devel, openssl-devel

# PostGIS geospatial stack dependencies
gmp-devel, mpfr-devel, sqlite-devel
protobuf-c, protobuf-c-devel
libxslt, docbook-style-xsl
```

### Environment Variables
```bash
PARTS_DIR="$HOME/bom-parts"          # Source checkout directory
INSTALL_PREFIX="/usr/local/$NAME"     # Per-component install prefix
DISABLE_EXTENSION_TESTS=true          # Skip extension regression tests
USE_PGXS=1                           # Use PostgreSQL extension build system
```

---

## 🏭 Component Details

### Core: Cloudberry Database
- **Source**: Apache Cloudberry
- **Features**: Distributed database with debug mode, extensions, optimizers
- **Test Configs**: Default, optimizer-off, PAX storage
- **Install**: `/usr/local/cloudberry`

### Extensions: PostGIS
- **Source**: Cloudberry-contrib PostGIS fork
- **Dependencies**: Complete geospatial stack (CGAL → SFCGAL → GEOS → PROJ → GDAL)
- **Features**: Raster support, SFCGAL 3D operations, MVT/Geobuf formats
- **Testing**: Regression tests + crash analysis framework

### Extensions: PXF
- **Source**: Apache Cloudberry PXF
- **Purpose**: Platform Extension Framework for external data access
- **Build**: Java-based with Cloudberry integration

---

## 📚 Documentation

- **`docs/PostGIS-Manual-Build-Guide.md`** - Complete PostGIS build instructions
- **`docs/PostGIS-Validation-Report.md`** - PostGIS stability analysis
- **`docs/PostGIS-Crash-Test-Framework-Integration.md`** - Crash testing framework
- **`CLAUDE.md`** - Development guidance and architecture details

---

## 🔄 Advanced Usage

### Custom Component Steps
```bash
# Override default steps
./assemble.sh --run --component postgis --steps clone,configure,build

# Skip steps (when already completed)
./assemble.sh --run --component cloudberry --steps install,unittest
```

### Environment Customization
```bash
# Custom parts directory
PARTS_DIR=/custom/path ./assemble.sh --run

# Custom install prefix
INSTALL_PREFIX=/opt/cloudberry ./assemble.sh --run --component cloudberry
```

### Force Operations
```bash
# Force clean and rebuild
./assemble.sh --run --force --component postgis

# Force specific steps
./assemble.sh --run --component cloudberry --steps configure --force
```

---

## 🛠️ Extending the Framework

### Adding New Components
1. Add component definition to `bom.yaml`
2. Create component-specific stations in `stations/{layer}/{component}/`
3. Override generic steps as needed
4. Test build pipeline

### Component-Specific Scripts
```bash
# Override pattern: stations/{layer}/{component}/{step}.sh
stations/extensions/myextension/configure.sh
stations/extensions/myextension/build.sh
stations/extensions/myextension/test.sh
```

---

## 📦 License

Apache License 2.0 — see [LICENSE](LICENSE)

---

## 🤝 Contributing

This Assembly BOM tool follows Software Bill of Materials best practices for development workflows. Contributions should maintain:

- **Deterministic builds** - Reproducible component assembly 
- **Clear dependencies** - Explicit component relationships
- **Systematic testing** - Comprehensive validation at each layer
- **Documentation** - Clear component descriptions and build instructions

For development guidance, see `CLAUDE.md` for detailed architecture and implementation notes.
