#!/usr/bin/env bash
# Compare the source archives the discover step downloaded.
# Pins live in the component env, not in this script. A later candidate
# changes apache-bom.yaml and reruns assemble.sh. Do not copy this logic
# into a scratch script.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "jcasbin" ]]; then
  echo "[jcasbin-archives] ERROR: this step is jcasbin-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_DIR="$PARTS_DIR/${ARTIFACTS_DIR:-${NAME}-artifacts}"

echo "[jcasbin-archives] Artifact dir: $ARTIFACT_DIR"
if [[ ! -d "$ARTIFACT_DIR" ]]; then
  echo "[jcasbin-archives] ERROR: artifact directory not found"
  exit 1
fi

mapfile -t ARCHIVES < <(find "$ARTIFACT_DIR" -maxdepth 1 -type f \( -name '*-src.tar.gz' -o -name '*-src.zip' \) | sort)
if [[ ${#ARCHIVES[@]} -lt 2 ]]; then
  echo "[jcasbin-archives] ERROR: expected at least two source archives, found ${#ARCHIVES[@]}"
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
i=0
for archive in "${ARCHIVES[@]}"; do
  base=$(basename "$archive")
  echo "[jcasbin-archives] Archive: $base"
  case "$base" in
    *incubating*) ;;
    *)
      echo "[jcasbin-archives] ERROR: incubating source archive name missing incubating: $base"
      exit 1
      ;;
  esac
  dest="$work/$i"
  mkdir -p "$dest"
  case "$archive" in
    *.tar.gz) tar -xzf "$archive" -C "$dest" ;;
    *.zip) unzip -q "$archive" -d "$dest" ;;
    *)
      echo "[jcasbin-archives] ERROR: unsupported archive: $base"
      exit 1
      ;;
  esac
  i=$((i + 1))
done

python3 - "$work" << 'PY'
import hashlib, os, sys
root = sys.argv[1]
dirs = sorted(name for name in os.listdir(root) if os.path.isdir(os.path.join(root, name)))

def files(base):
    out = {}
    for dirpath, dirnames, filenames in os.walk(base):
        for name in filenames:
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, base)
            digest = hashlib.sha256()
            with open(path, "rb") as fh:
                for chunk in iter(lambda: fh.read(1 << 20), b""):
                    digest.update(chunk)
            out[rel] = digest.hexdigest()
    return out

trees = [files(os.path.join(root, name)) for name in dirs]
print("[jcasbin-archives] FILE_COUNT", len(trees[0]))
failed = False
for tree in trees[1:]:
    if len(tree) != len(trees[0]):
        print("[jcasbin-archives] FAIL: file count %s != %s" % (len(tree), len(trees[0])))
        failed = True
    only_a = sorted(set(trees[0]) - set(tree))
    only_b = sorted(set(tree) - set(trees[0]))
    differ = sorted(key for key in set(trees[0]) & set(tree) if trees[0][key] != tree[key])
    print("[jcasbin-archives] ONLY_FIRST", len(only_a), "ONLY_OTHER", len(only_b), "CONTENT_DIFFER", len(differ))
    if only_a or only_b or differ:
        failed = True
if failed:
    sys.exit(1)
print("[jcasbin-archives] RESULT: PASS")
PY
echo "[jcasbin-archives] RESULT: PASS"
