#!/usr/bin/env bash
COMPONENT_NAME="$1"
REPO_URL="$2"
BRANCH="$3"
CONFIGURE_FLAGS="$4"

echo "[build] Component: $COMPONENT_NAME"
echo "[build] Repo URL:  $REPO_URL"
echo "[build] Branch:    $BRANCH"
echo "[build] Flags:     $CONFIGURE_FLAGS"
