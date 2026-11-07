#!/usr/bin/env bash
# The vote stages one source tar and two convenience binary tars.
# The binary tars are in this vote. They are not unexpected extras.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "amoro" ]]; then
  echo "[amoro-review-release-set] ERROR: this step is amoro-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_PATH="$PARTS_DIR/${NAME}-artifacts"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"
expect_src="apache-amoro-${RELEASE_VERSION}-incubating-src.tar.gz"
expect_h2="apache-amoro-${RELEASE_VERSION}-incubating-bin-hadoop2.tar.gz"
expect_h3="apache-amoro-${RELEASE_VERSION}-incubating-bin-hadoop3.tar.gz"

mapfile -t src < <(sed '/^$/d' "$ARTIFACT_PATH/.discovered-src-artifacts")
mapfile -t bin < <(sed '/^$/d' "$ARTIFACT_PATH/.discovered-bin-artifacts")

echo "[amoro-review-release-set] Source artifacts: ${#src[@]}"
printf '[amoro-review-release-set]   %s\n' "${src[@]:-}"
echo "[amoro-review-release-set] Binary artifacts: ${#bin[@]}"
printf '[amoro-review-release-set]   %s\n' "${bin[@]:-}"

fail=0
if [[ ${#src[@]} -ne 1 || "${src[0]}" != "$expect_src" ]]; then
  echo "[amoro-review-release-set] ERROR: expected exactly $expect_src"
  fail=1
fi
found_h2=0
found_h3=0
for name in "${bin[@]:-}"; do
  [[ "$name" == "$expect_h2" ]] && found_h2=1
  [[ "$name" == "$expect_h3" ]] && found_h3=1
done
if [[ ${#bin[@]} -ne 2 || "$found_h2" -ne 1 || "$found_h3" -ne 1 ]]; then
  echo "[amoro-review-release-set] ERROR: expected exactly $expect_h2 and $expect_h3"
  fail=1
fi
for name in "$expect_src" "$expect_h2" "$expect_h3"; do
  case "$name" in
    *incubating*) echo "[amoro-review-release-set] incubating in filename: $name" ;;
    *)
      echo "[amoro-review-release-set] ERROR: filename lacks incubating: $name"
      fail=1
      ;;
  esac
done

if [[ "$fail" -ne 0 ]]; then
  echo "[amoro-review-release-set] RESULT: FAIL"
  exit 1
fi
echo "[amoro-review-release-set] The binary tars are in this vote. They are not unexpected extras."
echo "[amoro-review-release-set] They are not the Maven staging repository."
echo "[amoro-review-release-set] RESULT: PASS"
exit 0
