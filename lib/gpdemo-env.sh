#!/usr/bin/env bash
# The installed gpdemo writes gpdemo-env.sh in the caller's cwd.
# create-demo-cluster.sh runs it from $HOME/gpdemo. Later steps source that file.
gpdemo_env_file() {
  if [[ -n "${GPDEMO_ENV:-}" && -f "$GPDEMO_ENV" ]]; then
    printf '%s\n' "$GPDEMO_ENV"
    return 0
  fi
  if [[ -f "${HOME}/gpdemo/gpdemo-env.sh" ]]; then
    printf '%s\n' "${HOME}/gpdemo/gpdemo-env.sh"
    return 0
  fi
  local parts="${PARTS_DIR:-$HOME/bom-parts}"
  local found
  found=$(find "$parts" -name gpdemo-env.sh 2>/dev/null | head -1 || true)
  if [[ -n "$found" ]]; then
    printf '%s\n' "$found"
    return 0
  fi
  return 1
}
