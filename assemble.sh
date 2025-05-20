#!/usr/bin/env bash
# --------------------------------------------------------------------
# File     : assemble.sh
# Purpose  : Safe, explicit orchestrator for Assembly BOM
# --------------------------------------------------------------------

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load shared functions
COMMON_SH="${SCRIPT_DIR}/lib/common.sh"
if [ -f "${COMMON_SH}" ]; then
    # shellcheck disable=SC1090
    source "${COMMON_SH}"
else
    echo "[assemble.sh] Missing library: ${COMMON_SH}" >&2
    exit 1
fi

cd "$SCRIPT_DIR"

LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/assemble-$(date '+%Y%m%d-%H%M%S').log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Load environment and bootstrap tools
# shellcheck disable=SC1091
[ -f config/env.sh ] && source config/env.sh
# shellcheck disable=SC1091
[ -f config/bootstrap.sh ] && source config/bootstrap.sh

# Validate bom.yaml
if [[ ! -f bom.yaml ]]; then
  echo "[assemble] Error: bom.yaml not found!"
  exit 1
fi
if ! yq e '.' bom.yaml >/dev/null 2>&1; then
  echo "[assemble] Error: bom.yaml is not valid YAML."
  exit 1
fi

if [[ "$#" -eq 0 ]]; then
  set -- --help
fi

OPTIONS=c:s:t:hlrdfGSECDT
LONGOPTS=component:,steps:,test-config:,help,list,run,dry-run,force

PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
eval set -- "$PARSED"

ONLY_COMPONENTS=()
STEP_OVERRIDE=""
TEST_CONFIG_OVERRIDE=""
DO_RUN=false
DO_DRY_RUN=false
FORCE_RESET=false

SHOW_LIST=false
SHOW_GIT=false
SHOW_STEPS=false
SHOW_ENV=false
SHOW_CONFIGURE=false
SHOW_TEST_CONFIGS=false

while true; do
  case "$1" in
    -c|--component) IFS=',' read -ra ONLY_COMPONENTS <<< "$2"; shift 2 ;;
    -s|--steps) STEP_OVERRIDE="$2"; shift 2 ;;
    -t|--test-config) TEST_CONFIG_OVERRIDE="$2"; shift 2 ;;
    -l) SHOW_LIST=true; shift ;;
    -G) SHOW_GIT=true; shift ;;
    -S) SHOW_STEPS=true; shift ;;
    -E) SHOW_ENV=true; shift ;;
    -C) SHOW_CONFIGURE=true; shift ;;
    -T) SHOW_TEST_CONFIGS=true; shift ;;
    -D)
      SHOW_LIST=true
      SHOW_GIT=true
      SHOW_STEPS=true
      SHOW_ENV=true
      SHOW_CONFIGURE=true
      SHOW_TEST_CONFIGS=true
      shift
      ;;
    -f|--force) FORCE_RESET=true; shift ;;
    -r|--run) DO_RUN=true; shift ;;
    -d|--dry-run) DO_DRY_RUN=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--run] [--list] [--dry-run] [-c <names>] [-s <steps>] [-f]"
      echo ""
      echo "  -r, --run            Run BOM steps (must be explicitly provided)"
      echo "  -l                   List component names by layer"
      echo "  -G                   Show Git info (url, branch)"
      echo "  -S                   Show steps"
      echo "  -E                   Show environment variables"
      echo "  -C                   Show configure flags"
      echo "  -T                   Show test configurations"
      echo "  -D                   Show all details (-GSECT)"
      echo "  -f, --force          Prompt to clean parts/<component> before cloning"
      echo "  -c, --component      Filter components by name"
      echo "  -s, --steps          Override steps (comma-separated)"
      echo "  -t, --test-config    Set test configuration for components"
      echo "  -d, --dry-run        Show build order only"
      echo "  -h, --help           Show this help message"
      exit 0
      ;;
    --) shift; break ;;
    *) echo "[assemble] Unknown option: $1"; exit 1 ;;
  esac
done

PRODUCT=$(yq e '.products | keys | .[0]' bom.yaml)

