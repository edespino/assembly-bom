#!/usr/bin/env bash
# One source tar and one Docker Compose bundle. The bundle is not an
# unexpected extra. Do not run apache-validate-release-structure.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "texera" ]]; then
  echo "[texera-review-release-set] ERROR: this step is texera-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_PATH="$PARTS_DIR/${NAME}-artifacts"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"
expect_src="apache-texera-${RELEASE_VERSION}-incubating-src.tar.gz"
expect_bin="apache-texera-${RELEASE_VERSION}-incubating-docker-compose.tar.gz"

mapfile -t src < <(sed '/^$/d' "$ARTIFACT_PATH/.discovered-src-artifacts")
mapfile -t bin < <(sed '/^$/d' "$ARTIFACT_PATH/.discovered-bin-artifacts")

echo "[texera-review-release-set] Source artifacts: ${#src[@]}"
printf '[texera-review-release-set]   %s\n' "${src[@]:-}"
echo "[texera-review-release-set] Binary artifacts: ${#bin[@]}"
printf '[texera-review-release-set]   %s\n' "${bin[@]:-}"

fail=0
if [[ ${#src[@]} -ne 1 || "${src[0]}" != "$expect_src" ]]; then
  echo "[texera-review-release-set] ERROR: expected exactly $expect_src"
  fail=1
fi
if [[ ${#bin[@]} -ne 1 || "${bin[0]}" != "$expect_bin" ]]; then
  echo "[texera-review-release-set] ERROR: expected exactly $expect_bin"
  fail=1
fi
for name in "$expect_src" "$expect_bin"; do
  case "$name" in
    *incubating*) echo "[texera-review-release-set] incubating in filename: $name" ;;
    *)
      echo "[texera-review-release-set] ERROR: filename lacks incubating: $name"
      fail=1
      ;;
  esac
done

if [[ "$fail" -ne 0 ]]; then
  echo "[texera-review-release-set] RESULT: FAIL"
  exit 1
fi
echo "[texera-review-release-set] The compose bundle is in this vote. It is not an unexpected extra."
echo "[texera-review-release-set] RESULT: PASS"
exit 0
