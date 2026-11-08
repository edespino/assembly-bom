#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "polaris" ]]; then
  echo "[polaris-run] ERROR: this step is polaris-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
gradlew=$(find "$PARTS_DIR/$NAME" -maxdepth 3 -type f -name gradlew | head -1)
src=$(dirname "$gradlew")
dist=$(find "$src/runtime/server/build/distributions" -name 'polaris-server-*.zip' | head -1)
run_home="$HOME/polaris-run"
if [[ -f "$run_home/polaris.pid" ]]; then
  old=$(cat "$run_home/polaris.pid" || true)
  if [[ -n "${old:-}" ]]; then
    kill "$old" 2>/dev/null || true
    sleep 1
  fi
fi
pkill -f 'quarkus-run.jar' 2>/dev/null || true
rm -rf "$run_home"
mkdir -p "$run_home"
unzip -q "$dist" -d "$run_home"
jar=$(find "$run_home" -name quarkus-run.jar | head -1)
if [[ -z "$jar" ]]; then
  echo "[polaris-run] ERROR: quarkus-run.jar not in $dist" >&2
  exit 1
fi
if [[ -f "$run_home/polaris.pid" ]]; then
  old=$(cat "$run_home/polaris.pid" || true)
  if [[ -n "$old" ]]; then
    kill "$old" 2>/dev/null || true
  fi
fi
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
export AWS_REGION=us-west-2
export AWS_DEFAULT_REGION=us-west-2
# Upstream quickstart bootstrap. Not an AWS credential.
export POLARIS_BOOTSTRAP_CREDENTIALS='POLARIS,root,s3cr3t'
cd "$(dirname "$jar")"
nohup java \
  -Dpolaris.realm-context.realms=POLARIS \
  -Dquarkus.otel.sdk.disabled=true \
  -jar "$(basename "$jar")" \
  > "$run_home/polaris.log" 2>&1 &
echo $! > "$run_home/polaris.pid"
ok=0
for _ in $(seq 1 60); do
  if curl -fsS --max-time 2 http://127.0.0.1:8182/q/health >/dev/null; then
    ok=1
    break
  fi
  sleep 2
done
if [[ "$ok" != 1 ]]; then
  echo "[polaris-run] ERROR: health check failed" >&2
  tail -40 "$run_home/polaris.log" >&2 || true
  exit 1
fi
echo "[polaris-run] RESULT: PASS"
