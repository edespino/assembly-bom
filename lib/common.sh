#!/usr/bin/env bash
# lib/common.sh — General-purpose functions for Assembly BOM

# --------------------------------------------------------------------
# Formatting Utilities
# --------------------------------------------------------------------

format_duration() {
  local total_seconds="$1"
  if [[ "$total_seconds" -lt 1 ]]; then
    echo "<1s"
  else
    local hours=$(( total_seconds / 3600 ))
    local minutes=$(( (total_seconds % 3600) / 60 ))
    local seconds=$(( total_seconds % 60 ))
    printf "%02d:%02d:%02d\n" "$hours" "$minutes" "$seconds"
  fi
}

section() {
  echo "==> $1..."
}

section_complete() {
  echo "✅ $1 complete (duration: $(format_duration "$(($(date +%s) - $2))"))"
}

log() {
  printf "[%s] %s\n" "$(date '+%H:%M:%S')" "$*"
}

# --------------------------------------------------------------------
# Component Field Output Helpers (used by --list)
# --------------------------------------------------------------------

print_git_info() {
  local layer="$1" idx="$2"
  local url branch
  url=$(yq e ".products.${PRODUCT}.components.${layer}[${idx}].url" bom.yaml 2>/dev/null || echo "")
  branch=$(yq e ".products.${PRODUCT}.components.${layer}[${idx}].branch" bom.yaml 2>/dev/null || echo "")
  echo "      Git:"
  [[ -z "$url" || "$url" == "null" || "$url" == "[]" ]] && url="(none)"
  [[ -z "$branch" || "$branch" == "null" || "$branch" == "[]" ]] && branch="(none)"
  echo "        url: $url"
  echo "        branch: $branch"
}

print_steps() {
  local layer="$1" idx="$2"
  echo "      Steps:"
  mapfile -t steps < <(yq e ".products.${PRODUCT}.components.${layer}[${idx}].steps[]" bom.yaml 2>/dev/null || true)
  if [[ ${#steps[@]} -eq 0 || "${steps[0]}" == "null" || "${steps[0]}" == "[]" ]]; then
    echo "        (none)"
  else
    for s in "${steps[@]}"; do echo "        - $s"; done
  fi
}

print_env() {
  local layer="$1" idx="$2"
  echo "      Env:"
  local keys
  keys=$(yq e ".products.${PRODUCT}.components.${layer}[${idx}].env | keys | .[]" bom.yaml 2>/dev/null || true)
  if [[ -z "$keys" || "$keys" == "null" || "$keys" == "[]" ]]; then
    echo "        (none)"
  else
    for k in $keys; do
      local val
      val=$(yq e ".products.${PRODUCT}.components.${layer}[${idx}].env.${k}" bom.yaml)
      echo "        $k: $val"
    done
  fi
}

print_configure_flags() {
  local layer="$1" idx="$2"
  local config
  config=$(yq e ".products.${PRODUCT}.components.${layer}[${idx}].configure_flags" bom.yaml 2>/dev/null || echo "")
  echo "      Configure Flags:"
  if [[ -z "$config" || "$config" == "null" || "$config" == "[]" ]]; then
    echo "        (none)"
  else
    echo "$config" | sed 's/^/        /'
  fi
}

print_test_configs() {
  local layer="$1" idx="$2"
  echo "      Test Configs:"
  local count
  count=$(yq e ".products.${PRODUCT}.components.${layer}[${idx}].test_configs | length" bom.yaml 2>/dev/null || echo 0)
  if [[ "$count" -eq 0 ]]; then
    echo "        (none)"
  else
    for ((i = 0; i < count; i++)); do
      local name pgoptions target directory description
      name=$(yq e ".products.${PRODUCT}.components.${layer}[${idx}].test_configs[${i}].name" bom.yaml 2>/dev/null || echo "")
      pgoptions=$(yq e ".products.${PRODUCT}.components.${layer}[${idx}].test_configs[${i}].pgoptions" bom.yaml 2>/dev/null || echo "")
      target=$(yq e ".products.${PRODUCT}.components.${layer}[${idx}].test_configs[${i}].target" bom.yaml 2>/dev/null || echo "")
      directory=$(yq e ".products.${PRODUCT}.components.${layer}[${idx}].test_configs[${i}].directory" bom.yaml 2>/dev/null || echo "")
      description=$(yq e ".products.${PRODUCT}.components.${layer}[${idx}].test_configs[${i}].description" bom.yaml 2>/dev/null || echo "")
      
      echo "        - name: $name"
      [[ -n "$description" && "$description" != "null" ]] && echo "          description: $description"
      [[ -n "$target" && "$target" != "null" ]] && echo "          target: $target"
      [[ -n "$directory" && "$directory" != "null" ]] && echo "          directory: $directory"
      [[ -n "$pgoptions" && "$pgoptions" != "null" ]] && echo "          pgoptions: $pgoptions"
    done
  fi
}
