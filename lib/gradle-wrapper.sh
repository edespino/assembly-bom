#!/usr/bin/env bash
# Point a Gradle wrapper at a host that actually returns the distribution.
# services.gradle.org and the GitHub release it redirects to can return 504
# or time out. That is not a compile failure. A longer networkTimeout does
# not fix a 504.

gradle_use_reachable_distribution() {
  local props="$1"
  [[ -f "$props" ]] || return 0
  sed -i 's/networkTimeout=10000/networkTimeout=180000/' "$props"
  local url code
  url=$(sed -n 's/^distributionUrl=//p' "$props" | head -1 | sed 's/\\:/:/g')
  [[ -n "$url" ]] || return 0
  code=$(curl -sI -o /dev/null -w '%{http_code}' -L --max-time 20 "$url" || true)
  if [[ "$code" == "200" ]]; then
    return 0
  fi
  echo "[gradle] distribution host returned ${code:-none}; using mirrors.cloud.tencent.com" >&2
  sed -i 's|services.gradle.org/distributions/|mirrors.cloud.tencent.com/gradle/|' "$props"
}
