#!/bin/sh
# --------------------------------------------------------------------
# File     : stations/dependencies/proj/install.sh
# Purpose  : Install step for PROJ library
# Inputs   :
#   - NAME              : component name (should be "proj")
# --------------------------------------------------------------------

set -e

[ -f config/env.sh ] && . config/env.sh

# Validate input
if [ -z "$NAME" ]; then
  echo "Error: NAME is not set"
  exit 1
fi

# Navigate to PROJ extracted directory
PROJ_EXTRACT_DIR="$PARTS_DIR/$NAME/proj-6.0.0"
cd "$PROJ_EXTRACT_DIR" || {
  echo "Error: Directory '$PROJ_EXTRACT_DIR' not found"
  exit 1
}

echo "==> Installing $NAME..."
echo "    Working directory: $PROJ_EXTRACT_DIR"

# Install with parallel jobs
NPROC=$(nproc 2>/dev/null || echo 4)
echo "    Using $NPROC parallel jobs"

sudo make -j"$NPROC" install 2>&1 | tee "install-$(date '+%Y%m%d-%H%M%S').log"

echo "✅ install step complete for $NAME"