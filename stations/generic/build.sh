#!/usr/bin/env bash
set -euo pipefail

# Load shared environment
[ -f config/env.sh ] && . config/env.sh

NAME="${NAME:?Component name (NAME) must be provided}"
BUILD_DIR="$PARTS_DIR/$NAME"

echo "[build] Component: $NAME"

# Validate build directory
if [[ ! -d "$BUILD_DIR" ]]; then
  echo "[build] ERROR: Build directory '$BUILD_DIR' not found."
  exit 1
fi

cd "$BUILD_DIR"

# Find the actual source directory (handle extracted tarballs)
if [ ! -f "./Makefile" ]; then
  # Look for Makefile in subdirectories (common for tarballs)
  SUBDIR=$(find . -maxdepth 2 -name "Makefile" -type f | head -1 | xargs dirname)
  if [ -n "$SUBDIR" ] && [ -f "$SUBDIR/Makefile" ]; then
    echo "[build] Found Makefile in: $SUBDIR"
    cd "$SUBDIR" || exit 1
  else
    echo "[build] ERROR: No Makefile found in $BUILD_DIR"
    exit 1
  fi
fi

# Perform build
make -j"$(nproc)" 2>&1 | tee "$BUILD_DIR/make-build-$(date '+%Y%m%d-%H%M%S').log"

echo "[build] ✅ Build complete for $NAME"
