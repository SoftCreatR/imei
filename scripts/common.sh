#!/usr/bin/env bash

#
# Shared shell helpers for IMEI build/release scripts.
# Keeps repository paths, target metadata, download helpers, and common formatting
# in one place so the other scripts can stay focused on their own tasks.
#

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC2034
VERSIONS_DIR="$REPO_ROOT/versions"
# shellcheck disable=SC2034
GH_FILE_BASE="https://codeload.github.com"
# shellcheck disable=SC2034
IMEI_PREFIX="${IMEI_PREFIX:-/opt/imei}"
# shellcheck disable=SC2034
IMEI_MAINTAINER="Sascha Greuel <hello@1-2.dev>"
# shellcheck disable=SC2034
IMEI_HOMEPAGE="https://github.com/SoftCreatR/imei"
IMEI_SOURCE_CACHE_DIR="${IMEI_SOURCE_CACHE_DIR:-}"
IMEI_IMAGEMAGICK_BRAND="ImageMagick (IMEI - https://github.com/SoftCreatR/imei)"

# Abort the current script with a consistent error prefix.
die() {
  echo "Error: $*" >&2
  exit 1
}

# Run a command quietly on success but dump its captured output on failure so
# CI logs stay concise without hiding the real error.
run_logged_command() {
  local label="$1"
  shift
  local log_path

  log_path="$(mktemp)"
  if "$@" >"$log_path" 2>&1; then
    rm -f "$log_path"
    return 0
  fi

  echo "$label failed:" >&2
  cat "$log_path" >&2
  rm -f "$log_path"
  return 1
}

