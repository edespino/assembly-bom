#!/usr/bin/env bash
# XTable RAT. The pom declares apache-rat-plugin 0.16.1 and the tree ships mvnw.
# Do not use stations/generic/apache-rat.sh: that script uses mvn on PATH and
# does not pass -fn. Do not substitute plugin 0.18.
# README says build with Java 11. The compiler release in the pom is 8.
# The JVM that launches the plugin is Java 11, the README build Java.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "xtable" ]]; then
  echo "[xtable-rat] ERROR: this step is xtable-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
logdir="$PARTS_DIR/review-output/$NAME"
mkdir -p "$logdir"

mapfile -t trees < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[xtable-rat] ERROR: expected one extracted tree, found ${#trees[@]}"
  exit 1
fi
tree="${trees[0]}"
if [[ ! -f "$tree/pom.xml" || ! -f "$tree/mvnw" ]]; then
  echo "[xtable-rat] ERROR: extracted tree has no pom.xml and mvnw"
  exit 1
fi

if [[ -x /usr/lib/jvm/java-11-openjdk/bin/java ]]; then
  export JAVA_HOME=/usr/lib/jvm/java-11-openjdk
elif [[ -x /usr/lib/jvm/java-11/bin/java ]]; then
  export JAVA_HOME=/usr/lib/jvm/java-11
else
  echo "[xtable-rat] ERROR: Java 11 home not found. README requires Java 11."
  exit 1
fi
export PATH="$JAVA_HOME/bin:$PATH"
echo "[xtable-rat] JAVA_HOME=$JAVA_HOME"
java -version

mapfile -t compiled < <(find "$tree" -type f \( -name '*.class' -o -name '*.jar' -o -name '*.so' -o -name '*.o' -o -name '*.a' -o -name '*.exe' -o -name '*.dll' \) | sort)
echo "[xtable-rat] COMPILED_COUNT: ${#compiled[@]}"
if [[ ${#compiled[@]} -ne 0 ]]; then
  echo "[xtable-rat] ERROR: compiled files in the source archive"
  printf '%s\n' "${compiled[@]:0:20}"
  exit 1
fi
echo "[xtable-rat] No compiled binaries in the source archive"

if ! out=$(cd "$tree" && find . \( -name target -o -type l \)); then
  echo "[xtable-rat] ERROR: find failed inside the extract"
  exit 1
fi
if [[ -n "$out" ]]; then
  echo "[xtable-rat] ERROR: extract contains a target entry or a symlink"
  printf '%s\n' "$out"
  exit 1
fi

cd "$tree"
rm -f target/rat.txt
set +e
bash ./mvnw -B -ntp -fn apache-rat:check > "$logdir/rat-maven.log" 2>&1
mvn_rc=$?
set -e
echo "[xtable-rat] MAVEN_EXIT: $mvn_rc"
if [[ "$mvn_rc" -ne 0 ]]; then
  echo "[xtable-rat] ERROR: Maven did not finish"
  tail -40 "$logdir/rat-maven.log"
  exit 1
fi

report="$tree/target/rat.txt"
if [[ ! -f "$report" ]]; then
  echo "[xtable-rat] ERROR: root target/rat.txt is missing"
  exit 1
fi

unapproved=$(awk '
  /! Unapproved:/ { print $3; found=1; exit }
  /^[[:space:]]*Unapproved:/ { print $2; found=1; exit }
  /^[[:space:]]*Unknown Licenses:[[:space:]]*[0-9]+/ { print $3; found=1; exit }
  /^[[:space:]]*[0-9]+ Unknown Licenses/ { print $1; found=1; exit }
  END { if (!found) exit 1 }
' "$report") || {
  echo "[xtable-rat] ERROR: root rat.txt has no recognized summary line"
  exit 1
}
echo "[xtable-rat] UNAPPROVED: $unapproved"
if [[ "$unapproved" != "0" ]]; then
  echo "[xtable-rat] ERROR: unapproved count is $unapproved"
  exit 1
fi
if grep -q 'Build failures were ignored\.' "$logdir/rat-maven.log"; then
  echo "[xtable-rat] ERROR: Maven ignored a module failure"
  exit 1
fi
echo "[xtable-rat] RESULT: PASS"
exit 0
