#!/usr/bin/env bash
# Toolchain the Seata review steps need and the image does not ship.
# The vote compiles with JDK 8. RAT 0.18 needs Java 17 and Maven 3.9.
# Do not change the image default Java. Later steps set JAVA_HOME.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "seata" ]]; then
  echo "[seata-prepare] ERROR: this step is seata-only (NAME=${NAME})" >&2
  exit 1
fi

echo "[seata-prepare] Component: $NAME"

install_pkg() {
  local pkg=$1
  local cmd=$2
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "[seata-prepare] $cmd already present: $(command -v "$cmd")"
    return 0
  fi
  echo "[seata-prepare] Installing $pkg. The image did not have $cmd."
  sudo dnf install -y "$pkg"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "[seata-prepare] ERROR: $pkg did not provide $cmd"
    exit 1
  fi
  echo "[seata-prepare] Installed after launch: $pkg"
}

install_pkg git git
install_pkg unzip unzip
install_pkg gnupg2 gpg
echo "[seata-prepare] git: $(git --version)"
echo "[seata-prepare] unzip: $(command -v unzip)"
echo "[seata-prepare] gpg: $(gpg --version | head -1)"

JAVA17_HOME=/usr/lib/jvm/java-17-openjdk
if [[ -x "$JAVA17_HOME/bin/java" ]]; then
  echo "[seata-prepare] Java 17 already present: $($JAVA17_HOME/bin/java -version 2>&1 | head -1)"
else
  echo "[seata-prepare] Installing Java 17. RAT 0.18 needs it. The image default stays Java 8."
  sudo dnf install -y java-17-openjdk-devel
  if [[ ! -x "$JAVA17_HOME/bin/java" ]]; then
    echo "[seata-prepare] ERROR: Java 17 install did not create $JAVA17_HOME"
    exit 1
  fi
  echo "[seata-prepare] Installed after launch: java-17-openjdk-devel"
  echo "[seata-prepare] $($JAVA17_HOME/bin/java -version 2>&1 | head -1)"
fi

if [[ ! -x /usr/lib/jvm/java-1.8.0-openjdk/bin/java && ! -x /usr/lib/jvm/java-1.8.0/bin/java ]]; then
  echo "[seata-prepare] ERROR: JDK 8 is not on the image. The vote compiles with JDK 8."
  exit 1
fi
echo "[seata-prepare] JDK 8 is present. The build step sets JAVA_HOME. This step does not."

MVN_HOME="${HOME}/opt/apache-maven-3.9.16"
MVN_BIN="$MVN_HOME/bin/mvn"
EXPECTED_SHA512="831a8591fe20c8243b1dbe7d71e3244f31d1665b0804b2e825e38cbbe5ce0cafb8338851f90780735568773e0a6cd07bbec107cda0b896b008b861075358b6f6"

if [[ -x "$MVN_BIN" ]]; then
  mvn_line=$("$MVN_BIN" -version | head -1)
  echo "[seata-prepare] Maven already present: $mvn_line"
  case "$mvn_line" in
    "Apache Maven 3.9.16 "*) ;;
    *)
      echo "[seata-prepare] ERROR: $MVN_BIN is not Maven 3.9.16 ($mvn_line)"
      exit 1
      ;;
  esac
else
  echo "[seata-prepare] Installing Maven 3.9.16 under $MVN_HOME"
  echo "[seata-prepare] Image Maven is too old for RAT 0.18. This install does not replace it."
  work=$(mktemp -d)
  trap 'rm -rf "$work"' EXIT
  url="https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/3.9.16/apache-maven-3.9.16-bin.tar.gz"
  curl -fsSL -o "$work/apache-maven-3.9.16-bin.tar.gz" "$url"
  curl -fsSL -o "$work/apache-maven-3.9.16-bin.tar.gz.sha512" "${url}.sha512"
  published=$(awk '{print $1}' "$work/apache-maven-3.9.16-bin.tar.gz.sha512")
  actual=$(sha512sum "$work/apache-maven-3.9.16-bin.tar.gz" | awk '{print $1}')
  if [[ "$actual" != "$published" || "$actual" != "$EXPECTED_SHA512" ]]; then
    echo "[seata-prepare] ERROR: Maven 3.9.16 SHA-512 mismatch"
    exit 1
  fi
  echo "[seata-prepare] SHA-512 matched the published file and the pinned digest"
  mkdir -p "${HOME}/opt"
  tar -xzf "$work/apache-maven-3.9.16-bin.tar.gz" -C "${HOME}/opt"
  if [[ ! -x "$MVN_BIN" ]]; then
    echo "[seata-prepare] ERROR: Maven install did not create $MVN_BIN"
    exit 1
  fi
  echo "[seata-prepare] Installed after launch: apache-maven-3.9.16"
  echo "[seata-prepare] $($MVN_BIN -version | head -1)"
fi

echo "[seata-prepare] Image default Java is unchanged."

echo "[seata-prepare] Header check is apache-rat-plugin 0.18. license-eye is not used."
echo "[seata-prepare] RESULT: PASS"
exit 0
