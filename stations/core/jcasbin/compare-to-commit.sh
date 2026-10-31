#!/usr/bin/env bash
# Diff a fresh extract of the source tarball against RELEASE_COMMIT.
# The commit and repository are component env. They are not hardcoded.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "jcasbin" ]]; then
  echo "[jcasbin-commit] ERROR: this step is jcasbin-only (NAME=${NAME})" >&2
  exit 1
fi

RELEASE_COMMIT="${RELEASE_COMMIT:?Missing RELEASE_COMMIT}"
SOURCE_REPO="${SOURCE_REPO:?Missing SOURCE_REPO}"
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_DIR="$PARTS_DIR/${ARTIFACTS_DIR:-${NAME}-artifacts}"

mapfile -t TARBALLS < <(find "$ARTIFACT_DIR" -maxdepth 1 -type f -name '*-src.tar.gz' | sort)
if [[ ${#TARBALLS[@]} -ne 1 ]]; then
  echo "[jcasbin-commit] ERROR: expected one source tar.gz, found ${#TARBALLS[@]}"
  exit 1
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/extract" "$work/tag"
tar -xzf "${TARBALLS[0]}" -C "$work/extract"
git -C "$work/tag" init
git -C "$work/tag" remote add origin "$SOURCE_REPO"
git -C "$work/tag" fetch --depth 1 origin "$RELEASE_COMMIT"
git -C "$work/tag" checkout --detach FETCH_HEAD
echo "[jcasbin-commit] HEAD=$(git -C "$work/tag" rev-parse HEAD)"
if [[ "$(git -C "$work/tag" rev-parse HEAD)" != "$RELEASE_COMMIT" ]]; then
  echo "[jcasbin-commit] ERROR: fetched HEAD is not RELEASE_COMMIT"
  exit 1
fi

python3 - "$work" << 'PY'
import hashlib, os, sys
root = sys.argv[1]
extract_root = os.path.join(root, "extract")
subs = [name for name in os.listdir(extract_root) if os.path.isdir(os.path.join(extract_root, name))]
if len(subs) != 1:
    print("[jcasbin-commit] ERROR: expected one extracted directory, found %s" % len(subs))
    sys.exit(1)

def files(base):
    out = {}
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [name for name in dirnames if name != ".git"]
        for name in filenames:
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, base)
            digest = hashlib.sha256()
            with open(path, "rb") as fh:
                for chunk in iter(lambda: fh.read(1 << 20), b""):
                    digest.update(chunk)
            out[rel] = digest.hexdigest()
    return out

extracted = files(os.path.join(extract_root, subs[0]))
tagged = files(os.path.join(root, "tag"))
only_tag = sorted(set(tagged) - set(extracted))
only_extract = sorted(set(extracted) - set(tagged))
differ = sorted(key for key in set(tagged) & set(extracted) if tagged[key] != extracted[key])
print("[jcasbin-commit] TAG_FILES", len(tagged), "EXTRACT_FILES", len(extracted))
print("[jcasbin-commit] ONLY_TAG", len(only_tag), "ONLY_EXTRACT", len(only_extract), "CONTENT_DIFFER", len(differ))
for name in (only_tag + only_extract + differ)[:30]:
    print("[jcasbin-commit] DIFF", name)
if only_tag or only_extract or differ:
    sys.exit(1)
print("[jcasbin-commit] RESULT: PASS")
PY
echo "[jcasbin-commit] RESULT: PASS"