# Test whether one command is available in PATH.
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# Require a set of commands up front so failures happen early and clearly.
require_commands() {
  local missing=()
  local cmd

  for cmd in "$@"; do
    if ! command_exists "$cmd"; then
      missing+=("$cmd")
    fi
  done

  if ((${#missing[@]} > 0)); then
    die "Missing required command(s): ${missing[*]}"
  fi
}

# Download a file with the default retry policy used across IMEI scripts.
fetch_file() {
  local url="$1"
  local output="$2"

  curl -fsSL --retry 3 --retry-delay 1 "$url" -o "$output"
}

# Download a reusable source/dependency archive with an optional shared cache.
cacheable_fetch_file() {
  local url="$1"
  local output="$2"
  local cache_key=""
  local cache_path=""

  if [[ -n "$IMEI_SOURCE_CACHE_DIR" ]]; then
    mkdir -p "$IMEI_SOURCE_CACHE_DIR"
    chmod 755 "$IMEI_SOURCE_CACHE_DIR"
    cache_key="$(printf '%s' "$url" | sha1sum | awk '{print $1}')"
    cache_path="$IMEI_SOURCE_CACHE_DIR/$cache_key"
    if [[ -f "$cache_path" ]]; then
      cp -f "$cache_path" "$output"
      return 0
    fi
  fi

  fetch_file "$url" "$output"

  if [[ -n "$cache_path" ]]; then
    cp -f "$output" "$cache_path"
    chmod 644 "$cache_path"
  fi
}

# Read a tracked component version from versions/.
read_version_file() {
  local name="$1"
  tr -d '\n' <"$VERSIONS_DIR/$name.version"
}

# Read a tracked component hash from versions/.
read_hash_file() {
  local name="$1"
  tr -d '\n' <"$VERSIONS_DIR/$name.hash"
}

# Test whether a header exists in the system include paths or the active IMEI
# prefix, when one is in use.
header_exists() {
  local header_path="$1"

  [[ -f "/usr/include/$header_path" ]] && return 0
  [[ -f "/usr/local/include/$header_path" ]] && return 0
  [[ -n "${IMEI_PREFIX:-}" && -f "$IMEI_PREFIX/include/$header_path" ]] && return 0
  return 1
}

# Test whether a pkg-config module is currently resolvable.
pkgconfig_exists() {
  pkg-config --exists "$1" >/dev/null 2>&1
}

# Test whether a CMake package config file is available in the common system or
# IMEI prefix search paths.
cmake_package_exists() {
  local package_name="$1"
  local search_root
  local candidate
  local search_roots=()

  search_roots+=(/usr /usr/local)
  if [[ -n "${IMEI_PREFIX:-}" ]]; then
    search_roots+=("$IMEI_PREFIX")
  fi

  for search_root in "${search_roots[@]}"; do
    for candidate in \
      "$search_root/lib/cmake/$package_name/${package_name}Config.cmake" \
      "$search_root/lib/cmake/$package_name/${package_name}-config.cmake" \
      "$search_root/lib64/cmake/$package_name/${package_name}Config.cmake" \
      "$search_root/lib64/cmake/$package_name/${package_name}-config.cmake" \
      "$search_root/lib/x86_64-linux-gnu/cmake/$package_name/${package_name}Config.cmake" \
      "$search_root/lib/x86_64-linux-gnu/cmake/$package_name/${package_name}-config.cmake"; do
      [[ -f "$candidate" ]] && return 0
    done
  done

  return 1
}

# Read one pinned third-party dependency revision from a local libjxl deps.sh.
read_libjxl_dep_revision_from_file() {
  local deps_file="$1"
  local variable_name="$2"
  local revision

  revision="$(
    awk -F'"' -v variable_name="$variable_name" '
      $1 == variable_name "=" { print $2; exit }
    ' "$deps_file"
  )"
  [[ -n "$revision" ]] || die "Unable to determine $variable_name from $deps_file"
  printf '%s\n' "$revision"
}

# Read the download_github project/source entry for one dependency from a local
# libjxl deps.sh, preserving the exact upstream mapping.
read_libjxl_dep_project_from_file() {
  local deps_file="$1"
  local dep_path="$2"
  local project

  project="$(
    sed ':join; /\\$/ { N; s/\\\n[[:space:]]*/ /; b join; }' "$deps_file" \
      | awk -v dep_path="$dep_path" '
          $1 == "download_github" && $2 == dep_path {
            project = $3
            gsub(/^"/, "", project)
            gsub(/"$/, "", project)
            print project
            exit
          }
        '
  )"
  [[ -n "$project" ]] || die "Unable to determine download_github source for $dep_path from $deps_file"
  printf '%s\n' "$project"
}

# Download one selected libjxl third_party dependency into an extracted source
# tree, following the exact revision and source mapping from libjxl's deps.sh.
download_libjxl_third_party_dep() {
  local deps_file="$1"
  local source_dir="$2"
  local dep_path="$3"
  local variable_name
  local revision
  local project
  local archive_url
  local archive_path
  local target_dir
  local strip_components=1

  variable_name="$(printf '%s' "$dep_path" | tr '[:lower:]/-' '[:upper:]__')"
  revision="$(read_libjxl_dep_revision_from_file "$deps_file" "$variable_name")"
  project="$(read_libjxl_dep_project_from_file "$deps_file" "$dep_path")"
  archive_path="$(mktemp)"
  target_dir="$source_dir/$dep_path"

  if [[ "$project" == http* ]]; then
    archive_url="${project}${revision}.tar.gz"
    strip_components=0
  else
    archive_url="https://github.com/${project}/tarball/${revision}"
  fi

  rm -rf "$target_dir"
  mkdir -p "$target_dir"
  cacheable_fetch_file "$archive_url" "$archive_path"
  tar -zxf "$archive_path" -C "$target_dir" --strip-components="$strip_components"
  rm -f "$archive_path"
}

libjxl_dep_path() {
  case "$1" in
  brotli) echo "third_party/brotli" ;;
  highway) echo "third_party/highway" ;;
  skcms) echo "third_party/skcms" ;;
  sjpeg) echo "third_party/sjpeg" ;;
  zlib) echo "third_party/zlib" ;;
  libpng) echo "third_party/libpng" ;;
  libjpeg-turbo) echo "third_party/libjpeg-turbo" ;;
  *) die "Unsupported libjxl third-party dependency: $1" ;;
  esac
}

