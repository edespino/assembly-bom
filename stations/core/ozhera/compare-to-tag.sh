#!/usr/bin/env bash
# Compare the extracted source archive to the git tag the vote names.
# Run after extract and before prepare, RAT, or build.
# Exit 1 aborts the review: assemble.sh does not run later steps.
#
# Abort only when the signed archive is not the tag:
#   AppleDouble (._*) or .DS_Store in the archive
#   archive-only files outside the allowlist
#   content that differs for a reason other than line endings
# Do not abort on tag-only files. .gitignore in the tag and not in the
# archive is normal. Do not abort on a CRLF-only difference.
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

if ! command -v git >/dev/null 2>&1; then
  echo "[ozhera-compare] Installing git. This step runs before prepare."
  sudo dnf install -y git
  echo "[ozhera-compare] Installed after launch: git"
fi
echo "[ozhera-compare] git: $(command -v git) $(git --version)"

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

mapfile -t apple_files < <(find "$tree" -name '._*' | sort)
mapfile -t ds_files < <(find "$tree" -name '.DS_Store' | sort)
apple=${#apple_files[@]}
ds_store=${#ds_files[@]}
echo "[ozhera-compare] APPLEDOUBLE_COUNT: $apple"
echo "[ozhera-compare] DS_STORE_COUNT: $ds_store"
if [[ "$apple" != "0" ]]; then
  echo "[ozhera-compare] Sample AppleDouble paths:"
  printf '%s\n' "${apple_files[@]:0:5}"
fi
if [[ "$ds_store" != "0" ]]; then
  echo "[ozhera-compare] Sample .DS_Store paths:"
  printf '%s\n' "${ds_files[@]:0:5}"
fi

mkdir -p "$out"
rm -rf "$clone"
git clone --depth 1 --branch "$SOURCE_TAG" "$SOURCE_REPO" "$clone"
echo "[ozhera-compare] CLONE_HEAD: $(git -C "$clone" rev-parse HEAD)"

list_files() {
  local root=$1
  (cd "$root" && find . -type f ! -path './.git/*' ! -name '.git' | sed 's|^\./||' | sort)
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

has_nul() {
  local orig stripped
  orig=$(wc -c < "$1" | tr -d ' ')
  stripped=$(tr -d '\000' < "$1" | wc -c | tr -d ' ')
  [[ "$orig" != "$stripped" ]]
}

crlf_only() {
  local a=$1 b=$2
  if has_nul "$a" || has_nul "$b"; then
    return 1
  fi
  cmp -s <(tr -d '\r' < "$a") <(tr -d '\r' < "$b")
}

archive_list=$(mktemp)
tag_list=$(mktemp)
trap 'rm -f "$archive_list" "$tag_list"' EXIT
list_files "$tree" > "$archive_list"
list_files "$clone" > "$tag_list"

mapfile -t only_archive_files < <(comm -23 "$archive_list" "$tag_list")
mapfile -t only_tag_files < <(comm -13 "$archive_list" "$tag_list")

unexpected=0
allowed=0
if [[ ${#only_archive_files[@]} -gt 0 ]]; then
  for rel in "${only_archive_files[@]}"; do
    if archive_only_allowed "$rel"; then
      allowed=$((allowed + 1))
      echo "[ozhera-compare] ARCHIVE_ALLOWLIST: $rel"
    else
      unexpected=$((unexpected + 1))
      if [[ "$unexpected" -le 20 ]]; then
        echo "[ozhera-compare] ARCHIVE_UNEXPECTED: $rel"
      fi
    fi
  done
fi
echo "[ozhera-compare] ONLY_ARCHIVE: ${#only_archive_files[@]}"
echo "[ozhera-compare] ONLY_ARCHIVE_ALLOWLIST: $allowed"
echo "[ozhera-compare] ONLY_ARCHIVE_UNEXPECTED: $unexpected"

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
      echo "[ozhera-compare] ONLY_TAG_$class: $rel"
    fi
  done
fi
echo "[ozhera-compare] ONLY_TAG: ${#only_tag_files[@]}"
echo "[ozhera-compare] ONLY_TAG_VCS: $vcs_only"
echo "[ozhera-compare] ONLY_TAG_EXPORT_IGNORE: $export_only"
echo "[ozhera-compare] ONLY_TAG_OTHER: $other_only"
echo "[ozhera-compare] ONLY_TAG does not abort. A missing archive file is reported, not a -1."

content_diff=0
crlf_count=0
while IFS= read -r rel; do
  if cmp -s "$tree/$rel" "$clone/$rel"; then
    continue
  fi
  if crlf_only "$tree/$rel" "$clone/$rel"; then
    crlf_count=$((crlf_count + 1))
    if [[ "$crlf_count" -le 20 ]]; then
      echo "[ozhera-compare] CRLF_ONLY: $rel"
    fi
  else
    content_diff=$((content_diff + 1))
    if [[ "$content_diff" -le 20 ]]; then
      echo "[ozhera-compare] CONTENT_DIFF: $rel"
    fi
  fi
done < <(comm -12 "$archive_list" "$tag_list")
echo "[ozhera-compare] CONTENT_DIFF_COUNT: $content_diff"
echo "[ozhera-compare] CRLF_ONLY_COUNT: $crlf_count"

if [[ "$apple" != "0" || "$ds_store" != "0" || "$unexpected" != "0" || "$content_diff" != "0" ]]; then
  echo "[ozhera-compare] RESULT: FAIL"
  echo "[ozhera-compare] ABORT: signed archive is not the tag. Later steps must not run."
  exit 1
fi
echo "[ozhera-compare] RESULT: PASS"
exit 0
