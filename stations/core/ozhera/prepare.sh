#!/usr/bin/env bash
# Install the toolchain OzHera review steps need and the image does not ship.
# pom.xml sets maven.compiler.source to 21. The image default Java is 8.
# Do not change the image default Java. Later steps set JAVA_HOME.
# Maven 3.9 is installed because the image Maven is 3.6.3.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "ozhera" ]]; then
  echo "[ozhera-prepare] ERROR: this step is ozhera-only (NAME=${NAME})" >&2
  exit 1
fi

echo "[ozhera-prepare] Component: $NAME"

JAVA21_HOME=/usr/lib/jvm/java-21-openjdk
if [[ -x "$JAVA21_HOME/bin/java" ]]; then
  echo "[ozhera-prepare] Java 21 already present: $($JAVA21_HOME/bin/java -version 2>&1 | head -1)"
else
  echo "[ozhera-prepare] Installing Java 21. The image does not have $JAVA21_HOME."
  echo "[ozhera-prepare] The extracted pom requires source and target 21."
  sudo dnf install -y java-21-openjdk-devel
  if [[ ! -x "$JAVA21_HOME/bin/java" ]]; then
    echo "[ozhera-prepare] ERROR: Java 21 install did not create $JAVA21_HOME"
    exit 1
  fi
  echo "[ozhera-prepare] Installed after launch: java-21-openjdk-devel"
  echo "[ozhera-prepare] $($JAVA21_HOME/bin/java -version 2>&1 | head -1)"
fi

if ! command -v git >/dev/null 2>&1; then
  echo "[ozhera-prepare] Installing git. compare-to-tag needs it and it was not on PATH."
  sudo dnf install -y git
  echo "[ozhera-prepare] Installed after launch: git"
fi
echo "[ozhera-prepare] git: $(command -v git) $(git --version)"

MVN_HOME="${HOME}/opt/apache-maven-3.9.16"
MVN_BIN="$MVN_HOME/bin/mvn"
EXPECTED_SHA512="831a8591fe20c8243b1dbe7d71e3244f31d1665b0804b2e825e38cbbe5ce0cafb8338851f90780735568773e0a6cd07bbec107cda0b896b008b861075358b6f6"

if [[ -x "$MVN_BIN" ]]; then
  mvn_line=$("$MVN_BIN" -version | head -1)
  echo "[ozhera-prepare] Maven already present: $mvn_line"
  case "$mvn_line" in
    "Apache Maven 3.9.16 "*) ;;
    *)
      echo "[ozhera-prepare] ERROR: $MVN_BIN is not Maven 3.9.16 ($mvn_line)"
      exit 1
      ;;
  esac
else
  echo "[ozhera-prepare] Installing Maven 3.9.16 under $MVN_HOME"
  echo "[ozhera-prepare] Image Maven is 3.6.3. This install does not replace it."
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  url="https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.16/apache-maven-3.9.16-bin.tar.gz"
  curl -fsSL -o "$work/apache-maven-3.9.16-bin.tar.gz" "$url"
  curl -fsSL -o "$work/apache-maven-3.9.16-bin.tar.gz.sha512" "${url}.sha512"
  published=$(awk '{print $1}' "$work/apache-maven-3.9.16-bin.tar.gz.sha512")
  actual=$(sha512sum "$work/apache-maven-3.9.16-bin.tar.gz" | awk '{print $1}')
  if [[ "$actual" != "$published" || "$actual" != "$EXPECTED_SHA512" ]]; then
    echo "[ozhera-prepare] ERROR: Maven 3.9.16 SHA-512 mismatch"
    exit 1
  fi
  echo "[ozhera-prepare] SHA-512 matched the published file and the pinned digest"
  mkdir -p "${HOME}/opt"
  tar -xzf "$work/apache-maven-3.9.16-bin.tar.gz" -C "${HOME}/opt"
  if [[ ! -x "$MVN_BIN" ]]; then
    echo "[ozhera-prepare] ERROR: Maven install did not create $MVN_BIN"
    exit 1
  fi
  echo "[ozhera-prepare] Installed after launch: apache-maven-3.9.16"
  echo "[ozhera-prepare] $($MVN_BIN -version | head -1)"
fi

echo "[ozhera-prepare] Image default Java is unchanged."
echo "[ozhera-prepare] RESULT: PASS"
exit 0
