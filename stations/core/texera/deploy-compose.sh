#!/usr/bin/env bash
# The vote checklist item is a Docker Compose deploy, not an sbt build.
# The bundle's .env already sets IMAGE_REGISTRY and IMAGE_TAG. Do not print it.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "texera" ]]; then
  echo "[texera-deploy-compose] ERROR: this step is texera-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
review_dir="$PARTS_DIR/${NAME}-compose"
mapfile -t tops < <(find "$review_dir" -mindepth 1 -maxdepth 1 -type d -print)
if [[ ${#tops[@]} -ne 1 || ! -f "${tops[0]}/docker-compose.yml" ]]; then
  echo "[texera-deploy-compose] ERROR: compose tree missing. Run review-binary first."
  exit 1
fi
root="${tops[0]}"
echo "[texera-deploy-compose] Directory: $root"
cd "$root"
docker compose --profile examples up -d
echo "[texera-deploy-compose] Waiting 60s for containers"
sleep 60
docker compose --profile examples ps
# Init containers exit 0 on purpose. Fail only a non-zero exit, a dead
# container, or an unhealthy healthcheck.
bad=$(docker compose --profile examples ps -a --format '{{.Service}}|{{.ExitCode}}|{{.Status}}' | awk -F'|' '$2 != "0" || $3 ~ /[Dd]ead|[Uu]nhealthy/ { print }')
if [[ -n "$bad" ]]; then
  echo "[texera-deploy-compose] ERROR: failed services:"
  printf '%s\n' "$bad"
  echo "[texera-deploy-compose] RESULT: FAIL"
  exit 1
fi
running=$(docker compose --profile examples ps --status running --format '{{.Service}}' | sed '/^$/d' | wc -l)
echo "[texera-deploy-compose] Running services: $running"
if [[ "$running" -lt 1 ]]; then
  echo "[texera-deploy-compose] ERROR: no running service"
  echo "[texera-deploy-compose] RESULT: FAIL"
  exit 1
fi
echo "[texera-deploy-compose] RESULT: PASS"
exit 0
