#!/usr/bin/env bash
# Fail if a RAT unapproved count, a missing count, or an ignored Maven
# failure can still be treated as a pass.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
# shellcheck disable=SC1091
source "$root/stations/generic/rat-verdict.sh"
data="$root/stations/generic/testdata"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

count=$(rat_report_unapproved_count "$data/rat-018-unapproved.txt") || fail "unapproved fixture was not readable"
[[ "$count" == "1" ]] || fail "unapproved fixture count is $count, want 1"
paths=$(rat_unapproved_paths "$data/rat-018-unapproved.txt")
printf '%s\n' "$paths" | grep -qx '/.editorconfig' || fail "unapproved fixture did not list /.editorconfig"
old_paths=$(rat_unapproved_paths "$data/rat-old-marker.txt")
printf '%s\n' "$old_paths" | grep -qx '/old-marker.txt' || fail "old !????? marker was not listed"

count=$(rat_report_unapproved_count "$data/rat-018-clean.txt") || fail "clean fixture was not readable"
[[ "$count" == "0" ]] || fail "clean fixture count is $count, want 0"

set +e
rat_report_unapproved_count "$data/rat-no-count.txt" >/dev/null
missing_rc=$?
set -e
[[ "$missing_rc" -eq 2 ]] || fail "missing count returned $missing_rc, want 2"

if rat_maven_log_blocks_pass "$data/maven-unapproved.log"; then
  :
else
  fail "unapproved Maven log did not block a pass"
fi
if rat_maven_log_blocks_pass "$data/maven-clean.log"; then
  fail "clean Maven log blocked a pass"
fi
if rat_maven_log_blocks_pass "$data/maven-no-result.log"; then
  :
else
  fail "a log with no Maven result line did not block a pass"
fi
if rat_maven_log_blocks_pass "$data/maven-count-nospace.log"; then
  :
else
  fail "Count:1 with no space did not block a pass"
fi

# A clean log returns 1. That must not abort under pipefail.
(
  set -euo pipefail
  if rat_maven_log_blocks_pass "$data/maven-clean.log"; then
    exit 1
  fi
)

generic="$root/stations/generic/apache-rat.sh"
if grep -n '^[^#]*mvn ' "$generic" | grep -q -- '-fn'; then
  fail "generic RAT mvn line passes -fn"
fi
grep -q 'RAT_MAVEN_COMMAND must not pass -fn' "$generic" || fail "generic station does not reject -fn"
grep -q 'rat-verdict.sh' "$generic" || fail "generic station does not source the verdict helper"
grep -q 'rat_report_unapproved_count' "$generic" || fail "generic station does not read the report count"
grep -q 'rat_maven_log_blocks_pass' "$generic" || fail "generic station does not check the Maven log"
grep -q 'REPORT_UNAPPROVED' "$generic" || fail "generic station does not keep the report count"

pass_line=$(grep -n 'PASSED - All files have appropriate license headers' "$generic" | head -1 | cut -d: -f1)
gate_line=$(grep -n 'rat_maven_log_blocks_pass' "$generic" | head -1 | cut -d: -f1)
report_line=$(grep -n 'rat_report_unapproved_count' "$generic" | head -1 | cut -d: -f1)
[[ -n "$pass_line" && -n "$gate_line" && -n "$report_line" ]] || fail "could not find the pass gate"
[[ "$gate_line" -lt "$pass_line" && "$report_line" -lt "$pass_line" ]] || fail "pass banner is not behind the report gate"

amoro="$root/stations/core/amoro/apache-rat.sh"
grep -q 'rat_maven_log_blocks_pass' "$amoro" || fail "amoro can pass after an ignored Maven failure"
amoro_pass=$(grep -n 'RESULT: PASS' "$amoro" | head -1 | cut -d: -f1)
amoro_gate=$(grep -n 'rat_maven_log_blocks_pass' "$amoro" | head -1 | cut -d: -f1)
[[ "$amoro_gate" -lt "$amoro_pass" ]] || fail "amoro pass is not behind the Maven log gate"

jcasbin="$root/stations/core/jcasbin/apache-rat.sh"
grep -q 'rat_report_unapproved_count' "$jcasbin" || fail "jcasbin can pass without the report count"
jcasbin_pass=$(grep -n 'RESULT: PASS' "$jcasbin" | head -1 | cut -d: -f1)
jcasbin_gate=$(grep -n 'rat_report_unapproved_count' "$jcasbin" | head -1 | cut -d: -f1)
[[ "$jcasbin_gate" -lt "$jcasbin_pass" ]] || fail "jcasbin pass is not behind the report count"

seata="$root/stations/core/seata/apache-rat.sh"
grep -q 'Build failures were ignored.' "$seata" || fail "seata no longer fails an ignored Maven failure"
grep -q 'unrecognized RAT summary' "$seata" || fail "seata treats a missing count as zero"
grep -q 'UNAPPROVED_TOTAL' "$seata" || fail "seata no longer totals the report count"
grep -q 'Maven did not finish' "$amoro" || fail "amoro ignores a non-zero Maven exit"
grep -q -- '--fail-never' "$generic" || fail "generic station does not reject --fail-never"
grep -q 'Maven exit ${RAT_EXIT_CODE} is not a pass' "$generic" || fail "generic station ignores a non-zero Maven exit"

run_stub() {
  local stub_exit=$1
  local stub_log=$2
  local tmp stub_bin out rc
  tmp=$(mktemp -d)
  stub_bin="$tmp/bin"
  mkdir -p "$stub_bin" "$tmp/parts/locktest/tree"
  printf '%s\n' '<project/>' > "$tmp/parts/locktest/tree/pom.xml"
  cat > "$stub_bin/mvn" << EOF
#!/bin/sh
mkdir -p target
cp "$data/rat-stub-clean.txt" target/rat.txt
cat "$stub_log"
exit $stub_exit
EOF
  chmod +x "$stub_bin/mvn"
  set +e
  out=$(PATH="$stub_bin:$PATH" NAME=locktest PARTS_DIR="$tmp/parts" "$BASH" "$generic" 2>&1)
  rc=$?
  set -e
  rm -rf "$tmp"
  printf '%s\n' "$out" | grep -q 'PASSED - All files have appropriate license headers' && fail "stub exit $stub_exit printed a pass"
  [[ "$rc" -ne 0 ]] || fail "stub exit $stub_exit returned 0"
}

run_stub 0 "$data/maven-no-result.log"
run_stub 1 "$data/maven-clean.log"

echo "rat-verdict-test: ok"