libjxl_dep_is_available() {
  case "$1" in
  brotli)
    (pkgconfig_exists libbrotlidec && pkgconfig_exists libbrotlienc && pkgconfig_exists libbrotlicommon) || header_exists "brotli/decode.h"
    ;;
  highway)
    return 1
    ;;
  skcms)
    header_exists "skcms.h"
    ;;
  sjpeg)
    header_exists "sjpeg.h"
    ;;
  zlib)
    pkgconfig_exists zlib || header_exists "zlib.h"
    ;;
  libpng)
    pkgconfig_exists libpng || pkgconfig_exists libpng16 || header_exists "png.h"
    ;;
  libjpeg-turbo)
    pkgconfig_exists libjpeg || pkgconfig_exists libturbojpeg || header_exists "jpeglib.h"
    ;;
  *)
    return 1
    ;;
  esac
}

libjxl_dep_is_vendored() {
  local source_dir="$1"
  local dep_name="$2"
  local dep_path

  dep_path="$(libjxl_dep_path "$dep_name")"
  [[ -d "$source_dir/$dep_path" ]]
}

# Populate only the selected libjxl third_party dependencies from the extracted
# upstream deps.sh, and only when the system/prefix does not already provide them.
populate_libjxl_third_party_deps() {
  local source_dir="$1"
  shift
  local deps_file="$source_dir/deps.sh"
  local dep_name
  local dep_path

  [[ -f "$deps_file" ]] || die "libjxl source tree is missing deps.sh: $source_dir"

  for dep_name in "$@"; do
    if libjxl_dep_is_available "$dep_name"; then
      continue
    fi

    dep_path="$(libjxl_dep_path "$dep_name")"
    download_libjxl_third_party_dep "$deps_file" "$source_dir" "$dep_path"
  done
}

# Make a string safe for Debian version and package naming contexts.
sanitize_version() {
  local value="$1"
  printf '%s\n' "${value//[^0-9A-Za-z.+:~-]/}"
}

# Convert an upstream version into the Debian-friendly variant IMEI uses.
deb_version_from_upstream() {
  local value="$1"
  printf '%s\n' "${value//-/.}"
}

# Build the synthetic release tag from the tracked component versions.
stack_release_tag() {
  printf 'im-%s_aom-%s_heif-%s_jxl-%s\n' \
    "$(read_version_file imagemagick)" \
    "$(read_version_file aom)" \
    "$(read_version_file libheif)" \
    "$(read_version_file libjxl)"
}

# Patch the generated ImageMagick version header so the runtime version string
# clearly identifies IMEI builds while preserving the upstream version number.
patch_imagemagick_version_branding() {
  local source_dir="$1"
  local version_header="$source_dir/MagickCore/version.h"

  [[ -f "$version_header" ]] || die "Missing ImageMagick version header: $version_header"

  sed -i \
    "s|^#define MagickPackageName \".*\"$|#define MagickPackageName \"$IMEI_IMAGEMAGICK_BRAND\"|" \
    "$version_header"
}

# Patch libheif sources for older GCC releases that reject the defaulted
# comparison operators used in nclx_profile.
patch_libheif_source_compatibility() {
  local source_dir="$1"
  local nclx_header="$source_dir/libheif/nclx.h"

  [[ -f "$nclx_header" ]] || die "Missing libheif compatibility header: $nclx_header"

  if ! grep -q 'bool operator==(const nclx_profile& b) const = default;' "$nclx_header"; then
    return 0
  fi

  perl -0pi -e '
    s@  bool operator==\(const nclx_profile& b\) const = default;\n\n  bool operator!=\(const nclx_profile& b\) const = default;@  bool operator==(const nclx_profile& b) const {\n    return m_colour_primaries == b.m_colour_primaries &&\n           m_transfer_characteristics == b.m_transfer_characteristics &&\n           m_matrix_coefficients == b.m_matrix_coefficients &&\n           m_full_range_flag == b.m_full_range_flag;\n  }\n\n  bool operator!=(const nclx_profile& b) const {\n    return !(*this == b);\n  }@s
  ' "$nclx_header"
}

