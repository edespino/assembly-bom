#!/usr/bin/env bash
# The vote links a Maven staging repository. Verify the checksum files that
# repository publishes. A missing SHA-512 it does not publish is not a
# checksum failure. Read Build-Jdk-Spec and any recorded origin from main
# jars. A fork URL is recorded. It does not fail this step.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "xtable" ]]; then
  echo "[xtable-staging] ERROR: this step is xtable-only (NAME=${NAME})" >&2
  exit 1
fi

STAGING_URL="${STAGING_URL:?Missing STAGING_URL}"
SIGNING_KEY_ID="${SIGNING_KEY_ID:?Missing SIGNING_KEY_ID}"
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
out="$PARTS_DIR/review-output/$NAME/staging"
rm -rf "$out"
mkdir -p "$out"

keys="$PARTS_DIR/${NAME}-artifacts/KEYS"
if [[ -f "$keys" ]]; then
  gpg --import "$keys" >/dev/null 2>&1 || true
fi

echo "[xtable-staging] Repository: $STAGING_URL"
python3 - "$STAGING_URL" "$out" "$SIGNING_KEY_ID" << 'PY'
import hashlib, os, subprocess, sys, tempfile, zipfile
from html.parser import HTMLParser
from urllib.parse import urljoin
from urllib.request import Request, urlopen

base = sys.argv[1].rstrip("/") + "/"
out = sys.argv[2]
want = sys.argv[3].upper()
nlen = len(want)

class Links(HTMLParser):
    def __init__(self):
        super().__init__()
        self.hrefs = []
    def handle_starttag(self, tag, attrs):
        if tag != "a":
            return
        for key, value in attrs:
            if key == "href" and value:
                self.hrefs.append(value)

def fetch(url):
    req = Request(url, headers={"User-Agent": "synx-dev-review/1.0"})
    with urlopen(req, timeout=180) as resp:
        return resp.read()

def download(url, path):
    req = Request(url, headers={"User-Agent": "synx-dev-review/1.0"})
    with urlopen(req, timeout=180) as resp, open(path, "wb") as fh:
        while True:
            chunk = resp.read(1024 * 1024)
            if not chunk:
                break
            fh.write(chunk)

def list_dir(url):
    parser = Links()
    parser.feed(fetch(url).decode("utf-8", "replace"))
    kids = []
    for href in parser.hrefs:
        if href.startswith("?") or href.startswith("/") or href in ("../",):
            continue
        kids.append(urljoin(url, href))
    return kids

files = []
dirs = [base]
seen = set()
while dirs:
    current = dirs.pop()
    if current in seen:
        continue
    seen.add(current)
    for link in list_dir(current):
        if link.endswith("/"):
            dirs.append(link)
        else:
            files.append(link)

names = [u.rsplit("/", 1)[-1] for u in files]
print(f"[xtable-staging] FILE_COUNT: {len(files)}")
have_sha1 = sum(1 for n in names if n.endswith(".sha1"))
have_md5 = sum(1 for n in names if n.endswith(".md5"))
have_sha512 = sum(1 for n in names if n.endswith(".sha512"))
print(f"[xtable-staging] CHECKSUM_FILES: sha1={have_sha1} md5={have_md5} sha512={have_sha512}")

artifacts = [u for u in files if u.endswith((".jar", ".pom")) and not u.endswith((".sha1", ".md5", ".sha512", ".asc"))]
print(f"[xtable-staging] ARTIFACTS: {len(artifacts)}")
fail = 0
jdks = {}
origins = []
for url in artifacts:
    name = url.rsplit("/", 1)[-1]
    sidecars = {kind: url + "." + kind for kind in ("sha1", "md5", "sha512", "asc")}
    present = {kind: (sidecars[kind] in files) for kind in sidecars}
    if not present["asc"]:
        print(f"[xtable-staging] ERROR: no .asc for {name}")
        fail += 1
        continue
    fd, path = tempfile.mkstemp(prefix="xtable-stage-")
    os.close(fd)
    try:
        download(url, path)
        for kind, algo in (("sha1", "sha1"), ("md5", "md5"), ("sha512", "sha512")):
            if not present[kind]:
                continue
            published = fetch(sidecars[kind]).decode("utf-8", "replace")
            token = published.replace("\n", " ").strip().split()
            expected = token[0].lower() if token else ""
            h = hashlib.new(algo)
            with open(path, "rb") as fh:
                while True:
                    chunk = fh.read(1024 * 1024)
                    if not chunk:
                        break
                    h.update(chunk)
            actual = h.hexdigest()
            if expected != actual:
                print(f"[xtable-staging] ERROR: {kind} mismatch for {name}")
                fail += 1
        asc_path = path + ".asc"
        with open(asc_path, "wb") as fh:
            fh.write(fetch(sidecars["asc"]))
        proc = subprocess.run(
            ["gpg", "--status-fd", "1", "--verify", asc_path, path],
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
        )
        bad = False
        valids = []
        for line in proc.stdout.splitlines():
            fields = line.split()
            if len(fields) < 2 or fields[0] != "[GNUPG:]":
                continue
            if fields[1] in ("BADSIG", "ERRSIG", "EXPKEYSIG", "REVKEYSIG", "EXPSIG"):
                bad = True
            if fields[1] == "VALIDSIG" and len(fields) >= 12 and len(fields[11]) == 40:
                valids.append(fields[11])
        suffix = valids[0][-nlen:].upper() if len(valids) == 1 else ""
        if bad or len(valids) != 1 or suffix != want:
            print(f"[xtable-staging] ERROR: signature mismatch for {name}")
            fail += 1
        else:
            print(f"[xtable-staging] SIGNED: {name}")
        main_jar = name.endswith(".jar") and not name.endswith(("-sources.jar", "-javadoc.jar", "-tests.jar"))
        if main_jar:
            with zipfile.ZipFile(path) as zf:
                if "META-INF/MANIFEST.MF" in zf.namelist():
                    text = zf.read("META-INF/MANIFEST.MF").decode("utf-8", "replace")
                    for line in text.splitlines():
                        if line.startswith("Build-Jdk-Spec:"):
                            jdks.setdefault(line.split(":", 1)[1].strip(), []).append(name)
                for entry in zf.namelist():
                    if entry.endswith("git.properties") or entry.endswith("build.properties"):
                        body = zf.read(entry).decode("utf-8", "replace")
                        for line in body.splitlines():
                            if "origin" in line.lower() or line.startswith("git.commit.id=") or line.startswith("git.dirty="):
                                origins.append(f"{name} {entry} {line}")
    finally:
        os.remove(path)
        if os.path.exists(path + ".asc"):
            os.remove(path + ".asc")

print(f"[xtable-staging] JDK_SPECS: {len(jdks)}")
for spec, jars in sorted(jdks.items()):
    print(f"[xtable-staging] BUILD_JDK_SPEC: {spec} count={len(jars)} sample={jars[0]}")
print(f"[xtable-staging] ORIGIN_LINES: {len(origins)}")
for line in origins[:20]:
    print(f"[xtable-staging] ORIGIN: {line}")
if fail:
    print("[xtable-staging] RESULT: FAIL")
    sys.exit(1)
print("[xtable-staging] RESULT: PASS")
PY
