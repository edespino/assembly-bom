# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Assembly BOM is a modular, declarative build orchestration system for multi-component database systems. It builds a complete Cloudberry Database stack with extensions and tools from source using a YAML-based Bill of Materials.

## Essential Commands

### Build System Commands
```bash
# Show all components and build order
./assemble.sh -l

# Show detailed component info (Git, steps, env, configure flags)
./assemble.sh -D

# Build entire product (requires --run for safety)
./assemble.sh --run

# Build specific components
./assemble.sh --run --component cloudberry
./assemble.sh --run --component cloudberry,pxf,pg_jieba

# Build with custom steps
./assemble.sh --run --component cloudberry --steps configure,build

# Force rebuild (cleans existing repos)
./assemble.sh --run --force

# Dry run (show what would be executed)
./assemble.sh --dry-run
```

### Individual Station Execution
```bash
# Run individual build steps directly
NAME=cloudberry INSTALL_PREFIX=/usr/local/cloudberry ./stations/build-cloudberry.sh
NAME=pxf ./stations/build-pxf.sh
NAME=pg_jieba ./stations/postgres-extension.sh
```

## Architecture

### Component Hierarchy (built in dependency order)
1. **dependencies** - External libraries (Apache Arrow, Apache ORC)
2. **core** - Main database engine (Cloudberry Database) 
3. **extensions** - Database extensions (PXF, pg_jieba, pgvector, etc.)
4. **components** - Utility tools (pg_filedump, pgpool)

### Station-Based Build Pipeline
- **Generic stations**: `clone.sh`, `configure.sh`, `build.sh`, `install.sh`, `test.sh`
- **Component-specific overrides**: `<step>-<component>.sh` (e.g., `build-cloudberry.sh`)
- **PostgreSQL extensions**: Use `postgres-extension.sh` for standardized extension builds

### Key Directories
- `bom.yaml` - Component definitions and build configuration
- `stations/` - Build step implementations 
- `parts/` - Source code checkouts (populated during builds)
- `config/` - Environment setup and tool bootstrapping
- `logs/` - Build logs with timestamps

### Important Environment Variables
- `PARTS_DIR="./parts"` - Source checkout directory
- `INSTALL_PREFIX="/usr/local/$NAME"` - Per-component install prefix
- `DISABLE_EXTENSION_TESTS=true` - Skip extension regression tests
- `USE_PGXS=1` - Use PostgreSQL extension build infrastructure

## Configuration

### bom.yaml Structure
- Each component defines: `name`, `url`, `branch`, `configure_flags`, `steps`, `env`
- Components grouped by: `dependencies`, `core`, `extensions`, `components`
- Steps executed in order: typically `clone → configure → build → install → test`

### Testing
- Unit tests: `unittest-cloudberry.sh`
- Extension tests: Built into `postgres-extension.sh` via `make installcheck`
- Demo cluster: `create-demo-cluster-cloudberry.sh`
- Individual tests: `test-<component>.sh` stations

## Common Issues

### bom.yaml Fixes
- Line 116 has duplicate `components:` key - should be renamed to `tools:` or similar
- Using personal fork for core Cloudberry component instead of official Apache repo

### Extension Build Notes
- Most extensions have `DISABLE_EXTENSION_TESTS: true` to skip regression tests
- Extensions use `--with-cloudberry-core=/usr/local/cloudberry` configure flag
- PostgreSQL extensions use PGXS build system via `postgres-extension.sh`