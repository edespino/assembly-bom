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

if ! listing=$(tar -tzf "$archive"); then
  echo "[amoro-rat] ERROR: cannot list archive members"
  exit 1
fi
prefix=""
while IFS= read -r member; do
  [[ -z "$member" ]] && continue
  member=${member#./}
  member=${member%/}
  [[ -z "$member" ]] && continue
  case "$member" in
    /*|..|../*|*/..|*/../*)
      echo "[amoro-rat] ERROR: unsafe archive member"
      exit 1
      ;;
  esac
  top=${member%%/*}
  if [[ "$top" == .* ]]; then
    echo "[amoro-rat] ERROR: archive member is not under one project directory"
    exit 1
  fi
  if [[ -z "$prefix" ]]; then
    prefix=$top
  elif [[ "$top" != "$prefix" ]]; then
    echo "[amoro-rat] ERROR: archive member ${top} is outside ${prefix}"
    exit 1
  fi
done <<< "$listing"
if [[ -z "$prefix" || "$prefix" == .* ]]; then
  echo "[amoro-rat] ERROR: archive has no single project directory"
  exit 1
fi
echo "[amoro-rat] Archive prefix: $prefix"

rm -rf "$fresh"
mkdir -p "$fresh"
tar -xzf "$archive" -C "$fresh"
if ! members=$(find "$fresh" -mindepth 1 -maxdepth 1 -print); then
  echo "[amoro-rat] ERROR: find failed while listing the extract"
  exit 1
fi
mapfile -t members < <(printf '%s\n' "$members" | sed '/^$/d')
if [[ ${#members[@]} -ne 1 ]]; then
  echo "[amoro-rat] ERROR: expected one extracted entry, found ${#members[@]}"
  exit 1
fi
tree="${members[0]}"
if [[ -L "$tree" || ! -d "$tree" || "$(basename "$tree")" != "$prefix" ]]; then
  echo "[amoro-rat] ERROR: extracted entry is not the archive prefix ${prefix}"
  exit 1
fi
echo "[amoro-rat] Fresh extract: $tree"

if ! bad_dirs=$(cd "$tree" && find . -type d ! -perm -u=rx -print); then
  echo "[amoro-rat] ERROR: find failed while checking directory permissions"
  exit 1
fi
if [[ -n "$bad_dirs" ]]; then
  echo "[amoro-rat] ERROR: extracted directory is missing owner read and search"
  printf '%s\n' "$bad_dirs" | head -20 | sed 's/^/[amoro-rat] /'
  exit 1
fi

# Before any -f, grep, or chmod. Those follow symlinks and can change a
# file outside the extract.
if ! preexisting=$(cd "$tree" && find . \( -name target -o -type l \) -print); then
  echo "[amoro-rat] ERROR: find failed while scanning the extract for target entries"
  exit 1
fi
mapfile -t preexisting < <(printf '%s\n' "$preexisting" | sed '/^$/d')
if [[ ${#preexisting[@]} -ne 0 ]]; then
  echo "[amoro-rat] ERROR: extracted tree contains a target entry or a symlink."
  printf '%s\n' "${preexisting[@]}" | head -20 | sed 's/^/[amoro-rat] /'
  exit 1
fi

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
if ! compiled=$(cd "$tree" && find . -type f \( -name '*.class' -o -name '*.jar' -o -name '*.so' -o -name '*.o' -o -name '*.a' -o -name '*.exe' -o -name '*.dll' \) -print); then
  echo "[amoro-rat] ERROR: find failed while counting compiled suffixes"
  exit 1
fi
compiled=$(printf '%s\n' "$compiled" | sed '/^$/d; s|^\./||' | sort)
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

root_report="$tree/target/rat.txt"
if [[ ! -f "$root_report" ]]; then
  echo "[amoro-rat] ERROR: root RAT report missing: $root_report"
  echo "[amoro-rat] A child target/rat.txt is not the reactor report. -fn can exit 0 anyway."
  exit 1
fi
reports=("$root_report")
if ! child_reports=$(cd "$tree" && find . -path '*/target/rat.txt' -print); then
  echo "[amoro-rat] ERROR: find failed while listing RAT reports"
  exit 1
fi
while IFS= read -r extra; do
  [[ -z "$extra" ]] && continue
  extra_abs="$tree/${extra#./}"
  [[ "$extra_abs" == "$root_report" ]] && continue
  reports+=("$extra_abs")
done < <(printf '%s\n' "$child_reports" | sed '/^$/d' | sort)
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
