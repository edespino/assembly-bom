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

if [[ "$#" -eq 0 ]]; then
  set -- --help
fi

OPTIONS=b:c:s:t:hlrdfgxGSECDTB
LONGOPTS=bom-file:,component:,steps:,test-config:,help,list,run,dry-run,force,debug,debug-extensions,list-boms

PARSED=$(getopt --options=$OPTIONS --longoptions=$LONGOPTS --name "$0" -- "$@")
eval set -- "$PARSED"

BOM_FILE="cloudberry-bom.yaml"
ONLY_COMPONENTS=()
STEP_OVERRIDE=""
TEST_CONFIG_OVERRIDE=""
DO_RUN=false
DO_DRY_RUN=false
FORCE_RESET=false
DEBUG_BUILD=false
DEBUG_EXTENSIONS_FLAG=false

SHOW_LIST=false
SHOW_BOMS=false
SHOW_GIT=false
SHOW_STEPS=false
SHOW_ENV=false
SHOW_CONFIGURE=false
SHOW_TEST_CONFIGS=false

while true; do
  case "$1" in
    -b|--bom-file) BOM_FILE="$2"; shift 2 ;;
    -c|--component) IFS=',' read -ra ONLY_COMPONENTS <<< "$2"; shift 2 ;;
    -s|--steps) STEP_OVERRIDE="$2"; shift 2 ;;
    -t|--test-config) TEST_CONFIG_OVERRIDE="$2"; shift 2 ;;
    -l) SHOW_LIST=true; shift ;;
    -B|--list-boms) SHOW_BOMS=true; shift ;;
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
    -g|--debug) DEBUG_BUILD=true; shift ;;
    -x|--debug-extensions) DEBUG_EXTENSIONS_FLAG=true; shift ;;
    -h|--help)
      echo "Usage: $0 [--run] [--list] [--dry-run] [-b <file>] [-c <names>] [-s <steps>] [-f]"
      echo ""
      echo "  -r, --run               Run BOM steps (must be explicitly provided)"
      echo "  -b, --bom-file          Specify alternate BOM file (default: cloudberry-bom.yaml)"
      echo "  -l                      List component names by layer"
      echo "  -B, --list-boms         List available BOM files"
      echo "  -G                      Show Git info (url, branch)"
      echo "  -S                      Show steps"
      echo "  -E                      Show environment variables"
      echo "  -C                      Show configure flags"
      echo "  -T                      Show test configurations"
      echo "  -D                      Show all details (-GSECT)"
      echo "  -f, --force             Prompt to clean \$PARTS_DIR/<component> before cloning"
      echo "  -c, --component         Filter components by name"
      echo "  -s, --steps             Override steps (comma-separated)"
      echo "  -t, --test-config       Set test configuration for components"
      echo "  -d, --dry-run           Show build order only"
      echo "  -g, --debug             Enable debug build (CFLAGS=\"-O0 -g3 -ggdb3 -fno-omit-frame-pointer -fno-inline -Wno-suggest-attribute=format\")"
      echo "  -x, --debug-extensions  Enable Cloudberry debug extensions (DEBUG_EXTENSIONS=1)"
      echo "  -h, --help              Show this help message"
      exit 0
      ;;
    --) shift; break ;;
    *) echo "[assemble] Unknown option: $1"; exit 1 ;;
  esac
done

