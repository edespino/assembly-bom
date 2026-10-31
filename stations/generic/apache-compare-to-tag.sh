#!/usr/bin/env bash
# Compare the extracted source archive to the git tag the vote names.
# Run after extract and before prepare, RAT, or build.
# Identity is validated again before the clone. A missing repo or tag
# stops this step before the comparison starts.
# Exit 1 aborts the review: assemble.sh does not run later steps.
#
# Abort only when the signed archive is not the tag:
#   AppleDouble (._*) or .DS_Store in the archive
#   archive-only files outside the allowlist
#   content that differs for a reason other than line endings
# Do not abort on tag-only files. .gitignore in the tag and not in the
# archive is normal. Do not abort on a CRLF-only difference.
# Clone into review-output, not into the extracted tree.
# A public repo needs no credentials. Do not guess the remote from NAME.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=apache-source-identity.sh
source "$HERE/apache-source-identity.sh"
apache_require_source_identity

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
out="${PARTS_DIR}/review-output/${NAME}"
clone="$out/git-tag"

mapfile -t trees < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)
if [[ ${#trees[@]} -ne 1 ]]; then
  echo "[compare-to-tag] ERROR: expected one extracted tree, found ${#trees[@]}"
  printf '%s\n' "${trees[@]:-}"
  exit 1
fi
tree="${trees[0]}"

echo "[compare-to-tag] Archive tree: $tree"
echo "[compare-to-tag] Tag: $SOURCE_TAG"
echo "[compare-to-tag] Repo: $SOURCE_REPO"

mapfile -t apple_files < <(find "$tree" -name '._*' | sort)
mapfile -t ds_files < <(find "$tree" -name '.DS_Store' | sort)
apple=${#apple_files[@]}
ds_store=${#ds_files[@]}
echo "[compare-to-tag] APPLEDOUBLE_COUNT: $apple"
echo "[compare-to-tag] DS_STORE_COUNT: $ds_store"
if [[ "$apple" != "0" ]]; then
  echo "[compare-to-tag] Sample AppleDouble paths:"
  printf '%s\n' "${apple_files[@]:0:5}"
fi
if [[ "$ds_store" != "0" ]]; then
  echo "[compare-to-tag] Sample .DS_Store paths:"
  printf '%s\n' "${ds_files[@]:0:5}"
fi

mkdir -p "$out"
rm -rf "$clone"
if [[ "$SOURCE_TAG" =~ ^[0-9a-fA-F]{40}$ ]]; then
  mkdir -p "$clone"
  git -C "$clone" init -q
  git -C "$clone" remote add origin "$SOURCE_REPO"
  git -C "$clone" fetch --depth 1 origin "$SOURCE_TAG"
  git -C "$clone" checkout --detach FETCH_HEAD
else
  git clone --depth 1 --branch "$SOURCE_TAG" "$SOURCE_REPO" "$clone"
fi
echo "[compare-to-tag] CLONE_HEAD: $(git -C "$clone" rev-parse HEAD)"

list_files() {
  local root=$1
  local exclude_git=$2
  (
    cd "$root" || exit 1
    if [[ "$exclude_git" == yes ]]; then
      find . -type f ! -path './.git/*' ! -name '.git'
    else
      find . -type f
    fi | sed 's|^\./||' | sort
  )
}

list_links() {
  local root=$1
  local exclude_git=$2
  (
    cd "$root" || exit 1
    find . -type l -print | sed 's|^\./||' | while IFS= read -r rel; do
      if [[ "$exclude_git" == yes && ( "$rel" == ".git" || "$rel" == .git/* ) ]]; then
        continue
      fi
      printf '%s\t%s\n' "$rel" "$(readlink "$rel")"
    done | sort
  )
}

archive_only_allowed() {
  local base
  base=$(basename "$1")
  case "$base" in
    DISCLAIMER|DEPENDENCIES) return 0 ;;
    *) return 1 ;;
  esac
}

tag_only_class() {
  local rel=$1
  local base
  base=$(basename "$rel")
  case "$base" in
    .gitignore|.gitmodules|.gitattributes) echo VCS; return ;;
  esac
  case "$rel" in
    .github/*|.git/*) echo VCS; return ;;
  esac
  if git -C "$clone" check-attr export-ignore -- "$rel" | grep -q 'export-ignore: set'; then
    echo EXPORT_IGNORE
    return
  fi
  echo OTHER
}

crlf_only() {
  python3 - "$1" "$2" << 'PY'
import sys
def norm(path):
    data = open(path, "rb").read()
    if b"\0" in data:
        sys.exit(2)
    return data.replace(b"\r\n", b"\n")
sys.exit(0 if norm(sys.argv[1]) == norm(sys.argv[2]) else 1)
PY
}

archive_list=$(mktemp)
tag_list=$(mktemp)
trap 'rm -f "$archive_list" "$tag_list"' EXIT
list_files "$tree" no > "$archive_list"
list_files "$clone" yes > "$tag_list"

mapfile -t only_archive_files < <(comm -23 "$archive_list" "$tag_list")
mapfile -t only_tag_files < <(comm -13 "$archive_list" "$tag_list")

unexpected=0
allowed=0
if [[ ${#only_archive_files[@]} -gt 0 ]]; then
  for rel in "${only_archive_files[@]}"; do
    if archive_only_allowed "$rel"; then
      allowed=$((allowed + 1))
      echo "[compare-to-tag] ARCHIVE_ALLOWLIST: $rel"
    else
      unexpected=$((unexpected + 1))
      if [[ "$unexpected" -le 20 ]]; then
        echo "[compare-to-tag] ARCHIVE_UNEXPECTED: $rel"
      fi
    fi
  done
fi
echo "[compare-to-tag] ONLY_ARCHIVE: ${#only_archive_files[@]}"
echo "[compare-to-tag] ONLY_ARCHIVE_ALLOWLIST: $allowed"
echo "[compare-to-tag] ONLY_ARCHIVE_UNEXPECTED: $unexpected"

archive_links=$(mktemp)
tag_links=$(mktemp)
trap 'rm -f "$archive_list" "$tag_list" "$archive_links" "$tag_links"' EXIT
list_links "$tree" no > "$archive_links"
list_links "$clone" yes > "$tag_links"
link_unexpected=0
while IFS= read -r row; do
  [[ -z "$row" ]] && continue
  link_unexpected=$((link_unexpected + 1))
  if [[ "$link_unexpected" -le 20 ]]; then
    echo "[compare-to-tag] LINK_UNEXPECTED: $row"
  fi
done < <(comm -23 "$archive_links" "$tag_links")
while IFS= read -r row; do
  [[ -z "$row" ]] && continue
  echo "[compare-to-tag] LINK_ONLY_TAG: $row"
done < <(comm -13 "$archive_links" "$tag_links")
echo "[compare-to-tag] LINK_UNEXPECTED: $link_unexpected"
unexpected=$((unexpected + link_unexpected))

vcs_only=0
export_only=0
other_only=0
if [[ ${#only_tag_files[@]} -gt 0 ]]; then
  for rel in "${only_tag_files[@]}"; do
    class=$(tag_only_class "$rel")
    case "$class" in
      VCS) vcs_only=$((vcs_only + 1)) ;;
      EXPORT_IGNORE) export_only=$((export_only + 1)) ;;
      *) other_only=$((other_only + 1)) ;;
    esac
    if [[ $((vcs_only + export_only + other_only)) -le 20 ]]; then
      echo "[compare-to-tag] ONLY_TAG_$class: $rel"
    fi
  done
fi
echo "[compare-to-tag] ONLY_TAG: ${#only_tag_files[@]}"
echo "[compare-to-tag] ONLY_TAG_VCS: $vcs_only"
echo "[compare-to-tag] ONLY_TAG_EXPORT_IGNORE: $export_only"
echo "[compare-to-tag] ONLY_TAG_OTHER: $other_only"
echo "[compare-to-tag] ONLY_TAG does not abort. A missing archive file is reported, not a -1."

content_diff=0
crlf_count=0
while IFS= read -r rel; do
  if cmp -s "$tree/$rel" "$clone/$rel"; then
    continue
  fi
  if crlf_only "$tree/$rel" "$clone/$rel"; then
    crlf_count=$((crlf_count + 1))
    if [[ "$crlf_count" -le 20 ]]; then
      echo "[compare-to-tag] CRLF_ONLY: $rel"
    fi
  else
    content_diff=$((content_diff + 1))
    if [[ "$content_diff" -le 20 ]]; then
      echo "[compare-to-tag] CONTENT_DIFF: $rel"
    fi
  fi
done < <(comm -12 "$archive_list" "$tag_list")
echo "[compare-to-tag] CONTENT_DIFF_COUNT: $content_diff"
echo "[compare-to-tag] CRLF_ONLY_COUNT: $crlf_count"

if [[ "$apple" != "0" || "$ds_store" != "0" || "$unexpected" != "0" || "$content_diff" != "0" ]]; then
  echo "[compare-to-tag] RESULT: FAIL"
  echo "[compare-to-tag] ABORT: signed archive is not the tag. Later steps must not run."
  exit 1
fi
echo "[compare-to-tag] RESULT: PASS"
exit 0
