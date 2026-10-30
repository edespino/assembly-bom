#!/usr/bin/env bash
# Compare the extracted source archive to the git tag the vote names.
# Clone into review-output, not into the extracted tree.
# A public repo needs no credentials.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "ozhera" ]]; then
  echo "[ozhera-compare] ERROR: this step is ozhera-only (NAME=${NAME})" >&2
  exit 1
fi

SOURCE_REPO="${SOURCE_REPO:?Missing SOURCE_REPO}"
SOURCE_TAG="${SOURCE_TAG:?Missing SOURCE_TAG}"
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
out="${PARTS_DIR}/review-output/${NAME}"
clone="$out/git-tag"

mapfile -t trees < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[ozhera-compare] ERROR: expected one extracted tree, found ${#trees[@]}"
  printf '%s\n' "${trees[@]:-}"
  exit 1
fi
tree="${trees[0]}"

echo "[ozhera-compare] Archive tree: $tree"
echo "[ozhera-compare] Tag: $SOURCE_TAG"
echo "[ozhera-compare] Repo: $SOURCE_REPO"

apple=$(find "$tree" -name '._*' | wc -l | tr -d ' ')
echo "[ozhera-compare] APPLEDOUBLE_COUNT: $apple"
if [[ "$apple" != "0" ]]; then
  echo "[ozhera-compare] Sample AppleDouble paths:"
  find "$tree" -name '._*' | head -5
fi

mkdir -p "$out"
rm -rf "$clone"
git clone --depth 1 --branch "$SOURCE_TAG" "$SOURCE_REPO" "$clone"
echo "[ozhera-compare] CLONE_HEAD: $(git -C "$clone" rev-parse HEAD)"

list_files() {
  local root=$1
  (cd "$root" && find . -type f ! -path './.git/*' ! -name '.git' | sed 's|^\./||' | sort)
}

archive_list=$(mktemp)
tag_list=$(mktemp)
trap 'rm -f "$archive_list" "$tag_list"' EXIT
list_files "$tree" > "$archive_list"
list_files "$clone" > "$tag_list"

only_archive=$(comm -23 "$archive_list" "$tag_list" | wc -l | tr -d ' ')
only_tag=$(comm -13 "$archive_list" "$tag_list" | wc -l | tr -d ' ')
echo "[ozhera-compare] ONLY_ARCHIVE: $only_archive"
echo "[ozhera-compare] ONLY_TAG: $only_tag"
if [[ "$only_archive" != "0" ]]; then
  echo "[ozhera-compare] Files only in the archive (first 20):"
  comm -23 "$archive_list" "$tag_list" | head -20
fi
if [[ "$only_tag" != "0" ]]; then
  echo "[ozhera-compare] Files only in the tag (first 20):"
  comm -13 "$archive_list" "$tag_list" | head -20
fi

content_diff=0
while IFS= read -r rel; do
  if ! cmp -s "$tree/$rel" "$clone/$rel"; then
    content_diff=$((content_diff + 1))
    if [[ "$content_diff" -le 20 ]]; then
      echo "[ozhera-compare] CONTENT_DIFF: $rel"
    fi
  fi
done < <(comm -12 "$archive_list" "$tag_list")
echo "[ozhera-compare] CONTENT_DIFF_COUNT: $content_diff"

if [[ "$apple" != "0" || "$only_archive" != "0" || "$only_tag" != "0" || "$content_diff" != "0" ]]; then
  echo "[ozhera-compare] RESULT: FAIL"
  exit 1
fi
echo "[ozhera-compare] RESULT: PASS"
exit 0
