#!/usr/bin/env bash
# JCasbin RAT. Do not use stations/generic/apache-rat.sh.
# The project pom runs apache-rat-plugin 0.18. That plugin needs Maven 3.9
# and Java 17 to launch. The image default is Maven 3.6.3 and Java 8.
# RAT 0.18 writes the path on one line and "B <media-type>" on the next.
# A png marked B is an image, not a compiled binary, and it is not excluded.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "jcasbin" ]]; then
  echo "[jcasbin-rat] ERROR: this step is jcasbin-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"

if [[ -x "${HOME}/opt/apache-maven-3.9.16/bin/mvn" ]]; then
  export PATH="${HOME}/opt/apache-maven-3.9.16/bin:${PATH}"
fi
if [[ ! -d /usr/lib/jvm/java-17-openjdk ]]; then
  echo "[jcasbin-rat] ERROR: Java 17 home not found at /usr/lib/jvm/java-17-openjdk"
  exit 1
fi
export JAVA_HOME=/usr/lib/jvm/java-17-openjdk
export PATH="${JAVA_HOME}/bin:${PATH}"

mvn_line=$(mvn -version | head -1)
echo "[jcasbin-rat] $mvn_line"
echo "[jcasbin-rat] JAVA_HOME=$JAVA_HOME"
case "$mvn_line" in
  "Apache Maven 3.9"*) ;;
  *)
    echo "[jcasbin-rat] ERROR: Maven 3.9 is required to launch RAT 0.18. Image Maven is 3.6.3."
    echo "[jcasbin-rat] Install 3.9.16 under \$HOME/opt/apache-maven-3.9.16 or put it first on PATH."
    exit 1
    ;;
esac

mapfile -t TREES < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
SELECTED=()
for tree in "${TREES[@]}"; do
  if [[ -f "$tree/pom.xml" ]]; then
    SELECTED+=("$tree")
  fi
done
if [[ ${#SELECTED[@]} -eq 0 ]]; then
  echo "[jcasbin-rat] ERROR: no extracted tree with pom.xml under $COMPONENT_DIR"
  exit 1
fi

is_compiled() {
  local path=$1 base desc
  base=$(basename "$path")
  case "$base" in
    *.png|*.jpg|*.jpeg|*.gif|*.svg|*.ico|*.webp)
      echo "[jcasbin-rat] image, not a compiled binary: $base"
      return 1
      ;;
    *.class|*.jar|*.so|*.o|*.a|*.exe|*.dll|*.pyc|*.whl|*.node)
      echo "[jcasbin-rat] FAIL: compiled binary $base"
      return 0
      ;;
  esac
  if [[ ! -e "$path" ]] || ! command -v file >/dev/null 2>&1; then
    echo "[jcasbin-rat] WARN: could not classify $base"
    return 1
  fi
  desc=$(file -b -- "$path" | tr '[:upper:]' '[:lower:]')
  case "$desc" in
    *elf*|*mach-o*|*pe32*|*java?class*|*byte-compiled*|*shared?object*)
      echo "[jcasbin-rat] FAIL: compiled binary $base ($desc)"
      return 0
      ;;
  esac
  echo "[jcasbin-rat] not compiled: $base ($desc)"
  return 1
}

fail=0
for tree in "${SELECTED[@]}"; do
  echo "[jcasbin-rat] Scanning $(basename "$tree")"
  echo "[jcasbin-rat] The project pom does not declare apache-rat-plugin. Invoking 0.18 by coordinates."
  rm -f "$tree/target/rat.txt"
  set +e
  (
    cd "$tree"
    mvn -B -ntp org.apache.rat:apache-rat-plugin:0.18:check
  )
  rc=$?
  set -e
  report="$tree/target/rat.txt"
  if [[ ! -f "$report" ]]; then
    echo "[jcasbin-rat] ERROR: no rat.txt (mvn exit $rc)"
    exit 1
  fi
  echo "[jcasbin-rat] Report summary:"
  grep -E '^[[:space:]]*(Notes|Binaries|Archives|Standards|Unapproved|Generated|Unknown):' "$report" | sed 's/^/[jcasbin-rat]   /' || true
  echo "[jcasbin-rat] Unapproved lines:"
  grep -E '^[[:space:]]*!' "$report" | sed 's/^/[jcasbin-rat]   /' || true
  if [[ "$rc" -ne 0 ]]; then
    echo "[jcasbin-rat] FAIL: mvn org.apache.rat:apache-rat-plugin:0.18:check exited $rc"
    fail=1
  fi

  prev=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^[[:space:]]*(/[^[:space:]]+)[[:space:]]*$ ]]; then
      prev="${BASH_REMATCH[1]}"
      continue
    fi
    if [[ ! "$line" =~ ^[[:space:]]*B[[:space:]]+([^[:space:]].*)[[:space:]]*$ ]]; then
      continue
    fi
    rest="${BASH_REMATCH[1]}"
    rest="${rest%"${rest##*[![:space:]]}"}"
    rel=""
    if [[ "$rest" == "Binary file" || "$rest" =~ ^[A-Za-z0-9.+-]+/[A-Za-z0-9.+-]+$ ]]; then
      rel="$prev"
    else
      rel="$rest"
    fi
    if [[ -z "$rel" ]]; then
      echo "[jcasbin-rat] skip legend: $rest"
      continue
    fi
    path="$tree/${rel#/}"
    echo "[jcasbin-rat] B ${rel#/} ($rest)"
    if is_compiled "$path"; then
      fail=1
    fi
  done < "$report"
done

if [[ "$fail" -ne 0 ]]; then
  echo "[jcasbin-rat] RESULT: FAIL"
  exit 1
fi
echo "[jcasbin-rat] RESULT: PASS"
exit 0
