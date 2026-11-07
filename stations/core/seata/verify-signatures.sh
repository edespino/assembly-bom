#!/usr/bin/env bash
# Re-run gpg --verify. Discover's PASSED line discards the gpg text and does
# not name the signer. Require one VALIDSIG from the key the vote names.
# The vote key id may be 8 or 16 hex. Compare that many characters of the
# fingerprint. Do not read the human-readable fingerprint label.
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
if [[ ! "$want" =~ ^[0-9A-F]{8}$ && ! "$want" =~ ^[0-9A-F]{16}$ ]]; then
  echo "[seata-verify-signatures] ERROR: SIGNING_KEY_ID must be 8 or 16 hex characters"
  exit 1
fi

echo "[seata-verify-signatures] Component: $NAME"
echo "[seata-verify-signatures] Vote key id suffix: $want"

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
  sha="$ARTIFACT_PATH/${artifact}.sha512"
  echo "[seata-verify-signatures] Verifying $artifact"
  if [[ ! -f "$file" || ! -f "$sig" || ! -f "$sha" ]]; then
    echo "[seata-verify-signatures] ERROR: missing artifact, .asc, or .sha512 for $artifact"
    fail=1
    continue
  fi
  expected=$(awk '{print $1}' "$sha")
  actual=$(sha512sum "$file" | awk '{print $1}')
  if [[ "$expected" != "$actual" ]]; then
    echo "[seata-verify-signatures] ERROR: SHA-512 mismatch for $artifact"
    fail=1
    continue
  fi
  echo "[seata-verify-signatures] SHA-512 matched: $artifact"
  # Status only. Human-readable text must not set the signer.
  status=$(gpg --status-fd 1 --verify "$sig" "$file" 2>/dev/null || true)
  set +e
  parsed=$(printf '%s\n' "$status" | awk -v nlen="${#want}" '
    $1=="[GNUPG:]" && ($2=="BADSIG" || $2=="ERRSIG" || $2=="EXPKEYSIG" || $2=="REVKEYSIG" || $2=="EXPSIG") { bad=1 }
    $1=="[GNUPG:]" && $2=="VALIDSIG" { n++; fpr=$12; nf=NF }
    END {
      if (bad) exit 3
      if (n!=1) exit 2
      if (nf < 12) exit 4
      if (fpr !~ /^[0-9A-Fa-f]{40}$/) exit 5
      print substr(fpr, length(fpr)-nlen+1)
    }
  ')
  parse_rc=$?
  set -e
  suffix=$(printf '%s' "$parsed" | tr '[:lower:]' '[:upper:]')
  echo "[seata-verify-signatures] Primary key id suffix: ${suffix:-missing}"
  if [[ "$parse_rc" -ne 0 || "$suffix" != "$want" ]]; then
    echo "[seata-verify-signatures] ERROR: VALIDSIG primary suffix does not match the vote"
    echo "[seata-verify-signatures] ERROR: got ${suffix:-missing} want $want"
    fail=1
  fi
done

if [[ "$fail" -ne 0 ]]; then
  echo "[seata-verify-signatures] RESULT: FAIL"
  exit 1
fi
echo "[seata-verify-signatures] RESULT: PASS"
exit 0