# Copy staged/installed runtime libraries into the canonical IMEI libdir when
# an upstream build system chooses another libdir such as lib64 or a
# multiarch-specific subdirectory.
normalize_runtime_library_locations() {
  local search_root="$1"
  local target_lib_dir="$2"
  shift 2
  local pattern
  local candidate

  mkdir -p "$target_lib_dir"

  for pattern in "$@"; do
    while IFS= read -r -d '' candidate; do
      [[ "$(dirname "$candidate")" == "$target_lib_dir" ]] && continue
      cp -a "$candidate" "$target_lib_dir/"
    done < <(find "$search_root" \( -type f -o -type l \) -name "$pattern" -print0 2>/dev/null)
  done
}

# Ensure the canonical IMEI libdir contains all required runtime libraries
# after an install step.
require_runtime_libraries() {
  local target_lib_dir="$1"
  shift
  local pattern

  for pattern in "$@"; do
    if ! find "$target_lib_dir" \( -type f -o -type l \) -name "$pattern" -print -quit 2>/dev/null | grep -q .; then
      die "Missing required runtime library in $target_lib_dir: $pattern"
    fi
  done
}

# Collapse a target label to its distro family.
target_os_family() {
  case "$1" in
  debian*) echo "debian" ;;
  ubuntu*) echo "ubuntu" ;;
  *) die "Unsupported target: $1" ;;
  esac
}

# Human-readable name for a supported release target.
target_label() {
  case "$1" in
  debian11) echo "Debian 11 (Bullseye)" ;;
  debian12) echo "Debian 12 (Bookworm)" ;;
  debian13) echo "Debian 13 (Trixie)" ;;
  ubuntu20.04) echo "Ubuntu 20.04 (Focal Fossa)" ;;
  ubuntu22.04) echo "Ubuntu 22.04 (Jammy Jellyfish)" ;;
  ubuntu22.10) echo "Ubuntu 22.10 (Kinetic Kudu)" ;;
  ubuntu23.04) echo "Ubuntu 23.04 (Lunar Lobster)" ;;
  ubuntu23.10) echo "Ubuntu 23.10 (Mantic Minotaur)" ;;
  ubuntu24.04) echo "Ubuntu 24.04 (Noble Numbat)" ;;
  ubuntu24.10) echo "Ubuntu 24.10 (Oracular Oriole)" ;;
  ubuntu25.04) echo "Ubuntu 25.04 (Plucky Puffin)" ;;
  ubuntu25.10) echo "Ubuntu 25.10 (Questing Quokka)" ;;
  ubuntu26.04) echo "Ubuntu 26.04 (Resolute Raccoon)" ;;
  *) die "Unsupported target: $1" ;;
  esac
}

# Container base image used by CI for a supported release target.
target_container_image() {
  case "$1" in
  debian11) echo "debian:11" ;;
  debian12) echo "debian:12" ;;
  debian13) echo "debian:13" ;;
  ubuntu20.04) echo "ubuntu:20.04" ;;
  ubuntu22.04) echo "ubuntu:22.04" ;;
  ubuntu22.10) echo "ubuntu:22.10" ;;
  ubuntu23.04) echo "ubuntu:23.04" ;;
  ubuntu23.10) echo "ubuntu:23.10" ;;
  ubuntu24.04) echo "ubuntu:24.04" ;;
  ubuntu24.10) echo "ubuntu:24.10" ;;
  ubuntu25.04) echo "ubuntu:25.04" ;;
  ubuntu25.10) echo "ubuntu:25.10" ;;
  ubuntu26.04) echo "ubuntu:26.04" ;;
  *) die "Unsupported target: $1" ;;
  esac
}

# Return success when the architecture has published prebuilt package support.
prebuilt_arch_is_supported() {
  case "$1" in
  amd64 | arm64) return 0 ;;
  *) return 1 ;;
  esac
}

