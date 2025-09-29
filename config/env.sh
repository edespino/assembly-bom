#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Display environment setup for visibility
echo "[env] Loading geospatial library environment configuration..."

# Helper function to build paths with validation
build_path() {
  local path_type="$1"
  local base_var="$2"
  shift 2
  local validated_paths=""
  local missing_paths=""

  for path in "$@"; do
    if [[ -d "$path" ]]; then
      if [[ -z "$validated_paths" ]]; then
        validated_paths="$path"
      else
        validated_paths="$validated_paths:$path"
      fi
    else
      if [[ -z "$missing_paths" ]]; then
        missing_paths="$path"
      else
        missing_paths="$missing_paths:$path"
      fi
    fi
  done

  # Add existing base paths if any
  if [[ -n "${!base_var:-}" ]]; then
    if [[ -n "$validated_paths" ]]; then
      validated_paths="$validated_paths:${!base_var}"
    else
      validated_paths="${!base_var}"
    fi
  fi

  echo "$validated_paths"

  # Report missing paths (suppressed to reduce noise)
  # if [[ -n "$missing_paths" ]]; then
  #   echo "[env] ⚠ Missing $path_type directories: $missing_paths" >&2
  # fi
}

# Default parts directory for component checkouts
export PARTS_DIR="$HOME/bom-parts"
mkdir -p "$PARTS_DIR"

# Geospatial library paths for PostGIS and dependencies
export LD_LIBRARY_PATH=$(build_path "LD_LIBRARY" "LD_LIBRARY_PATH" \
  "/usr/local/cgal-5.6.1/lib64" \
  "/usr/local/geos-3.11.0/lib64" \
  "/usr/local/sfcgal-1.4.1/lib64" \
  "/usr/local/gdal-3.5.3/lib" \
  "/usr/local/proj6/lib")
echo "[env] LD_LIBRARY_PATH: $LD_LIBRARY_PATH"

# PKG_CONFIG paths for geospatial libraries (CGAL uses CMake config instead)
export PKG_CONFIG_PATH=$(build_path "PKG_CONFIG" "PKG_CONFIG_PATH" \
  "/usr/local/geos-3.11.0/lib64/pkgconfig" \
  "/usr/local/sfcgal-1.4.1/lib64/pkgconfig" \
  "/usr/local/gdal-3.5.3/lib/pkgconfig" \
  "/usr/local/proj6/lib/pkgconfig")
echo "[env] PKG_CONFIG_PATH: $PKG_CONFIG_PATH"

# CMake paths for finding installed packages
export CMAKE_PREFIX_PATH=$(build_path "CMAKE_PREFIX" "CMAKE_PREFIX_PATH" \
  "/usr/local/cgal-5.6.1" \
  "/usr/local/geos-3.11.0" \
  "/usr/local/sfcgal-1.4.1" \
  "/usr/local/gdal-3.5.3" \
  "/usr/local/proj6")
echo "[env] CMAKE_PREFIX_PATH: $CMAKE_PREFIX_PATH"

# Cloudberry/PostgreSQL environment
export GPHOME="${GPHOME:-/usr/local/cloudberry}"
if [[ -d "$GPHOME" ]]; then
  echo "[env] GPHOME: $GPHOME"
else
  echo "[env] ⚠ GPHOME directory does not exist: $GPHOME" >&2
  echo "[env] GPHOME: $GPHOME (missing)"
fi
echo "[env] Environment configuration complete"
