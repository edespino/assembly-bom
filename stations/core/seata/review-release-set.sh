#!/usr/bin/env bash
# The vote stages one source zip and one binary tar. Record that set.
# Do not treat the binary tar as unexpected: the vote linked the directory
# that contains it. apache-validate-release-structure would fail that tar.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "seata" ]]; then
  echo "[seata-review-release-set] ERROR: this step is seata-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_PATH="$PARTS_DIR/${NAME}-artifacts"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"
expect_src="apache-seata-${RELEASE_VERSION}-incubating-src.zip"
expect_bin="apache-seata-${RELEASE_VERSION}-incubating-bin.tar.gz"

mapfile -t src < <(sed '/^$/d' "$ARTIFACT_PATH/.discovered-src-artifacts")
mapfile -t bin < <(sed '/^$/d' "$ARTIFACT_PATH/.discovered-bin-artifacts")

echo "[seata-review-release-set] Source artifacts: ${#src[@]}"
printf '[seata-review-release-set]   %s\n' "${src[@]:-}"
echo "[seata-review-release-set] Binary artifacts: ${#bin[@]}"
printf '[seata-review-release-set]   %s\n' "${bin[@]:-}"

fail=0
if [[ ${#src[@]} -ne 1 || "${src[0]}" != "$expect_src" ]]; then
  echo "[seata-review-release-set] ERROR: expected exactly $expect_src"
  fail=1
fi
if [[ ${#bin[@]} -ne 1 || "${bin[0]}" != "$expect_bin" ]]; then
  echo "[seata-review-release-set] ERROR: expected exactly $expect_bin"
  fail=1
fi
for name in "$expect_src" "$expect_bin"; do
  case "$name" in
    *incubating*) echo "[seata-review-release-set] incubating in filename: $name" ;;
    *)
      echo "[seata-review-release-set] ERROR: filename lacks incubating: $name"
      fail=1
      ;;
  esac
done

if [[ "$fail" -ne 0 ]]; then
  echo "[seata-review-release-set] RESULT: FAIL"
  exit 1
fi
echo "[seata-review-release-set] The binary tar is in this vote. It is not an unexpected extra."
echo "[seata-review-release-set] RESULT: PASS"
exit 0