# Return success when the target/architecture tuple has published prebuilt package support.
target_is_prebuilt_supported() {
  local target="$1"
  local arch="${2:-amd64}"

  if ! prebuilt_arch_is_supported "$arch"; then
    return 1
  fi

  case "$target" in
  debian11 | debian12 | debian13 | ubuntu20.04 | ubuntu22.04 | ubuntu24.04 | ubuntu26.04) return 0 ;;
  *) return 1 ;;
  esac
}

# Normalize arbitrary target fragments into env-var-safe slugs.
target_slug() {
  printf '%s\n' "${1//[^0-9A-Za-z]/_}"
}

# Build the manifest variable stem for one target/architecture tuple.
manifest_target_var() {
  local target="$1"
  local arch="$2"
  printf '%s\n' "$(printf '%s_%s' "$(target_slug "$target")" "$(target_slug "$arch")" | tr '[:lower:]' '[:upper:]')"
}

# Detect the current system as one of IMEI's Debian/Ubuntu target identifiers.
detect_local_target() {
  if [[ ! -r /etc/os-release ]]; then
    die "Unable to detect operating system. /etc/os-release is missing."
  fi

  # shellcheck disable=SC1091
  . /etc/os-release

  case "${ID:-}" in
  debian)
    printf 'debian%s\n' "${VERSION_ID:-unknown}"
    ;;
  ubuntu)
    printf 'ubuntu%s\n' "${VERSION_ID:-unknown}"
    ;;
  *)
    die "Unsupported operating system: ${PRETTY_NAME:-${ID:-unknown}}"
    ;;
  esac
}

# Download and verify one upstream source archive against the tracked SHA1.
download_source_archive() {
  local component="$1"
  local url="$2"
  local sha1="$3"
  local destination="$4"

  mkdir -p "$(dirname "$destination")"
  cacheable_fetch_file "$url" "$destination"

  if [[ -n "$sha1" ]]; then
    local actual
    actual="$(sha1sum "$destination" | awk '{print $1}')"
    if [[ "$actual" != "$sha1" ]]; then
      die "SHA1 mismatch for $component: expected $sha1, got $actual"
    fi
  fi
}

# Filter empty lines from stdin.
strip_empty_lines() {
  sed '/^[[:space:]]*$/d'
}

# Join all remaining arguments with the given delimiter.
join_by() {
  local delimiter="$1"
  shift
  local first=1
  local item

  for item in "$@"; do
    if ((first)); then
      printf '%s' "$item"
      first=0
    else
      printf '%s%s' "$delimiter" "$item"
    fi
  done
}

# Flatten control-file values to a single line for dpkg metadata.
escape_control_value() {
  printf '%s' "$1" | tr '\n' ' '
}

