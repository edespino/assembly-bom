#!/usr/bin/env bash
# Record the items the RC14 call says were fixed after the RC10 -1.
# A missing string is a gap to judge. It is not, by itself, Category X.
# This step does not mark LICENSE accurate.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "amoro" ]]; then
  echo "[amoro-named] ERROR: this step is amoro-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
mapfile -t trees < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[amoro-named] ERROR: expected one extracted tree, found ${#trees[@]}"
  exit 1
fi
tree="${trees[0]}"
echo "[amoro-named] Tree: $tree"

apple=$(find "$tree" -name '._*' | wc -l | tr -d ' ')
echo "[amoro-named] APPLEDOUBLE_COUNT: $apple"

search_file() {
  local file=$1
  local token=$2
  if [[ ! -f "$tree/$file" ]]; then
    echo "[amoro-named] MISSING_FILE: $file"
    return
  fi
  if grep -F -q -- "$token" "$tree/$file"; then
    echo "[amoro-named] HIT $file: $token"
  else
    echo "[amoro-named] GAP $file: $token"
  fi
}

for legal in LICENSE NOTICE DISCLAIMER LICENSE-binary NOTICE-binary; do
  if [[ -f "$tree/$legal" ]]; then
    echo "[amoro-named] present: $legal"
  else
    echo "[amoro-named] MISSING_FILE: $legal"
  fi
done

search_file LICENSE "ICU"
search_file LICENSE "SparkInternalRowWrapper"
search_file LICENSE "ThreadLocalCache"
search_file LICENSE "dnsjava"
search_file LICENSE "Kyuubi"
search_file LICENSE "xmlenc"
search_file LICENSE "SCRAM"
search_file LICENSE "Stringprep"
search_file LICENSE-binary "activation"
search_file LICENSE-binary "jaxb"
search_file LICENSE-binary "javassist"
search_file LICENSE-binary "servlet"

wrapper_count=$(find "$tree" -name 'SparkInternalRowWrapper.java' | wc -l | tr -d ' ')
cache_count=$(find "$tree" -name 'ThreadLocalCache.java' | wc -l | tr -d ' ')
echo "[amoro-named] FILE_COUNT SparkInternalRowWrapper.java: $wrapper_count"
echo "[amoro-named] FILE_COUNT ThreadLocalCache.java: $cache_count"

if [[ "$apple" != "0" ]]; then
  echo "[amoro-named] RESULT: FAIL"
  exit 1
fi
echo "[amoro-named] RESULT: RECORDED"
echo "[amoro-named] A GAP line is not a license pass."
exit 0
