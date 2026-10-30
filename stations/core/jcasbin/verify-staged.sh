#!/usr/bin/env bash
# Verify the staged Maven files named by the vote, then compare them to the
# jars this build produced. Pins are component env.
# A CRLF-only difference is a warning. A class or source byte difference fails.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "jcasbin" ]]; then
  echo "[jcasbin-staged] ERROR: this step is jcasbin-only (NAME=${NAME})" >&2
  exit 1
fi

STAGING_URL="${STAGING_URL:?Missing STAGING_URL}"
STAGING_ARTIFACTS="${STAGING_ARTIFACTS:?Missing STAGING_ARTIFACTS}"
SIGNING_KEY_SUFFIX="${SIGNING_KEY_SUFFIX:?Missing SIGNING_KEY_SUFFIX}"
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
STAGE="$PARTS_DIR/review-output/$NAME/staged"
mkdir -p "$STAGE"

echo "[jcasbin-staged] Staging: $STAGING_URL"
fail=0
warn=0
for artifact in $STAGING_ARTIFACTS; do
  curl -fsSL -o "$STAGE/$artifact" "${STAGING_URL%/}/$artifact"
  curl -fsSL -o "$STAGE/$artifact.asc" "${STAGING_URL%/}/$artifact.asc"
  if curl -fsSL -o "$STAGE/$artifact.sha512" "${STAGING_URL%/}/$artifact.sha512"; then
    expected=$(awk '{print $1}' "$STAGE/$artifact.sha512")
    actual=$(sha512sum "$STAGE/$artifact" | awk '{print $1}')
    kind=SHA512
  else
    rm -f "$STAGE/$artifact.sha512"
    curl -fsSL -o "$STAGE/$artifact.sha1" "${STAGING_URL%/}/$artifact.sha1"
    expected=$(tr -d '[:space:]' < "$STAGE/$artifact.sha1")
    actual=$(sha1sum "$STAGE/$artifact" | awk '{print $1}')
    kind=SHA1
    echo "[jcasbin-staged] WARN: $artifact has no SHA-512. Checked SHA-1."
    warn=1
  fi
  if [[ "$expected" == "$actual" ]]; then
    echo "[jcasbin-staged] ${kind}_OK $artifact"
  else
    echo "[jcasbin-staged] FAIL: ${kind} mismatch $artifact"
    fail=1
  fi
  gpg_out=$(gpg --verify "$STAGE/$artifact.asc" "$STAGE/$artifact" 2>&1 || true)
  if printf '%s\n' "$gpg_out" | grep -q "Good signature"; then
    echo "[jcasbin-staged] GPG_GOOD $artifact"
  else
    echo "[jcasbin-staged] FAIL: signature not good $artifact"
    fail=1
  fi
  suffix=$(printf '%s\n' "$gpg_out" | python3 -c '
import sys, re
text = sys.stdin.read()
match = re.search(r"using (?:RSA|ECDSA|EDDSA|DSA) key ([0-9A-Fa-f ]+)", text)
print("MISSING" if not match else match.group(1).replace(" ", "")[-8:].upper())
')
  echo "[jcasbin-staged] KEY_SUFFIX $artifact $suffix"
  if [[ "$suffix" != "$SIGNING_KEY_SUFFIX" ]]; then
    echo "[jcasbin-staged] FAIL: key suffix $suffix is not $SIGNING_KEY_SUFFIX"
    fail=1
  fi
done

mapfile -t TREES < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d | sort)
TREE=""
for candidate in "${TREES[@]}"; do
  if [[ -f "$candidate/LICENSE" ]]; then
    TREE="$candidate"
    break
  fi
done
if [[ -z "$TREE" ]]; then
  echo "[jcasbin-staged] ERROR: extracted source tree not found"
  exit 1
fi

python3 - "$TREE" "$STAGE" "$COMPONENT_DIR" << 'PY'
import hashlib, os, sys, zipfile
tree, stage, component = sys.argv[1:4]
fail = False
warn = False
for legal in ("LICENSE", "NOTICE", "DISCLAIMER"):
    src = open(os.path.join(tree, legal), "rb").read()
    src_hash = hashlib.sha256(src).hexdigest()
    for name in sorted(os.listdir(stage)):
        if not name.endswith(".jar"):
            continue
        with zipfile.ZipFile(os.path.join(stage, name)) as zf:
            try:
                data = zf.read("META-INF/" + legal)
            except KeyError:
                print("[jcasbin-staged] FAIL: %s missing META-INF/%s" % (name, legal))
                fail = True
                continue
        mark = "MATCH" if hashlib.sha256(data).hexdigest() == src_hash else "DIFFER"
        print("[jcasbin-staged] LEGAL %s %s %s" % (name, legal, mark))
        if mark != "MATCH":
            fail = True

built_root = None
for dirpath, dirnames, filenames in os.walk(component):
    if os.path.basename(dirpath) == "target" and any(name.endswith(".jar") for name in filenames):
        built_root = dirpath
        break
if built_root is None:
    print("[jcasbin-staged] ERROR: no built jars under target/")
    sys.exit(1)

def load(path):
    out = {}
    with zipfile.ZipFile(path) as zf:
        for info in zf.infolist():
            if not info.is_dir():
                out[info.filename] = zf.read(info.filename)
    return out

for name in sorted(os.listdir(stage)):
    if not name.endswith(".jar"):
        continue
    built = os.path.join(built_root, name)
    if not os.path.isfile(built):
        print("[jcasbin-staged] WARN: no local build of %s" % name)
        warn = True
        continue
    b = load(built)
    s = load(os.path.join(stage, name))
    raw = 0
    payload = 0
    for key in sorted(set(b) & set(s)):
        if b[key] == s[key]:
            continue
        raw += 1
        if b[key].replace(b"\r\n", b"\n") != s[key].replace(b"\r\n", b"\n"):
            payload += 1
            if key.endswith(".class") or key.endswith(".java"):
                print("[jcasbin-staged] FAIL: payload differs %s %s" % (name, key))
                fail = True
            else:
                print("[jcasbin-staged] WARN: generated file differs %s %s" % (name, key))
                warn = True
    print("[jcasbin-staged] JAR %s RAW_DIFFER %s PAYLOAD_DIFFER %s" % (name, raw, payload))
if fail:
    sys.exit(1)
print("[jcasbin-staged] RESULT: PASS" + (" with warnings" if warn else ""))
PY
echo "[jcasbin-staged] done"
