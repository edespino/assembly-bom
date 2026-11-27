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
# A leftover volume keeps the previous database. Postgres init scripts
# run only when that volume is empty, so a second run would judge the
# earlier stack. The bundle README names down -v before up.
docker compose --profile examples down -v --remove-orphans
docker compose --profile examples up -d

deadline=$((SECONDS + 600))
while true; do
  docker compose --profile examples ps -a
  rows=$(docker compose --profile examples ps -a --format '{{.Service}}|{{.State}}|{{.ExitCode}}|{{.Health}}|{{.Status}}')
  bad=$(printf '%s\n' "$rows" | awk -F'|' '
    $2 ~ /[Dd]ead/ || $5 ~ /[Uu]nhealthy/ || $4 ~ /[Uu]nhealthy/ { print; next }
    $2 ~ /exited/ && $3 != "0" { print }
  ')
  if [[ -n "$bad" ]]; then
    echo "[texera-deploy-compose] ERROR: failed services:"
    printf '%s\n' "$bad"
    echo "[texera-deploy-compose] RESULT: FAIL"
    exit 1
  fi
  loader=$(printf '%s\n' "$rows" | awk -F'|' '$1 == "example-data-loader" { print; exit }')
  starting=$(printf '%s\n' "$rows" | awk -F'|' '$4 ~ /[Ss]tarting/ || $5 ~ /[Ss]tarting/ { print }')
  loader_done=0
  if [[ -n "$loader" ]] && printf '%s\n' "$loader" | awk -F'|' '$2 ~ /exited/ && $3 == "0" { found=1 } END { exit !found }'; then
    loader_done=1
  fi
  if [[ "$loader_done" -eq 1 && -z "$starting" ]]; then
    break
  fi
  if [[ "$SECONDS" -ge "$deadline" ]]; then
    echo "[texera-deploy-compose] ERROR: examples job or healthchecks did not finish in 600s"
    echo "[texera-deploy-compose] RESULT: FAIL"
    exit 1
  fi
  echo "[texera-deploy-compose] Waiting for example-data-loader and healthy services"
  sleep 10
done
running=$(docker compose --profile examples ps --status running --format '{{.Service}}' | sed '/^$/d' | wc -l | tr -d ' ')
echo "[texera-deploy-compose] Running services: $running"
if [[ "$running" -lt 1 ]]; then
  echo "[texera-deploy-compose] ERROR: no running service"
  echo "[texera-deploy-compose] RESULT: FAIL"
  exit 1
fi
echo "[texera-deploy-compose] RESULT: PASS"
exit 0