# --------------------------------------------------------------------
# Force Reset Helper
# --------------------------------------------------------------------
force_reset_repo() {
  local name="$1"
  local branch="$2"
  local path="parts/$name"

  if [[ ! -d "$path/.git" ]]; then
    echo "[force-reset] Skipping: $path is not a Git repository."
    return
  fi

  echo ""
  echo "⚠️  WARNING: This will delete ALL local changes in '$path'"
  echo "            and reset it to origin/$branch."
  echo "            This action CANNOT be undone."
  echo ""
  read -rp "Type 'yes' to continue: " confirm
  if [[ "$confirm" != "yes" ]]; then
    echo "[force-reset] Aborted for $name"
    return
  fi

  echo "[force-reset] Cleaning parts/$name ..."
  git -C "$path" fetch origin
  git -C "$path" checkout -f "$branch"
  git -C "$path" reset --hard "origin/$branch"
  git -C "$path" clean -xfd
  echo "[force-reset] Complete."
}

# --------------------------------------------------------------------
# LIST MODE
# --------------------------------------------------------------------
if [[ "$SHOW_LIST" == true ]]; then
  echo "[assemble] Component listing for product: $PRODUCT"

  for LAYER in dependencies core extensions components; do
    COUNT=$(yq e ".products.${PRODUCT}.components.${LAYER} | length" bom.yaml 2>/dev/null || echo 0)
    [[ "$COUNT" -eq 0 ]] && continue

    MATCHED=()

    for ((i = 0; i < COUNT; i++)); do
      NAME=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].name" bom.yaml)

      if (( ${#ONLY_COMPONENTS[@]} > 0 )); then
        MATCH=false
        for COMP in "${ONLY_COMPONENTS[@]}"; do
          if [[ "$NAME" == "$COMP" ]]; then
            MATCH=true
            break
          fi
        done
        $MATCH || continue
      fi

      MATCHED+=("$i")
    done

    [[ ${#MATCHED[@]} -eq 0 ]] && continue

    echo ""
    echo "$LAYER:"
    for i in "${MATCHED[@]}"; do
      NAME=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].name" bom.yaml)
      echo "  - $NAME"
      [[ "$SHOW_GIT" == true ]] && print_git_info "$LAYER" "$i"
      [[ "$SHOW_STEPS" == true ]] && print_steps "$LAYER" "$i"
      [[ "$SHOW_ENV" == true ]] && print_env "$LAYER" "$i"
      [[ "$SHOW_CONFIGURE" == true ]] && print_configure_flags "$LAYER" "$i"
      [[ "$SHOW_TEST_CONFIGS" == true ]] && print_test_configs "$LAYER" "$i"
    done
  done

  exit 0
fi

# --------------------------------------------------------------------
# DRY-RUN MODE
# --------------------------------------------------------------------
if [[ "$DO_DRY_RUN" == true ]]; then
  echo "[assemble] Dry run: Build order based on layer ordering (dependencies → core → extensions → components)"
  for LAYER in dependencies core extensions components; do
    COUNT=$(yq e ".products.${PRODUCT}.components.${LAYER} | length" bom.yaml 2>/dev/null || echo 0)
    if [[ "$COUNT" -eq 0 ]]; then continue; fi
    echo ""
    echo "$LAYER:"
    for ((i = 0; i < COUNT; i++)); do
      NAME=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].name" bom.yaml)
      echo "  - $NAME"
    done
  done
  exit 0
fi

# --------------------------------------------------------------------
# DEFAULT / RUN MODE
# --------------------------------------------------------------------
if [[ "$DO_RUN" != true ]]; then
  echo "[assemble] No action taken. Use --run to execute, or --list to inspect."
  echo "Try: $0 --run --component cloudberry --steps build,test"
  exit 0
fi

echo "[assemble] Building product: $PRODUCT"
START_TIME=$(date +%s)
SUMMARY_LINES=()

sudo chmod a+w /usr/local

for LAYER in dependencies core extensions components; do
  COUNT=$(yq e ".products.${PRODUCT}.components.${LAYER} | length" bom.yaml 2>/dev/null || echo 0)
  if [[ "$COUNT" -eq 0 ]]; then continue; fi

  echo "[assemble] Processing $LAYER components..."

  for ((i = 0; i < COUNT; i++)); do
    NAME=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].name" bom.yaml)

    if (( ${#ONLY_COMPONENTS[@]} > 0 )); then
      SKIP=true
      for COMP in "${ONLY_COMPONENTS[@]}"; do
        if [[ "$NAME" == "$COMP" ]]; then
          SKIP=false
          break
        fi
      done
      $SKIP && continue
    fi

    URL=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].url" bom.yaml)
    BRANCH=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].branch" bom.yaml)
    CONFIGURE_FLAGS=$(yq e -o=props ".products.${PRODUCT}.components.${LAYER}[$i].configure_flags" bom.yaml)

    if [[ -n "$STEP_OVERRIDE" ]]; then
      IFS=',' read -ra STEPS <<< "$STEP_OVERRIDE"
    else
      mapfile -t STEPS < <(yq e ".products.${PRODUCT}.components.${LAYER}[$i].steps[]" bom.yaml)
    fi

    if [[ "$FORCE_RESET" == true && " ${STEPS[*]} " == *" clone "* ]]; then
      force_reset_repo "$NAME" "$BRANCH"
    fi

    echo "[assemble] Component: $NAME"
    export NAME URL BRANCH CONFIGURE_FLAGS
    export INSTALL_PREFIX="/usr/local/$NAME"

    ENV_KEYS=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].env | keys | .[]" bom.yaml 2>/dev/null || true)
    for KEY in $ENV_KEYS; do
      VALUE=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].env.$KEY" bom.yaml)
      export "$KEY"="$VALUE"
      echo "[assemble]     ENV: $KEY=$VALUE"
    done

    # Export test configuration if provided
    if [[ -n "$TEST_CONFIG_OVERRIDE" ]]; then
      export TEST_CONFIG_NAME="$TEST_CONFIG_OVERRIDE"
      echo "[assemble]     ENV: TEST_CONFIG_NAME=$TEST_CONFIG_OVERRIDE"
    fi

    STEP_TIMINGS=()
    COMPONENT_START=$(date +%s)

    for STEP in "${STEPS[@]}"; do
      SCRIPT="stations/${STEP}-${NAME}.sh"
      FALLBACK="stations/${STEP}.sh"
      echo "[assemble] --> Step: $STEP"
      STEP_START=$(date +%s)

      if [[ -x "$SCRIPT" ]]; then
        bash "$SCRIPT" "$NAME" "$URL" "$BRANCH"
      elif [[ -x "$FALLBACK" ]]; then
        if [[ "$STEP" == "clone" ]]; then
          bash "$FALLBACK" "$NAME" "$URL" "$BRANCH"
        else
          bash "$FALLBACK"
        fi
      else
        echo "[assemble] ❌ No script found for step '$STEP'"
        exit 1
      fi

      STEP_DURATION=$(( $(date +%s) - STEP_START ))
      echo "[assemble] ✅ Step completed in $(format_duration "$STEP_DURATION")"
      STEP_TIMINGS+=("    • $STEP  →  $(format_duration "$STEP_DURATION")")
    done

    COMPONENT_DURATION=$(( $(date +%s) - COMPONENT_START ))
    SUMMARY_LINES+=("")
    SUMMARY_LINES+=("[✓] $NAME  —  $(format_duration "$COMPONENT_DURATION")")
    SUMMARY_LINES+=("${STEP_TIMINGS[@]}")
  done
done

echo ""
echo "📋 Component Summary:"
printf '%s\n' "${SUMMARY_LINES[@]}"
echo ""
TOTAL_DURATION=$(( $(date +%s) - START_TIME ))
echo "✅ Assembly complete in $(format_duration "$TOTAL_DURATION")"
echo "📝 Full log: $LOG_FILE"

echo ""
echo "🔍 Postgres Extensions"
echo ""

awk '
/[[:alnum:]_]+[[:space:]]*\|[[:space:]]*default_version/ {
  if (!found) {
    printf "%-20s | %s\n", "Extension", "Version"
    print "---------------------+---------"
    found = 1
  }
  getline; getline
  split($0, a, "|")
  name = a[1]; version = a[2]
  gsub(/^ +| +$/, "", name)
  gsub(/^ +| +$/, "", version)
  printf "%-20s | %s\n", name, version
}
END {
  if (!found) {
    print "No extensions found."
  }
}' "$LOG_FILE"

exit 0

