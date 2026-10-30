#!/usr/bin/env bash
# Record the jars built from the JCasbin tarball.
# The pom default revision is 0.0.0. The build must pass -Drevision.
# Archive filenames include incubating. The Maven version does not.
# A missing incubating token is a warning, not a failure, when the
# release number matches and the archive names include incubating.
set -euo pipefail

NAME="${NAME:?Missing NAME environment variable}"
if [[ "$NAME" != "jcasbin" ]]; then
  echo "[jcasbin-versions] ERROR: this step is jcasbin-only (NAME=${NAME})" >&2
  exit 1
fi

PARTS_DIR="${PARTS_DIR:-$HOME/bom-parts}"
COMPONENT_DIR="$PARTS_DIR/$NAME"
RELEASE_VERSION="${RELEASE_VERSION:?Missing RELEASE_VERSION}"

note() { echo "[jcasbin-versions] $*"; }

note "Component: $NAME"
note "Release number: $RELEASE_VERSION"

if [[ ! -d "$COMPONENT_DIR" ]]; then
  note "FAIL: component directory not found: $COMPONENT_DIR"
  exit 1
fi

mapfile -t JARS < <(find "$COMPONENT_DIR" -path '*/target/*.jar' -printf '%f\n' | sort -u)
if [[ ${#JARS[@]} -eq 0 ]]; then
  note "FAIL: no jars under $COMPONENT_DIR"
  exit 1
fi

note "Jars:"
for jar in "${JARS[@]}"; do
  note "  $jar"
done

fail=0
warn=0
for required in \
  "jcasbin-${RELEASE_VERSION}.jar" \
  "jcasbin-${RELEASE_VERSION}-sources.jar" \
  "jcasbin-${RELEASE_VERSION}-javadoc.jar"
do
  found=0
  for jar in "${JARS[@]}"; do
    if [[ "$jar" == "$required" ]]; then
      found=1
      break
    fi
  done
  if [[ "$found" -eq 0 ]]; then
    note "FAIL: missing $required"
    fail=1
  fi
done

for jar in "${JARS[@]}"; do
  if [[ "$jar" != *"${RELEASE_VERSION}"* ]]; then
    note "FAIL: $jar does not contain $RELEASE_VERSION"
    fail=1
  fi
  if [[ "$jar" != *incubating* ]]; then
    note "WARN: $jar does not say incubating"
    warn=1
  fi
done

note "Source archive filenames include incubating. The Maven version is the release number without incubating. That warning is not a failure when the jar names match RELEASE_VERSION."

if [[ "$fail" -ne 0 ]]; then
  note "RESULT: FAIL"
  exit 1
fi
if [[ "$warn" -ne 0 ]]; then
  note "RESULT: PASS with warnings"
  exit 0
fi
note "RESULT: PASS"
exit 0
