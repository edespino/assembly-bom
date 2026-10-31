#!/usr/bin/env bash
# Shared identity check for a source-release vote.
# Source this file. Do not list it as a station step.
# The vote request must set SOURCE_REPO and SOURCE_TAG.
# This file does not invent a GitHub URL from the component name.

apache_require_source_identity() {
  local repo="${SOURCE_REPO:-}"
  local tag="${SOURCE_TAG:-}"
  local resolved=""

  if ! command -v git >/dev/null 2>&1; then
    if command -v dnf >/dev/null 2>&1; then
      echo "[source-identity] Installing git. The tag cannot be validated without it."
      sudo dnf install -y git
      echo "[source-identity] Installed after launch: git"
    else
      echo "[source-identity] ERROR: git is required to validate the vote tag. This test will not start." >&2
      return 1
    fi
  fi

  if [[ -z "$repo" ]]; then
    echo "[source-identity] ERROR: SOURCE_REPO was not provided. The vote request must name the git remote. This test will not start." >&2
    return 1
  fi
  if [[ -z "$tag" ]]; then
    echo "[source-identity] ERROR: SOURCE_TAG was not provided. The vote request must name the tag or full commit. This test will not start." >&2
    return 1
  fi

  case "$repo" in
    *://*:*@*)
      echo "[source-identity] ERROR: SOURCE_REPO contains credentials. Refusing to use it." >&2
      return 1
      ;;
    https://*|git://*|ssh://*|file://*|git@*)
      ;;
    *)
      echo "[source-identity] ERROR: SOURCE_REPO is not a git remote URL. Do not guess github.com/apache/<name>. This test will not start." >&2
      return 1
      ;;
  esac

  if [[ ! "$tag" =~ ^[A-Za-z0-9._/+-]+$ ]] || [[ "$tag" == *".."* ]] || [[ "$tag" == -* ]]; then
    echo "[source-identity] ERROR: SOURCE_TAG is not a tag name or full commit. This test will not start." >&2
    return 1
  fi

  echo "[source-identity] IDENTITY_REPO: $repo"
  echo "[source-identity] IDENTITY_TAG: $tag"

  if [[ "$tag" =~ ^[0-9a-fA-F]{40}$ ]]; then
    resolved=$(git ls-remote "$repo" | awk -v want="$tag" 'BEGIN{IGNORECASE=1} $1==want {print $1; exit}')
  else
    resolved=$(git ls-remote --tags "$repo" "refs/tags/${tag}" | awk 'NR==1 {print $1}')
  fi

  if [[ -z "$resolved" ]]; then
    echo "[source-identity] ERROR: SOURCE_TAG ${tag} was not found on ${repo}. This test will not start." >&2
    return 1
  fi

  echo "[source-identity] IDENTITY_RESOLVED: $resolved"
  echo "[source-identity] RESULT: PASS"
  return 0
}
