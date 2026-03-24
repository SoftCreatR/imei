#!/usr/bin/env bash

#
# Generate the release manifest and checksum file for packaged build outputs.
# The manifest is consumed by imei.sh to map distro targets to release assets.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

SOURCE_ROOT="${1:-$REPO_ROOT/dist}"
MANIFEST_PATH="${2:-$SOURCE_ROOT/release-manifest.env}"
CHECKSUMS_PATH="${3:-$SOURCE_ROOT/SHA256SUMS}"
PACKAGE_ORDER=(imei-libaom imei-libheif imei-libjxl imei-imagemagick)

mkdir -p "$(dirname "$MANIFEST_PATH")"

targets=()

{
  echo "RELEASE_TAG=$(stack_release_tag)"
  echo "IMAGEMAGICK_VERSION=$(read_version_file imagemagick)"
  echo "AOM_VERSION=$(read_version_file aom)"
  echo "LIBHEIF_VERSION=$(read_version_file libheif)"
  echo "LIBJXL_VERSION=$(read_version_file libjxl)"

  for target_dir in "$SOURCE_ROOT"/*; do
    [[ -d "$target_dir" ]] || continue
    target="$(basename "$target_dir")"
    arch_list=()

    while IFS= read -r file_name; do
      [[ "$file_name" =~ _([^_]+)\.deb$ ]] || continue
      arch_list+=("${BASH_REMATCH[1]}")
    done < <(find "$target_dir" -maxdepth 1 -type f -name '*.deb' -printf '%f\n' | sort)

    if ((${#arch_list[@]} == 0)); then
      continue
    fi

    while IFS= read -r arch; do
      key="$(manifest_target_var "$target" "$arch")"
      package_files=()

      for package_name in "${PACKAGE_ORDER[@]}"; do
        file_name="$(find "$target_dir" -maxdepth 1 -type f -name "${package_name}_*_${arch}.deb" -printf '%f\n' | sort | head -n1)"
        [[ -n "$file_name" ]] || die "Missing $package_name package in $target_dir for architecture $arch"
        package_files+=("$file_name")
      done

      targets+=("${target}-${arch}")

      printf 'TARGET_%s_ID=%q\n' "$key" "$target"
      printf 'TARGET_%s_LABEL=%q\n' "$key" "$(target_label "$target")"
      printf 'TARGET_%s_OS_FAMILY=%q\n' "$key" "$(target_os_family "$target")"
      printf 'TARGET_%s_ARCH=%q\n' "$key" "$arch"
      printf 'TARGET_%s_PACKAGES=%q\n' "$key" "${package_files[*]}"
    done < <(printf '%s\n' "${arch_list[@]}" | sort -u)
  done

  printf 'TARGETS=%q\n' "${targets[*]}"
} >"$MANIFEST_PATH"

(
  cd "$SOURCE_ROOT"
  files=()
  while IFS= read -r -d '' file_name; do
    files+=("${file_name#./}")
  done < <(find . -maxdepth 2 -type f \( -name '*.deb' -o -name 'release-manifest.env' \) -print0 | sort -z)

  for file_name in "${files[@]}"; do
    sha256sum "$file_name"
  done
) >"$CHECKSUMS_PATH"
