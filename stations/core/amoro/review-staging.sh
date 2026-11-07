#!/usr/bin/env bash
# The vote links a Maven staging repository. Verify the checksum files
# that repository publishes. A missing SHA-512 it does not publish is
# not a checksum failure. Read Build-Jdk-Spec and any recorded origin
# from one main jar. A fork URL is recorded. It does not fail this step.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "amoro" ]]; then
  echo "[amoro-staging] ERROR: this step is amoro-only (NAME=${NAME})" >&2
  exit 1
fi

STAGING_URL="${STAGING_URL:?Missing STAGING_URL}"
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
out="$PARTS_DIR/review-output/$NAME/staging"
rm -rf "$out"
mkdir -p "$out"

echo "[amoro-staging] Repository: $STAGING_URL"
python3 - "$STAGING_URL" "$out" << 'PY'
import hashlib, os, sys, urllib.request, zipfile
from html.parser import HTMLParser
from urllib.parse import urljoin

base = sys.argv[1].rstrip("/") + "/"
out = sys.argv[2]

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

def fetch_bytes(url):
    req = urllib.request.Request(url, headers={"User-Agent": "synx-dev-review/1.0"})
    with urllib.request.urlopen(req, timeout=180) as resp:
        return resp.read()

def download(url, path):
    req = urllib.request.Request(url, headers={"User-Agent": "synx-dev-review/1.0"})
    with urllib.request.urlopen(req, timeout=180) as resp, open(path, "wb") as fh:
        while True:
            chunk = resp.read(1024 * 1024)
            if not chunk:
                break
            fh.write(chunk)

def list_dir(url):
    parser = Links()
    parser.feed(fetch_bytes(url).decode("utf-8", "replace"))
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

jars = [u for u in files if u.endswith(".jar") and not u.endswith(("-sources.jar", "-javadoc.jar", "-tests.jar"))]
poms = [u for u in files if u.endswith(".pom")]
print(f"[amoro-staging] STAGING_JARS: {len(jars)}")
print(f"[amoro-staging] STAGING_POMS: {len(poms)}")
if not jars:
    print("[amoro-staging] ERROR: no main jars in the staging repository")
    sys.exit(1)

file_set = set(files)
fail = 0
sha512_n = 0
sha1_n = 0
checked = 0

def verify(url, keep=False):
    global fail, sha512_n, sha1_n, checked
    name = url.rsplit("/", 1)[-1]
    path = os.path.join(out, name)
    download(url, path)
    if url + ".sha512" in file_set:
        published = fetch_bytes(url + ".sha512").decode().split()[0].strip()
        digest = hashlib.sha512()
        kind = "SHA-512"
        sha512_n += 1
    elif url + ".sha1" in file_set:
        published = fetch_bytes(url + ".sha1").decode().split()[0].strip()
        digest = hashlib.sha1()
        kind = "SHA-1"
        sha1_n += 1
    else:
        print(f"[amoro-staging] ERROR: no checksum file for {name}")
        fail += 1
        if not keep:
            os.remove(path)
        return path
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            digest.update(chunk)
    actual = digest.hexdigest()
    checked += 1
    if published.lower() != actual.lower():
        print(f"[amoro-staging] ERROR: {kind} mismatch for {name}")
        fail += 1
    if not keep:
        os.remove(path)
    return path

for url in poms:
    verify(url)
sample = jars[0]
for url in jars:
    base_name = url.rsplit("/", 1)[-1]
    if "amoro-ams" in base_name:
        sample = url
        break
for url in jars:
    verify(url, keep=(url == sample))

print(f"[amoro-staging] CHECKSUMS_CHECKED: {checked}")
print(f"[amoro-staging] SHA512_FILES: {sha512_n}")
print(f"[amoro-staging] SHA1_FILES: {sha1_n}")
if sha512_n == 0:
    print("[amoro-staging] The repository did not publish SHA-512 for the files checked. That is not a checksum failure.")

sample_name = sample.rsplit("/", 1)[-1]
sample_path = os.path.join(out, sample_name)
print(f"[amoro-staging] MANIFEST_JAR: {sample_name}")
if not os.path.isfile(sample_path):
    print("[amoro-staging] ERROR: sample jar was not kept")
    sys.exit(1)
with zipfile.ZipFile(sample_path) as zf:
    names = zf.namelist()
    jdk = ""
    if "META-INF/MANIFEST.MF" in names:
        manifest = zf.read("META-INF/MANIFEST.MF").decode("utf-8", "replace")
        for line in manifest.splitlines():
            if line.startswith("Build-Jdk-Spec:"):
                jdk = line.split(":", 1)[1].strip()
    print(f"[amoro-staging] BUILD_JDK_SPEC: {jdk or 'absent'}")
    origin = ""
    commit = ""
    dirty = ""
    for name in names:
        lower = name.lower()
        if not lower.endswith((".properties", ".txt")):
            continue
        if "git" not in lower and "build" not in lower:
            continue
        text = zf.read(name).decode("utf-8", "replace")
        if "git.remote.origin.url" not in text and "git.commit.id" not in text:
            continue
        print(f"[amoro-staging] MARKER_FILE: {name}")
        for line in text.splitlines():
            if line.startswith("git.remote.origin.url=") and not origin:
                origin = line.split("=", 1)[1].strip()
            elif line.startswith("git.commit.id=") and "abbrev" not in line and not commit:
                commit = line.split("=", 1)[1].strip()
            elif line.startswith("git.dirty=") and not dirty:
                dirty = line.split("=", 1)[1].strip()
    print(f"[amoro-staging] ORIGIN: {origin or 'absent'}")
    print(f"[amoro-staging] MARKER_COMMIT: {commit or 'absent'}")
    print(f"[amoro-staging] MARKER_DIRTY: {dirty or 'absent'}")
    if origin and "github.com/apache/amoro" not in origin and "gitbox.apache.org" not in origin:
        print("[amoro-staging] NOTE: recorded origin is not the Apache remote. That URL alone is not a failed step.")

if fail:
    print("[amoro-staging] RESULT: FAIL")
    sys.exit(1)
print("[amoro-staging] RESULT: PASS")
PY
echo "[amoro-staging] RESULT: PASS"
exit 0