# List available BOM files if requested
if [[ "$SHOW_BOMS" == "true" ]]; then
  echo "[assemble] Available BOM files:"
  echo ""

  # Find all *-bom.yaml files
  shopt -s nullglob
  BOM_FILES=(*-bom.yaml)
  shopt -u nullglob

  if [[ ${#BOM_FILES[@]} -eq 0 ]]; then
    echo "  No BOM files found (*-bom.yaml)"
    exit 0
  fi

  DEFAULT_BOM="cloudberry-bom.yaml"

  for bom_file in "${BOM_FILES[@]}"; do
    # Check if it's the default
    if [[ "$bom_file" == "$DEFAULT_BOM" ]]; then
      echo "  $bom_file (default)"
    else
      echo "  $bom_file"
    fi

    # Try to extract product name
    if [[ -f "$bom_file" ]] && command -v yq &> /dev/null; then
      product=$(yq e '.products | keys | .[0]' "$bom_file" 2>/dev/null || echo "")
      if [[ -n "$product" && "$product" != "null" ]]; then
        echo "    Product: $product"
      fi
    fi
  done

  echo ""
  echo "Usage: ./assemble.sh -b <bom-file> [options]"
  exit 0
fi

# Validate BOM file (after parsing command line arguments)
if [[ ! -f "${BOM_FILE}" ]]; then
  echo "[assemble] Error: ${BOM_FILE} not found!"
  exit 1
fi
if ! yq e '.' "${BOM_FILE}" >/dev/null 2>&1; then
  echo "[assemble] Error: ${BOM_FILE} is not valid YAML."
  exit 1
fi

# Export BOM_FILE so lib/common.sh can use it
export BOM_FILE

PRODUCT=$(yq e '.products | keys | .[0]' "${BOM_FILE}")

# --------------------------------------------------------------------
# Force Reset Helper
# --------------------------------------------------------------------
force_reset_repo() {
  local name="$1"
  local branch="$2"
  local path="$PARTS_DIR/$name"

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

  echo "[force-reset] Cleaning $PARTS_DIR/$name ..."
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

  for LAYER in dependencies core extensions utilities components; do
    COUNT=$(yq e ".products.${PRODUCT}.components.${LAYER} | length" "${BOM_FILE}" 2>/dev/null || echo 0)
    [[ "$COUNT" -eq 0 ]] && continue

    MATCHED=()

    for ((i = 0; i < COUNT; i++)); do
      NAME=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].name" "${BOM_FILE}")

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
      NAME=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].name" "${BOM_FILE}")
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
  echo "[assemble] Dry run: Build order based on layer ordering (dependencies → core → extensions → utilities → components)"
  for LAYER in dependencies core extensions utilities components; do
    COUNT=$(yq e ".products.${PRODUCT}.components.${LAYER} | length" "${BOM_FILE}" 2>/dev/null || echo 0)
    if [[ "$COUNT" -eq 0 ]]; then continue; fi
    echo ""
    echo "$LAYER:"
    for ((i = 0; i < COUNT; i++)); do
      NAME=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].name" "${BOM_FILE}")
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
BUILD_FAILED=false
FAILED_COMPONENTS=()

# Function to print summary (can be called at any time)
print_build_summary() {
  echo ""
  echo "========================================="
  echo "📋 Component Summary"
  echo "========================================="

  if [[ ${#SUMMARY_LINES[@]} -eq 0 ]]; then
    echo "No components processed."
  else
    printf '%s\n' "${SUMMARY_LINES[@]}"
  fi

  echo ""
  echo "========================================="
  TOTAL_DURATION=$(( $(date +%s) - START_TIME ))

  if [[ "$BUILD_FAILED" == true ]]; then
    echo "❌ Assembly FAILED in $(format_duration "$TOTAL_DURATION")"
    echo ""
    echo "Failed components:"
    for FAILED in "${FAILED_COMPONENTS[@]}"; do
      echo "  • $FAILED"
    done
  else
    echo "✅ Assembly complete in $(format_duration "$TOTAL_DURATION")"
  fi

  echo "========================================="
  echo "📝 Full log: $LOG_FILE"
  echo ""
}

# Set trap to always print summary on exit
trap print_build_summary EXIT

sudo chmod a+w /usr/local

for LAYER in dependencies core extensions utilities components; do
  COUNT=$(yq e ".products.${PRODUCT}.components.${LAYER} | length" "${BOM_FILE}" 2>/dev/null || echo 0)
  if [[ "$COUNT" -eq 0 ]]; then continue; fi

  echo "[assemble] Processing $LAYER components..."

  for ((i = 0; i < COUNT; i++)); do
    NAME=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].name" "${BOM_FILE}")

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

    URL=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].url" "${BOM_FILE}")
    BRANCH=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].branch" "${BOM_FILE}")
    CONFIGURE_FLAGS=$(yq e -o=props ".products.${PRODUCT}.components.${LAYER}[$i].configure_flags" "${BOM_FILE}")
    BUILD_FLAGS=$(yq e -o=props ".products.${PRODUCT}.components.${LAYER}[$i].build_flags" "${BOM_FILE}")

    if [[ -n "$STEP_OVERRIDE" ]]; then
      IFS=',' read -ra STEPS <<< "$STEP_OVERRIDE"
    else
      mapfile -t STEPS < <(yq e ".products.${PRODUCT}.components.${LAYER}[$i].steps[]" "${BOM_FILE}")
    fi

    if [[ "$FORCE_RESET" == true && " ${STEPS[*]} " == *" clone "* ]]; then
      force_reset_repo "$NAME" "$BRANCH"
    fi

    echo "[assemble] Component: $NAME"
    export NAME URL BRANCH CONFIGURE_FLAGS BUILD_FLAGS
    export INSTALL_PREFIX="/usr/local/$NAME"

    ENV_KEYS=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].env | keys | .[]" "${BOM_FILE}" 2>/dev/null || true)
    for KEY in $ENV_KEYS; do
      VALUE=$(yq e ".products.${PRODUCT}.components.${LAYER}[$i].env.$KEY" "${BOM_FILE}")
      export "$KEY"="$VALUE"
      echo "[assemble]     ENV: $KEY=$VALUE"
    done

    # Export test configuration if provided
    if [[ -n "$TEST_CONFIG_OVERRIDE" ]]; then
      export TEST_CONFIG_NAME="$TEST_CONFIG_OVERRIDE"
      echo "[assemble]     ENV: TEST_CONFIG_NAME=$TEST_CONFIG_OVERRIDE"
    fi

    # Export debug build flags if enabled
    if [[ "$DEBUG_BUILD" == true ]]; then
      export CFLAGS="-O0 -g3 -ggdb3 -fno-omit-frame-pointer -fno-inline -Wno-suggest-attribute=format -Wno-maybe-uninitialized"
      export CXXFLAGS="-O0 -g3 -ggdb3 -fno-omit-frame-pointer -fno-inline -Wno-suggest-attribute=format -Wno-maybe-uninitialized"
      echo "[assemble]     DEBUG: CFLAGS=$CFLAGS"
      echo "[assemble]     DEBUG: CXXFLAGS=$CXXFLAGS"
    fi

    # Export Cloudberry debug extensions flag if enabled
    if [[ "$DEBUG_EXTENSIONS_FLAG" == true ]]; then
      export DEBUG_EXTENSIONS=1
      echo "[assemble]     DEBUG: DEBUG_EXTENSIONS=1"
    fi

    STEP_TIMINGS=()
    COMPONENT_START=$(date +%s)

    for STEP in "${STEPS[@]}"; do
      SCRIPT="stations/${LAYER}/${NAME}/${STEP}.sh"
      FALLBACK="stations/generic/${STEP}.sh"
      echo "[assemble] --> Step: $STEP"
      STEP_START=$(date +%s)

      # Execute step and capture exit code
      STEP_EXIT_CODE=0
      if [[ -x "$SCRIPT" ]]; then
        bash "$SCRIPT" "$NAME" "$URL" "$BRANCH" || STEP_EXIT_CODE=$?
      elif [[ -x "$FALLBACK" ]]; then
        if [[ "$STEP" == "clone" ]]; then
          bash "$FALLBACK" "$NAME" "$URL" "$BRANCH" || STEP_EXIT_CODE=$?
        else
          bash "$FALLBACK" || STEP_EXIT_CODE=$?
        fi
      else
        echo "[assemble] ❌ No script found for step '$STEP'"
        STEP_EXIT_CODE=1
      fi

      STEP_DURATION=$(( $(date +%s) - STEP_START ))

      # Check if step succeeded or failed
      if [[ $STEP_EXIT_CODE -eq 0 ]]; then
        echo "[assemble] ✅ Step completed in $(format_duration "$STEP_DURATION")"
        STEP_TIMINGS+=("    • $STEP  →  $(format_duration "$STEP_DURATION") ✅")
      else
        echo "[assemble] ❌ Step FAILED in $(format_duration "$STEP_DURATION") (exit code: $STEP_EXIT_CODE)"
        STEP_TIMINGS+=("    • $STEP  →  $(format_duration "$STEP_DURATION") ❌ FAILED")
        BUILD_FAILED=true
        FAILED_COMPONENTS+=("$NAME (step: $STEP, exit code: $STEP_EXIT_CODE)")

        # Add partial component summary before exiting
        COMPONENT_DURATION=$(( $(date +%s) - COMPONENT_START ))
        SUMMARY_LINES+=("")
        SUMMARY_LINES+=("[✗] $NAME  —  $(format_duration "$COMPONENT_DURATION") ❌ FAILED at step: $STEP")
        SUMMARY_LINES+=("${STEP_TIMINGS[@]}")

        # Exit immediately on failure
        exit $STEP_EXIT_CODE
      fi
    done

    COMPONENT_DURATION=$(( $(date +%s) - COMPONENT_START ))
    SUMMARY_LINES+=("")
    SUMMARY_LINES+=("[✓] $NAME  —  $(format_duration "$COMPONENT_DURATION")")
    SUMMARY_LINES+=("${STEP_TIMINGS[@]}")
  done
