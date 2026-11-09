#!/usr/bin/env bash
# Internal build artifacts. Not an Apache release review.
# ARTIFACT_BUCKET unset means build as usual.
# A hit is a manifest whose version, OS, and arch match. A bare key is a miss.

artifact_bucket() {
  printf '%s' "${ARTIFACT_BUCKET:-}"
}

artifact_os_tag() {
  local id major arch
  id=linux
  major=0
  if [[ -f /etc/os-release ]]; then
    # shellcheck disable=SC1091
    source /etc/os-release
    id=${ID:-linux}
    major=${VERSION_ID%%.*}
  fi
  arch=$(uname -m)
  printf '%s%s-%s' "$id" "$major" "$arch"
}

artifact_prefix() {
  local name=$1 version=$2
  printf 's3://%s/%s/%s/%s' "$(artifact_bucket)" "$name" "$version" "$(artifact_os_tag)"
}

artifact_step_is_build() {
  case "$1" in
    clone|apache-discover-and-verify-release|apache-extract-discovered|build|install|apache-build-release|apache-validate-compliance|apache-rat|apache-validate-build-artifacts|apache-validate-release-structure)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

artifact_restore() {
  local name=${1:?} version=${2:?} dest=${3:?}
  local bucket prefix manifest_local sha
  bucket=$(artifact_bucket)
  [[ -n "$bucket" ]] || return 1
  prefix=$(artifact_prefix "$name" "$version")
  manifest_local=$(mktemp)
  if ! aws s3 cp "$prefix/manifest.txt" "$manifest_local" --region "${AWS_REGION:-us-west-2}" >/dev/null 2>&1; then
    rm -f "$manifest_local"
    return 1
  fi
  if ! grep -q "^version=${version}$" "$manifest_local" || ! grep -q "^os_tag=$(artifact_os_tag)$" "$manifest_local"; then
    rm -f "$manifest_local"
    return 1
  fi
  sha=$(awk -F= '/^sha256=/{print $2}' "$manifest_local")
  rm -f "$manifest_local"
  [[ -n "$sha" ]] || return 1
  mkdir -p "$dest"
  aws s3 cp "$prefix/${name}.tar.gz" "$dest/${name}.tar.gz" --region "${AWS_REGION:-us-west-2}"
  echo "$sha  $dest/${name}.tar.gz" | sha256sum -c -
  case "$name" in
    superset)
      docker load -i "$dest/${name}.tar.gz"
      ;;
    *)
      tar -xzf "$dest/${name}.tar.gz" -C "$dest"
      ;;
  esac
  echo "[artifact] restored $name $version from $prefix"
  return 0
}

artifact_publish() {
  local name=${1:?} version=${2:?} src=${3:?}
  local bucket prefix work sha
  bucket=$(artifact_bucket)
  [[ -n "$bucket" ]] || return 0
  prefix=$(artifact_prefix "$name" "$version")
  work=$(mktemp -d)
  if [[ "$name" == "superset" ]]; then
    docker save -o "$work/${name}.tar.gz" "$src"
  else
    tar -C "$(dirname "$src")" -czf "$work/${name}.tar.gz" "$(basename "$src")"
  fi
  sha=$(sha256sum "$work/${name}.tar.gz" | awk '{print $1}')
  {
    echo "version=${version}"
    echo "os_tag=$(artifact_os_tag)"
    echo "sha256=${sha}"
    echo "name=${name}"
  } > "$work/manifest.txt"
  aws s3 cp "$work/${name}.tar.gz" "$prefix/${name}.tar.gz" --region "${AWS_REGION:-us-west-2}"
  aws s3 cp "$work/manifest.txt" "$prefix/manifest.txt" --region "${AWS_REGION:-us-west-2}"
  rm -rf "$work"
  echo "[artifact] published $name $version to $prefix sha256=${sha}"
}
