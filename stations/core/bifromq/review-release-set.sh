#!/usr/bin/env bash
# The vote stages one source tar.gz and one binary tar.gz. Record that set.
# Do not treat the binary tar as unexpected: the vote linked the directory
# that contains it. apache-validate-release-structure would fail that tar.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "bifromq" ]]; then
  echo "[bifromq-review-release-set] ERROR: this step is bifromq-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_PATH="$PARTS_DIR/${NAME}-artifacts"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"
expect_src="apache-bifromq-${RELEASE_VERSION}-incubating-src.tar.gz"
expect_bin="apache-bifromq-${RELEASE_VERSION}-incubating.tar.gz"

mapfile -t src < <(sed '/^$/d' "$ARTIFACT_PATH/.discovered-src-artifacts")
mapfile -t bin < <(sed '/^$/d' "$ARTIFACT_PATH/.discovered-bin-artifacts")

echo "[bifromq-review-release-set] Source artifacts: ${#src[@]}"
printf '[bifromq-review-release-set]   %s\n' "${src[@]:-}"
echo "[bifromq-review-release-set] Binary artifacts: ${#bin[@]}"
printf '[bifromq-review-release-set]   %s\n' "${bin[@]:-}"

fail=0
if [[ ${#src[@]} -ne 1 || "${src[0]}" != "$expect_src" ]]; then
  echo "[bifromq-review-release-set] ERROR: expected exactly $expect_src"
  fail=1
fi
if [[ ${#bin[@]} -ne 1 || "${bin[0]}" != "$expect_bin" ]]; then
  echo "[bifromq-review-release-set] ERROR: expected exactly $expect_bin"
  fail=1
fi
for name in "$expect_src" "$expect_bin"; do
  case "$name" in
    *incubating*) echo "[bifromq-review-release-set] incubating in filename: $name" ;;
    *)
      echo "[bifromq-review-release-set] ERROR: filename lacks incubating: $name"
      fail=1
      ;;
  esac
done

if [[ "$fail" -ne 0 ]]; then
  echo "[bifromq-review-release-set] RESULT: FAIL"
  exit 1
fi
echo "[bifromq-review-release-set] The binary tar is in this vote. It is not an unexpected extra."
echo "[bifromq-review-release-set] RESULT: PASS"
exit 0
