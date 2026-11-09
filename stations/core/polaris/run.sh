#!/usr/bin/env bash
set -euo pipefail
NAME="${NAME:?Missing NAME}"
if [[ "$NAME" != "polaris" ]]; then
  echo "[polaris-run] ERROR: this step is polaris-only" >&2
  exit 1
fi
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
jar="$PARTS_DIR/$NAME/from-artifact/quarkus-app/quarkus-run.jar"
if [[ ! -f "$jar" ]]; then
  gradlew=$(find "$PARTS_DIR/$NAME" -maxdepth 3 -type f -name gradlew | head -1)
  src=$(dirname "$gradlew")
  jar="$src/runtime/server/build/quarkus-app/quarkus-run.jar"
fi
if [[ ! -f "$jar" ]]; then
  echo "[polaris-run] ERROR: $jar not found" >&2
  exit 1
fi
run_home="$HOME/polaris-run"
if [[ -f "$run_home/polaris.pid" ]]; then
  old=$(cat "$run_home/polaris.pid" || true)
  if [[ -n "${old:-}" ]]; then
    kill "$old" 2>/dev/null || true
    sleep 1
  fi
fi
pkill -f 'quarkus-run.jar' 2>/dev/null || true
mkdir -p "$run_home"
if [[ ! -x /usr/lib/jvm/java-21-openjdk/bin/java ]]; then
  echo "[polaris-run] ERROR: Java 21 is not on this image at /usr/lib/jvm/java-21-openjdk" >&2
  exit 1
fi
export JAVA_HOME=/usr/lib/jvm/java-21-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"
export AWS_REGION=us-west-2
export AWS_DEFAULT_REGION=us-west-2
# Upstream quickstart bootstrap. Not an AWS credential.
export POLARIS_BOOTSTRAP_CREDENTIALS='POLARIS,root,s3cr3t'
cd "$(dirname "$jar")"
nohup "$JAVA_HOME/bin/java" \
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
