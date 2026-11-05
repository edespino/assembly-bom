#!/usr/bin/env bash
# Re-run gpg --verify. The discover script's PASSED line discards the gpg text
# and does not name the signer. Require Good signature from the key the vote names.
# Print the key id suffix, not the fingerprint line.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "seata" ]]; then
  echo "[seata-verify-signatures] ERROR: this step is seata-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
ARTIFACT_PATH="$PARTS_DIR/${NAME}-artifacts"
SIGNING_KEY_ID="${SIGNING_KEY_ID:?Missing SIGNING_KEY_ID}"
want=$(printf '%s' "$SIGNING_KEY_ID" | tr '[:lower:]' '[:upper:]')

echo "[seata-verify-signatures] Component: $NAME"
echo "[seata-verify-signatures] Vote key id: $want"

if [[ ! -d "$ARTIFACT_PATH" ]]; then
  echo "[seata-verify-signatures] ERROR: artifacts directory missing. Run discover first."
  exit 1
fi

mapfile -t artifacts < <(cat "$ARTIFACT_PATH/.discovered-src-artifacts" "$ARTIFACT_PATH/.discovered-bin-artifacts" | sed '/^$/d')
if [[ ${#artifacts[@]} -eq 0 ]]; then
  echo "[seata-verify-signatures] ERROR: no discovered artifacts"
  exit 1
fi

fail=0
for artifact in "${artifacts[@]}"; do
  sig="$ARTIFACT_PATH/${artifact}.asc"
  file="$ARTIFACT_PATH/$artifact"
  echo "[seata-verify-signatures] Verifying $artifact"
  if [[ ! -f "$file" || ! -f "$sig" ]]; then
    echo "[seata-verify-signatures] ERROR: missing artifact or signature for $artifact"
    fail=1
    continue
  fi
  out=$(gpg --verify "$sig" "$file" 2>&1 || true)
  if ! printf '%s\n' "$out" | grep -q "Good signature"; then
    echo "[seata-verify-signatures] ERROR: no Good signature for $artifact"
    fail=1
    continue
  fi
  echo "[seata-verify-signatures] Good signature: $artifact"
  key_line=$(printf '%s\n' "$out" | grep -E 'using (RSA|DSA|ECDSA|EDDSA|EdDSA) key' | head -1 || true)
  key_id=$(printf '%s\n' "$key_line" | awk '{print $NF}' | tr '[:lower:]' '[:upper:]')
  if [[ -z "$key_id" ]]; then
    echo "[seata-verify-signatures] ERROR: could not read the signing key id for $artifact"
    fail=1
    continue
  fi
  case "$key_id" in
    *"$want") echo "[seata-verify-signatures] Signer key id matches the vote: $want" ;;
    *)
      echo "[seata-verify-signatures] ERROR: signer key id does not match the vote"
      echo "[seata-verify-signatures] ERROR: got $key_id want $want"
      fail=1
      ;;
  esac
  fp_line=$(printf '%s\n' "$out" | grep -F 'Primary key fingerprint:' | head -1 || true)
  if [[ -n "$fp_line" ]]; then
    groups=${fp_line#*:}
    joined=$(printf '%s' "$groups" | tr -d '[:space:]' | tr '[:lower:]' '[:upper:]')
    suffix=${joined: -8}
    echo "[seata-verify-signatures] Key id suffix: $suffix"
  else
    echo "[seata-verify-signatures] ERROR: no fingerprint line to derive the suffix"
    fail=1
  fi
  if printf '%s\n' "$out" | grep -q "not certified with a trusted signature"; then
    echo "[seata-verify-signatures] Untrusted-key warning is not a bad signature."
  fi
done

if [[ "$fail" -ne 0 ]]; then
  echo "[seata-verify-signatures] RESULT: FAIL"
  exit 1
fi
echo "[seata-verify-signatures] RESULT: PASS"
exit 0
