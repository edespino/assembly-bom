#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Validate inputs
COMPONENT_NAME="${1:?Missing component name}"
REPO_URL="${2:?Missing repository URL}"
BRANCH="${3:?Missing branch name}"

PARTS_DIR="./parts"
COMPONENT_DIR="$PARTS_DIR/$COMPONENT_NAME"

echo "[clone] Component: $COMPONENT_NAME"
echo "[clone] Repo URL:  $REPO_URL"
echo "[clone] Branch:    $BRANCH"

if [[ -d "$COMPONENT_DIR/.git" ]]; then
  echo "[clone] $COMPONENT_NAME already exists. Fetching latest from $BRANCH..."
  git -C "$COMPONENT_DIR" fetch origin
  git -C "$COMPONENT_DIR" checkout "$BRANCH"
  git -C "$COMPONENT_DIR" pull
else
  echo "[clone] Cloning $COMPONENT_NAME into $COMPONENT_DIR"
  git clone --branch "$BRANCH" "$REPO_URL" "$COMPONENT_DIR"
fi

# Always update submodules to ensure consistency
echo "[clone] Initializing submodules (if any)..."
git -C "$COMPONENT_DIR" submodule update --init --recursive
