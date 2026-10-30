#!/usr/bin/env bash
set -euo pipefail

# JCasbin from-tarball build. Follow BUILDING.md in the extracted tree.
# Do not use stations/generic/build.sh: that script requires a Makefile.
# Do not use the Fluss station: that script requires mvnw, which this tree
# does not ship.

NAME="${NAME:?Missing NAME environment variable}"
PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"

echo "[jcasbin-build] Component: $NAME"
echo "[jcasbin-build] Directory: $COMPONENT_DIR"
echo "[jcasbin-build] RELEASE_VERSION: $RELEASE_VERSION"

if [[ ! -d "$COMPONENT_DIR" ]]; then
  echo "[jcasbin-build] ERROR: component directory not found"
  exit 1
fi

mapfile -t TREES < <(find "$COMPONENT_DIR" -mindepth 1 -maxdepth 1 -type d -print | sort)
SELECTED=()
for tree in "${TREES[@]}"; do
  if [[ -f "$tree/pom.xml" && -f "$tree/BUILDING.md" ]]; then
    SELECTED+=("$tree")
  fi
done

if [[ ${#SELECTED[@]} -eq 0 ]]; then
  echo "[jcasbin-build] ERROR: no extracted tree with pom.xml and BUILDING.md"
  exit 1
fi

if [[ -d /usr/lib/jvm/java-1.8.0-openjdk ]]; then
  export JAVA_HOME=/usr/lib/jvm/java-1.8.0-openjdk
elif [[ -d /usr/lib/jvm/java-1.8.0 ]]; then
  export JAVA_HOME=/usr/lib/jvm/java-1.8.0
else
  echo "[jcasbin-build] ERROR: JDK 8 home not found. BUILDING.md requires JDK 8."
  exit 1
fi
export PATH="$JAVA_HOME/bin:${PATH}"

if ! command -v java >/dev/null 2>&1; then
  echo "[jcasbin-build] ERROR: java not on PATH"
  exit 1
fi
if [[ -x "${HOME}/opt/apache-maven-3.9.16/bin/mvn" ]]; then
  export PATH="${HOME}/opt/apache-maven-3.9.16/bin:${PATH}"
fi
if ! command -v mvn >/dev/null 2>&1; then
  echo "[jcasbin-build] ERROR: mvn not on PATH"
  exit 1
fi
mvn_line=$(mvn -version | head -1)
echo "[jcasbin-build] $mvn_line"
case "$mvn_line" in
  "Apache Maven 3.9"*) ;;
  *)
    echo "[jcasbin-build] ERROR: BUILDING.md requires Maven 3.9. Refusing to build on $mvn_line"
    exit 1
    ;;
esac

JAVA_LINE=$(java -version 2>&1 | head -1)
echo "[jcasbin-build] JAVA_HOME=$JAVA_HOME"
echo "[jcasbin-build] $JAVA_LINE"
case "$JAVA_LINE" in
  *1.8.*|*\"8.*) ;;
  *)
    echo "[jcasbin-build] ERROR: BUILDING.md requires JDK 8. Refusing to build on $JAVA_LINE"
    exit 1
    ;;
esac
mvn -version

for tree in "${SELECTED[@]}"; do
  echo "[jcasbin-build] Building $(basename "$tree")"
  echo "[jcasbin-build] Command: mvn -B -ntp clean verify -Dgpg.skip=true -Drevision=$RELEASE_VERSION"
  (
    cd "$tree"
    mvn -B -ntp clean verify -Dgpg.skip=true -Drevision="$RELEASE_VERSION"
  )
done

echo "[jcasbin-build] done"
