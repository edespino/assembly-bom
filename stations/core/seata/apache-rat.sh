#!/usr/bin/env bash
# Required header check: Apache RAT 0.18.
# The tree has pom.xml and does not declare apache-rat-plugin.
# mvn apache-rat:check resolves the inherited parent plugin 0.12.
# That is not this check. Invoke the 0.18 goal explicitly.
# Scan a fresh extract. A post-build tree has target/ and is not the archive.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "seata" ]]; then
  echo "[seata-rat] ERROR: this step is seata-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"
zip="$PARTS_DIR/${NAME}-artifacts/apache-seata-${RELEASE_VERSION}-incubating-src.zip"
fresh="$PARTS_DIR/review-output/$NAME/rat-extract"
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH="${HOME}/opt/apache-maven-3.9.16/bin:${JAVA_HOME}/bin:${PATH}"

echo "[seata-rat] RAT plugin: org.apache.rat:apache-rat-plugin:0.18:check"
echo "[seata-rat] JAVA_HOME: $JAVA_HOME"
echo "[seata-rat] $($JAVA_HOME/bin/java -version 2>&1 | head -1)"
echo "[seata-rat] $(mvn -version | head -1)"

if [[ ! -x "$JAVA_HOME/bin/java" || ! -x "${HOME}/opt/apache-maven-3.9.16/bin/mvn" ]]; then
  echo "[seata-rat] ERROR: Java 17 or Maven 3.9.16 is missing. Run prepare first."
  exit 1
fi
if [[ ! -f "$zip" ]]; then
  echo "[seata-rat] ERROR: source zip not found: $zip"
  exit 1
fi

rm -rf "$fresh"
mkdir -p "$fresh"
unzip -q "$zip" -d "$fresh"
mapfile -t trees < <(find "$fresh" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[seata-rat] ERROR: expected one extracted tree, found ${#trees[@]}"
  exit 1
fi
tree="${trees[0]}"
echo "[seata-rat] Fresh extract: $tree"

log="$PARTS_DIR/review-output/$NAME/rat-0.18.log"
set +e
(
  cd "$tree"
  mvn -B -ntp -fn org.apache.rat:apache-rat-plugin:0.18:check
) 2>&1 | tee "$log"
rat_rc=${PIPESTATUS[0]}
set -e
echo "[seata-rat] RAT_MAVEN_EXIT: $rat_rc"
grep -E 'Rat check: Summary|Unapproved:' "$log" | sed 's/^/[seata-rat] /' || true

reports=$(find "$tree" -path '*/target/rat.txt' -print | sort)
if [[ -z "$reports" ]]; then
  echo "[seata-rat] ERROR: RAT did not write a report"
  exit 1
fi
unapproved_total=0
while IFS= read -r report; do
  echo "[seata-rat] Report: $report"
  grep -E '^[[:space:]]*! Unapproved:' "$report" | sed 's/^/[seata-rat] /' || true
  count=$(awk '/! Unapproved:/ {print $3; exit} /^[[:space:]]*Unapproved:/ {print $2; exit}' "$report")
  unapproved_total=$((unapproved_total + ${count:-0}))
  awk '
    $0 ~ /Files with unapproved licenses/ {grab=1; next}
    grab && $0 ~ /Detail/ {exit}
    grab && $0 ~ /^  \// {print}
  ' "$report" | sed 's/^/[seata-rat] /'
done <<< "$reports"
echo "[seata-rat] UNAPPROVED_TOTAL: $unapproved_total"
if [[ "$unapproved_total" -ne 0 ]]; then
  echo "[seata-rat] RESULT: FAIL"
  exit 1
fi
echo "[seata-rat] RESULT: PASS"
exit 0
