#!/usr/bin/env bash
# Re-run gpg --verify. Discover's PASSED line discards the gpg text and does
# not name the signer. Require Good signature from the key the vote names.
# Print the key id suffix, not the fingerprint line.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "amoro" ]]; then
  echo "[amoro-verify-signatures] ERROR: this step is amoro-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_PATH="$PARTS_DIR/${NAME}-artifacts"
SIGNING_KEY_ID="${SIGNING_KEY_ID:?Missing SIGNING_KEY_ID}"
want=$(printf '%s' "$SIGNING_KEY_ID" | tr '[:lower:]' '[:upper:]')

echo "[amoro-verify-signatures] Component: $NAME"
echo "[amoro-verify-signatures] Vote key id suffix: $want"

mapfile -t artifacts < <(cat "$ARTIFACT_PATH/.discovered-src-artifacts" "$ARTIFACT_PATH/.discovered-bin-artifacts" | sed '/^$/d')
if [[ ${#artifacts[@]} -eq 0 ]]; then
  echo "[amoro-verify-signatures] ERROR: no discovered artifacts"
  exit 1
fi

fail=0
for artifact in "${artifacts[@]}"; do
  sig="$ARTIFACT_PATH/${artifact}.asc"
  file="$ARTIFACT_PATH/$artifact"
  sha="$ARTIFACT_PATH/${artifact}.sha512"
  echo "[amoro-verify-signatures] Verifying $artifact"
  if [[ ! -f "$file" || ! -f "$sig" || ! -f "$sha" ]]; then
    echo "[amoro-verify-signatures] ERROR: missing artifact, .asc, or .sha512 for $artifact"
    fail=1
    continue
  fi
  expected=$(awk '{print $1}' "$sha")
  actual=$(sha512sum "$file" | awk '{print $1}')
  if [[ "$expected" != "$actual" ]]; then
    echo "[amoro-verify-signatures] ERROR: SHA-512 mismatch for $artifact"
    fail=1
    continue
  fi
  echo "[amoro-verify-signatures] SHA-512 matched: $artifact"
  out=$(gpg --verify "$sig" "$file" 2>&1 || true)
  if ! printf '%s\n' "$out" | grep -q "Good signature"; then
    echo "[amoro-verify-signatures] ERROR: no Good signature for $artifact"
    fail=1
    continue
  fi
  echo "[amoro-verify-signatures] Good signature: $artifact"
  status=$(gpg --status-fd 1 --verify "$sig" "$file" 2>&1 || true)
  if ! printf '%s\n' "$status" | grep -q '\[GNUPG:\] VALIDSIG '; then
    echo "[amoro-verify-signatures] ERROR: no VALIDSIG status for $artifact"
    fail=1
    continue
  fi
  valid_line=$(printf '%s\n' "$status" | grep '\[GNUPG:\] VALIDSIG ' | head -1)
  primary=$(printf '%s\n' "$valid_line" | grep -oE '[0-9A-Fa-f]{40}' | tail -1 | tr '[:lower:]' '[:upper:]')
  suffix=${primary: -8}
  echo "[amoro-verify-signatures] Primary key id suffix: $suffix"
  if [[ -z "$suffix" || "$suffix" != "$want" ]]; then
    echo "[amoro-verify-signatures] ERROR: primary key suffix does not match the vote"
    echo "[amoro-verify-signatures] ERROR: got ${suffix:-missing} want $want"
    fail=1
  fi
  if printf '%s\n' "$status" | grep -q "not certified with a trusted signature"; then
    echo "[amoro-verify-signatures] Untrusted-key warning is not a bad signature."
  fi
done

if [[ "$fail" -ne 0 ]]; then
  echo "[amoro-verify-signatures] RESULT: FAIL"
  exit 1
fi
echo "[amoro-verify-signatures] RESULT: PASS"
exit 0
