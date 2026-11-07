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

if ! listing=$(unzip -Z1 "$zip"); then
  echo "[seata-rat] ERROR: cannot list archive members"
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
      echo "[seata-rat] ERROR: unsafe archive member"
      exit 1
      ;;
  esac
  top=${member%%/*}
  if [[ "$top" == .* ]]; then
    echo "[seata-rat] ERROR: archive member is not under one project directory"
    exit 1
  fi
  if [[ -z "$prefix" ]]; then
    prefix=$top
  elif [[ "$top" != "$prefix" ]]; then
    echo "[seata-rat] ERROR: archive member ${top} is outside ${prefix}"
    exit 1
  fi
done <<< "$listing"
if [[ -z "$prefix" || "$prefix" == .* ]]; then
  echo "[seata-rat] ERROR: archive has no single project directory"
  exit 1
fi
echo "[seata-rat] Archive prefix: $prefix"

rm -rf "$fresh"
mkdir -p "$fresh"
unzip -q "$zip" -d "$fresh"
if ! members=$(find "$fresh" -mindepth 1 -maxdepth 1 -print); then
  echo "[seata-rat] ERROR: find failed while listing the extract"
  exit 1
fi
mapfile -t members < <(printf '%s\n' "$members" | sed '/^$/d')
if [[ ${#members[@]} -ne 1 ]]; then
  echo "[seata-rat] ERROR: expected one extracted entry, found ${#members[@]}"
  exit 1
fi
tree="${members[0]}"
if [[ -L "$tree" || ! -d "$tree" || "$(basename "$tree")" != "$prefix" ]]; then
  echo "[seata-rat] ERROR: extracted entry is not the archive prefix ${prefix}"
  exit 1
fi
echo "[seata-rat] Fresh extract: $tree"

if ! bad_dirs=$(cd "$tree" && find . -type d ! -perm -u=rx -print); then
  echo "[seata-rat] ERROR: find failed while checking directory permissions"
  exit 1
fi
if [[ -n "$bad_dirs" ]]; then
  echo "[seata-rat] ERROR: extracted directory is missing owner read and search"
  printf '%s\n' "$bad_dirs" | head -20 | sed 's/^/[seata-rat] /'
  exit 1
fi

# Before any -f or grep. Those follow symlinks.
if ! preexisting=$(cd "$tree" && find . \( -name target -o -type l \) -print); then
  echo "[seata-rat] ERROR: find failed while scanning the extract for target entries"
  exit 1
fi
mapfile -t preexisting < <(printf '%s\n' "$preexisting" | sed '/^$/d')
if [[ ${#preexisting[@]} -ne 0 ]]; then
  echo "[seata-rat] ERROR: extracted tree contains a target entry or a symlink."
  printf '%s\n' "${preexisting[@]}" | head -20 | sed 's/^/[seata-rat] /'
  exit 1
fi

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

root_report="$tree/target/rat.txt"
if [[ ! -f "$root_report" ]]; then
  echo "[seata-rat] ERROR: root RAT report missing: $root_report"
  echo "[seata-rat] A child target/rat.txt is not the reactor report. -fn can exit 0 anyway."
  exit 1
fi
reports=("$root_report")
if ! child_reports=$(cd "$tree" && find . -path '*/target/rat.txt' -print); then
  echo "[seata-rat] ERROR: find failed while listing RAT reports"
  exit 1
fi
while IFS= read -r extra; do
  [[ -z "$extra" ]] && continue
  extra_abs="$tree/${extra#./}"
  [[ "$extra_abs" == "$root_report" ]] && continue
  reports+=("$extra_abs")
done < <(printf '%s\n' "$child_reports" | sed '/^$/d' | sort)
# -fn makes Maven exit 0 even when RAT fails. The report is the gate.
# A report with no recognized count is a failure, not a zero.
unapproved_total=0
for report in "${reports[@]}"; do
  echo "[seata-rat] Report: $report"
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
    echo "[seata-rat] ERROR: unrecognized RAT summary in $report"
    exit 1
  fi
  echo "[seata-rat] REPORT_COUNT: $count $report"
  unapproved_total=$((unapproved_total + count))
  awk '
    $0 ~ /Files with unapproved licenses/ {grab=1; next}
    grab && $0 ~ /Detail/ {exit}
    grab && $0 ~ /^  \// {print}
  ' "$report" | sed 's/^/[seata-rat] /'
done
echo "[seata-rat] RAT_REPORTS: ${#reports[@]}"
echo "[seata-rat] UNAPPROVED_TOTAL: $unapproved_total"
if [[ "$unapproved_total" -ne 0 ]]; then
  echo "[seata-rat] RESULT: FAIL"
  exit 1
fi
echo "[seata-rat] RESULT: PASS"
exit 0
