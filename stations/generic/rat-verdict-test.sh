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

echo "rat-verdict-test: ok"
