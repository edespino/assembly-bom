#!/usr/bin/env bash
# Header check is the project's declared apache-rat-plugin 0.15.
# The pom declares the plugin. Do not invoke 0.18, and do not use the
# inherited parent goal. Scan a fresh extract. Pass -fn so one module
# does not hide the rest of the reactor.
# Compiled-suffix count is taken before Maven writes target/.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "amoro" ]]; then
  echo "[amoro-rat] ERROR: this step is amoro-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"
archive="$PARTS_DIR/${NAME}-artifacts/apache-amoro-${RELEASE_VERSION}-incubating-src.tar.gz"
fresh="$PARTS_DIR/review-output/$NAME/rat-extract"

java11=""
for candidate in /usr/lib/jvm/java-11-openjdk /usr/lib/jvm/java-11 /usr/lib/jvm/java-11-openjdk-11; do
  if [[ -x "$candidate/bin/java" ]]; then
    java11=$candidate
    break
  fi
done
if [[ -z "$java11" ]]; then
  echo "[amoro-rat] ERROR: Java 11 home not found. Run prepare first."
  exit 1
fi
export JAVA_HOME="$java11"
export PATH="${JAVA_HOME}/bin:${PATH}"

echo "[amoro-rat] Plugin: the pom's apache-rat-plugin, via ./mvnw apache-rat:check"
echo "[amoro-rat] JAVA_HOME: $JAVA_HOME"
echo "[amoro-rat] $($JAVA_HOME/bin/java -version 2>&1 | head -1)"
echo "[amoro-rat] Pom excludes are the project's own exclusions."

if [[ ! -f "$archive" ]]; then
  echo "[amoro-rat] ERROR: source tar not found"
  exit 1
fi

rm -rf "$fresh"
mkdir -p "$fresh"
tar -xzf "$archive" -C "$fresh"
mapfile -t trees < <(find "$fresh" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[amoro-rat] ERROR: expected one extracted tree, found ${#trees[@]}"
  exit 1
fi
tree="${trees[0]}"
echo "[amoro-rat] Fresh extract: $tree"

if [[ ! -f "$tree/pom.xml" || ! -f "$tree/mvnw" ]]; then
  echo "[amoro-rat] ERROR: extracted tree is missing pom.xml or mvnw"
  exit 1
fi
if ! grep -q '<artifactId>apache-rat-plugin</artifactId>' "$tree/pom.xml"; then
  echo "[amoro-rat] ERROR: pom does not declare apache-rat-plugin. Refusing the inherited goal."
  exit 1
fi
chmod +x "$tree/mvnw"

echo "[amoro-rat] Compiled suffixes in the source archive, before the RAT run writes target/:"
set +o pipefail
compiled=$(find "$tree" -type f \( -name '*.class' -o -name '*.jar' -o -name '*.so' -o -name '*.o' -o -name '*.a' -o -name '*.exe' -o -name '*.dll' \) | sed "s|^$tree/||" | sort)
set -o pipefail
compiled_count=0
if [[ -n "$compiled" ]]; then
  compiled_count=$(printf '%s\n' "$compiled" | wc -l | tr -d ' ')
  printf '%s\n' "$compiled" | head -20 | sed 's/^/[amoro-rat] compiled: /'
fi
echo "[amoro-rat] COMPILED_SUFFIX_COUNT: $compiled_count"

log="$PARTS_DIR/review-output/$NAME/rat.log"
rm -f "$log"
set +e
(
  cd "$tree"
  ./mvnw -B -ntp -fn apache-rat:check
) 2>&1 | tee "$log"
rat_rc=${PIPESTATUS[0]}
set -e
echo "[amoro-rat] RAT_MAVEN_EXIT: $rat_rc"
grep -E '^[[:space:]]*Rat check: Summary|^[[:space:]]*! Unapproved:|^[[:space:]]*Unapproved:|^[[:space:]]*[0-9]+ Unknown Licenses|^[[:space:]]*Unknown Licenses:' "$log" | sed 's/^/[amoro-rat] /' || true

mapfile -t reports < <(find "$tree" -path '*/target/rat.txt' | sort)
root_report="$tree/target/rat.txt"
if [[ ! -f "$root_report" ]]; then
  echo "[amoro-rat] ERROR: root RAT report missing: $root_report"
  echo "[amoro-rat] A child target/rat.txt is not the reactor report. -fn can exit 0 anyway."
  exit 1
fi
if [[ ${#reports[@]} -eq 0 ]]; then
  echo "[amoro-rat] ERROR: RAT did not write a report"
  exit 1
fi
# -fn makes Maven exit 0 even when RAT fails. The report is the gate.
# Plugin 0.15 writes "N Unknown Licenses". Plugin 0.18 writes "Unapproved:".
# A report with neither line is a failure, not a zero.
unapproved_total=0
for report in "${reports[@]}"; do
  set +e
  count=$(awk '
    /! Unapproved:/ { print $3; found=1; exit }
    /^[[:space:]]*Unapproved:/ { print $2; found=1; exit }
    /^[[:space:]]*Unknown Licenses:[[:space:]]*[0-9]+/ { print $3; found=1; exit }
    /^[[:space:]]*[0-9]+ Unknown Licenses/ { print $1; found=1; exit }
    END { if (!found) exit 2 }
  ' "$report")
  parse_rc=$?
  set -e
  if [[ "$parse_rc" -ne 0 || ! "$count" =~ ^[0-9]+$ ]]; then
    echo "[amoro-rat] ERROR: unrecognized RAT summary in $report"
    exit 1
  fi
  echo "[amoro-rat] REPORT_COUNT: $count $report"
  unapproved_total=$((unapproved_total + count))
done
echo "[amoro-rat] RAT_REPORTS: ${#reports[@]}"
echo "[amoro-rat] UNAPPROVED_TOTAL: $unapproved_total"

fail=0
if [[ "$compiled_count" -ne 0 ]]; then
  echo "[amoro-rat] ERROR: compiled suffixes in the source archive"
  fail=1
fi
if [[ "$unapproved_total" -ne 0 ]]; then
  echo "[amoro-rat] ERROR: unapproved files under the project's pom excludes"
  fail=1
fi
if [[ "$fail" -ne 0 ]]; then
  echo "[amoro-rat] RESULT: FAIL"
  exit 1
fi
echo "[amoro-rat] RESULT: PASS"
exit 0