# Print focused runtime diagnostics for ImageMagick module-loading failures.
dump_imagemagick_runtime_diagnostics() {
  local magick_cmd="$1"
  local format_name="$2"
  local module_name
  local module_path
  local module_exists

  echo "ImageMagick version output:" >&2
  "$magick_cmd" -version >&2 || true

  echo "ImageMagick configure summary:" >&2
  "$magick_cmd" -list configure 2>/dev/null \
    | grep -E '^(CODER_PATH|CONFIGURE_PATH|DELEGATES|FEATURES|LIB_VERSION_NUMBER|MODULES_PATH|SHARE_PATH)[[:space:]]' >&2 || true

  case "$format_name" in
  HEIC)
    for module_name in heic jxl; do
      module_path="$(find "$IMEI_PREFIX/lib" -path "*/modules-*/coders/${module_name}.so" -print -quit 2>/dev/null || true)"
      if [[ -n "$module_path" ]]; then
        echo "ImageMagick coder module: $module_path" >&2
        if command_exists ldd; then
          echo "ldd for $module_path:" >&2
          ldd "$module_path" >&2 || true
        fi
        if command_exists readelf; then
          echo "readelf -d for $module_path:" >&2
          readelf -d "$module_path" >&2 || true
        fi
      fi
    done

    for module_name in libheif.so libheif.so.* libaom.so libaom.so.*; do
      module_path="$(find "$IMEI_PREFIX/lib" -maxdepth 1 -name "$module_name" -print -quit 2>/dev/null || true)"
      if [[ -n "$module_path" ]]; then
        echo "Runtime library: $module_path" >&2
        if command_exists ldd; then
          echo "ldd for $module_path:" >&2
          ldd "$module_path" >&2 || true
        fi
        if command_exists readelf; then
          echo "readelf -d for $module_path:" >&2
          readelf -d "$module_path" >&2 || true
        fi
      fi
    done
    ;;
  JXL)
    module_exists="no"
    for module_name in jxl heic; do
      module_path="$(find "$IMEI_PREFIX/lib" -path "*/modules-*/coders/${module_name}.so" -print -quit 2>/dev/null || true)"
      if [[ -n "$module_path" ]]; then
        if [[ "$module_name" == "jxl" ]]; then
          module_exists="yes"
        fi
        echo "ImageMagick coder module: $module_path" >&2
        if command_exists ldd; then
          echo "ldd for $module_path:" >&2
          ldd "$module_path" >&2 || true
        fi
        if command_exists readelf; then
          echo "readelf -d for $module_path:" >&2
          readelf -d "$module_path" >&2 || true
        fi
      fi
    done

    if [[ "$module_exists" != "yes" ]]; then
      echo "ImageMagick coder module jxl.so is missing under $IMEI_PREFIX/lib." >&2
    fi

    for module_name in libjxl.so libjxl.so.* libjxl_threads.so libjxl_threads.so.*; do
      module_path="$(find "$IMEI_PREFIX/lib" -maxdepth 1 -name "$module_name" -print -quit 2>/dev/null || true)"
      if [[ -n "$module_path" ]]; then
        echo "Runtime library: $module_path" >&2
        if command_exists ldd; then
          echo "ldd for $module_path:" >&2
          ldd "$module_path" >&2 || true
        fi
        if command_exists readelf; then
          echo "readelf -d for $module_path:" >&2
          readelf -d "$module_path" >&2 || true
        fi
      fi
    done
    ;;
  esac
}

# Smoke-test an installed ImageMagick runtime by verifying the core commands
# start successfully and expected formats/delegates are exposed through
# `magick -list format` or `magick -version`.
smoke_test_imagemagick_installation() {
  local magick_cmd="$1"
  local identify_cmd="$2"
  shift 2
  local expected_formats=("$@")
  local formats_output
  local version_output
  local format_name
  local pattern
  local verified_formats=()

  if [[ ! -x "$magick_cmd" ]]; then
    die "ImageMagick smoke test failed: missing executable $magick_cmd"
  fi

  if [[ ! -x "$identify_cmd" ]]; then
    die "ImageMagick smoke test failed: missing executable $identify_cmd"
  fi

  version_output="$(mktemp)"
  formats_output="$(mktemp)"
  "$magick_cmd" -version >"$version_output"
  "$identify_cmd" -version >/dev/null

  if ((${#expected_formats[@]} == 0)); then
    rm -f "$version_output" "$formats_output"
    return 0
  fi

  "$magick_cmd" -list format >"$formats_output"

  for format_name in "${expected_formats[@]}"; do
    pattern="^[[:space:]]*${format_name}\\*?[[:space:]]"
    case "$format_name" in
    HEIC)
      pattern="^[[:space:]]*(AVIF|HEIC|HEIF)\\*?[[:space:]]"
      ;;
    esac

    if ! grep -Eq "$pattern" "$formats_output"; then
      echo "ImageMagick format list:" >&2
      cat "$formats_output" >&2
      dump_imagemagick_runtime_diagnostics "$magick_cmd" "$format_name"
      rm -f "$version_output" "$formats_output"
      die "ImageMagick smoke test failed: expected format '$format_name' is unavailable."
    fi

    verified_formats+=("$format_name")
  done

  printf 'ImageMagick smoke test passed: %s\n' "$(join_by ', ' "${verified_formats[@]}")"
  rm -f "$version_output" "$formats_output"
}
