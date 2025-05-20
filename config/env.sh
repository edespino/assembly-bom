#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Default parts directory for component checkouts
export PARTS_DIR="./parts"
mkdir -p "$PARTS_DIR"
