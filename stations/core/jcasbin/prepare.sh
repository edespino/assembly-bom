#!/usr/bin/env bash
# Install the toolchain JCasbin review steps need and the image does not ship.
# BUILDING.md requires Maven 3.9. The image Maven is 3.6.3.
# RAT 0.18 needs Java 17 to launch. Do not change the image default Java.
# Later steps look for Maven at $HOME/opt/apache-maven-3.9.16.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "jcasbin" ]]; then
  echo "[jcasbin-prepare] ERROR: this step is jcasbin-only (NAME=${NAME})" >&2
  exit 1
fi

echo "[jcasbin-prepare] Component: $NAME"

JAVA17_HOME=/usr/lib/jvm/java-17-openjdk
if [[ -x "$JAVA17_HOME/bin/java" ]]; then
  echo "[jcasbin-prepare] Java 17 already present: $($JAVA17_HOME/bin/java -version 2>&1 | head -1)"
else
  echo "[jcasbin-prepare] Installing Java 17. The image does not have $JAVA17_HOME."
  sudo dnf install -y java-17-openjdk-devel
  if [[ ! -x "$JAVA17_HOME/bin/java" ]]; then
    echo "[jcasbin-prepare] ERROR: Java 17 install did not create $JAVA17_HOME"
    exit 1
  fi
  echo "[jcasbin-prepare] Installed after launch: java-17-openjdk-devel"
  echo "[jcasbin-prepare] $($JAVA17_HOME/bin/java -version 2>&1 | head -1)"
fi

MVN_HOME="${HOME}/opt/apache-maven-3.9.16"
MVN_BIN="$MVN_HOME/bin/mvn"
EXPECTED_SHA512="831a8591fe20c8243b1dbe7d71e3244f31d1665b0804b2e825e38cbbe5ce0cafb8338851f90780735568773e0a6cd07bbec107cda0b896b008b861075358b6f6"

if [[ -x "$MVN_BIN" ]]; then
  mvn_line=$("$MVN_BIN" -version | head -1)
  echo "[jcasbin-prepare] Maven already present: $mvn_line"
  case "$mvn_line" in
    "Apache Maven 3.9.16 "*) ;;
    *)
      echo "[jcasbin-prepare] ERROR: $MVN_BIN is not Maven 3.9.16 ($mvn_line)"
      exit 1
      ;;
  esac
else
  echo "[jcasbin-prepare] Installing Maven 3.9.16 under $MVN_HOME"
  echo "[jcasbin-prepare] Image Maven is too old for BUILDING.md and for RAT 0.18."
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  url="https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.16/apache-maven-3.9.16-bin.tar.gz"
  curl -fsSL -o "$work/apache-maven-3.9.16-bin.tar.gz" "$url"
  curl -fsSL -o "$work/apache-maven-3.9.16-bin.tar.gz.sha512" "${url}.sha512"
  published=$(awk '{print $1}' "$work/apache-maven-3.9.16-bin.tar.gz.sha512")
  actual=$(sha512sum "$work/apache-maven-3.9.16-bin.tar.gz" | awk '{print $1}')
  if [[ "$actual" != "$published" || "$actual" != "$EXPECTED_SHA512" ]]; then
    echo "[jcasbin-prepare] ERROR: Maven 3.9.16 SHA-512 mismatch"
    exit 1
  fi
  echo "[jcasbin-prepare] SHA-512 matched the published file and the pinned digest"
  mkdir -p "${HOME}/opt"
  tar -xzf "$work/apache-maven-3.9.16-bin.tar.gz" -C "${HOME}/opt"
  if [[ ! -x "$MVN_BIN" ]]; then
    echo "[jcasbin-prepare] ERROR: Maven install did not create $MVN_BIN"
    exit 1
  fi
  echo "[jcasbin-prepare] Installed after launch: apache-maven-3.9.16"
  echo "[jcasbin-prepare] $($MVN_BIN -version | head -1)"
fi

echo "[jcasbin-prepare] RESULT: PASS"
exit 0