done

# Summary will be printed by the EXIT trap (print_build_summary function)

# Only show Postgres extensions if build succeeded
if [[ "$BUILD_FAILED" == false ]]; then
  echo ""
  echo "🔍 Postgres Extensions"
  echo ""
fi

if [[ "$BUILD_FAILED" == false ]]; then
  # Check for extension marker files from different components
  POSTGIS_MARKER="/tmp/claude_postgis_extensions.marker"
  PXF_MARKER="/tmp/claude_pxf_extensions.marker"
  COMBINED_MARKER="/tmp/claude_all_extensions.marker"

  # Combine all extension marker files
  rm -f "$COMBINED_MARKER"
  for marker in "$POSTGIS_MARKER" "$PXF_MARKER"; do
    if [ -f "$marker" ]; then
      cat "$marker" >> "$COMBINED_MARKER"
    fi
  done

  if [ -f "$COMBINED_MARKER" ]; then
    awk '
    /[[:alnum:]_]+[[:space:]]*\|[[:space:]]*default_version/ {
      if (!found) {
        printf "%-30s | %-15s | %-17s | %s\n", "Extension", "Default Version", "Installed Version", "Status"
        print "-------------------------------+-----------------+-------------------+-----------"
        found = 1
      }
      # Process data rows
      while ((getline) > 0) {
        if (/^[[:space:]]*$/ || /^\([0-9]+ rows\)/) break
        if (/^-+\+/) continue
        if (/[[:alnum:]_]+[[:space:]]*\|/) {
          split($0, a, "|")
          name = a[1]; version = a[2]; installed = a[3]; status = a[4]
          gsub(/^ +| +$/, "", name)
          gsub(/^ +| +$/, "", version)
          gsub(/^ +| +$/, "", installed)
          gsub(/^ +| +$/, "", status)
          printf "%-30s | %-15s | %-17s | %s\n", name, version, installed, status
        }
      }
    }
    END {
      if (!found) {
        print "No extensions found."
      }
    }' "$COMBINED_MARKER"

    # Clean up marker files
    rm -f "$POSTGIS_MARKER" "$PXF_MARKER" "$COMBINED_MARKER"
  else
    # Fallback to old method if marker file doesn't exist
    awk '
    /[[:alnum:]_]+[[:space:]]*\|[[:space:]]*default_version/ {
      if (!found) {
        printf "%-30s | %-15s | %-17s | %s\n", "Extension", "Default Version", "Installed Version", "Status"
        print "-------------------------------+-----------------+-------------------+-----------"
        found = 1
      }
      # Process data rows
      while ((getline) > 0) {
        if (/^[[:space:]]*$/ || /^\([0-9]+ rows\)/) break
        if (/^-+\+/) continue
        if (/[[:alnum:]_]+[[:space:]]*\|/) {
          split($0, a, "|")
          name = a[1]; version = a[2]; installed = a[3]; status = a[4]
          gsub(/^ +| +$/, "", name)
          gsub(/^ +| +$/, "", version)
          gsub(/^ +| +$/, "", installed)
          gsub(/^ +| +$/, "", status)
          printf "%-30s | %-15s | %-17s | %s\n", name, version, installed, status
        }
      }
    }
    END {
      if (!found) {
        print "No extensions found."
      }
    }' "$LOG_FILE"
  fi
fi

# Exit with appropriate code
if [[ "$BUILD_FAILED" == true ]]; then
  exit 1
else
  exit 0
fi

