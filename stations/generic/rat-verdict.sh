# shellcheck shell=bash
# Sourced by the RAT stations and by rat-verdict-test.sh.
# A missing recognized count is a failure, not zero.
# Do not print a pass from a Maven banner alone.

rat_report_unapproved_count() {
  local file=$1 count
  [[ -f "$file" ]] || return 2
  # Always exit 0 from awk. A missing line prints MISSING so set -e
  # in the caller does not treat the lookup itself as a crash.
  count=$(awk '
    /! Unapproved:/ { print $3; found=1; exit }
    /^[[:space:]]*Unapproved:/ { print $2; found=1; exit }
    /^[[:space:]]*Unknown Licenses:[[:space:]]*[0-9]+/ { print $3; found=1; exit }
    /^[[:space:]]*[0-9]+ Unknown Licenses/ { print $1; found=1; exit }
    END { if (!found) print "MISSING" }
  ' "$file")
  if [[ "$count" == "MISSING" || ! "$count" =~ ^[0-9]+$ ]]; then
    return 2
  fi
  printf '%s\n' "$count"
}

# Return 0 when the log must not become a pass.
# Return 1 when the log is clean. A missing counter line is clean.
rat_maven_log_blocks_pass() {
  local log=$1 count
  [[ -f "$log" ]] || return 0
  if grep -q 'Build failures were ignored' "$log"; then
    return 0
  fi
  count=$(awk '
    /Unexpected count for UNAPPROVED/ {
      if (match($0, /Count: *[0-9]+/)) {
        piece = substr($0, RSTART, RLENGTH)
        sub(/^Count: */, "", piece)
        s += piece + 0
      }
    }
    END { print s + 0 }
  ' "$log")
  if [[ "$count" -gt 0 ]]; then
    return 0
  fi
  if grep -q 'BUILD FAILURE' "$log"; then
    return 0
  fi
  if ! grep -q 'BUILD SUCCESS' "$log"; then
    return 0
  fi
  return 1
}

rat_unapproved_paths() {
  local file=$1
  [[ -f "$file" ]] || return 0
  awk '
    function emit(p) {
      if (p ~ /^\// && !seen[p]++) print p
    }
    /Files with unapproved licenses/ { grab=1; next }
    grab && /^[[:space:]]*$/ { next }
    grab && /^[*]+$/ { if (seen_path) grab=0; next }
    grab && /^[[:space:]]*Detail[[:space:]]*$/ { grab=0; next }
    grab && /^[[:space:]]+\// {
      sub(/^[[:space:]]+/, "")
      sub(/[[:space:]].*$/, "")
      if ($0 ~ /^\// && $0 !~ /^\/[*\/]/) {
        seen_path=1
        emit($0)
      }
      next
    }
    grab { grab=0; next }
    /^! \// {
      p=substr($0, 3)
      sub(/[[:space:]].*$/, "", p)
      emit(p)
      next
    }
    index($0, "!?????") > 0 {
      p=$0
      n=index(p, "!?????")
      p=substr(p, n + 6)
      sub(/^[[:space:]]+/, "", p)
      sub(/[[:space:]].*$/, "", p)
      emit(p)
    }
  ' "$file"
}
