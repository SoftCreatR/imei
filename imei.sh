#!/usr/bin/env bash

#
# IMEI installer entry point.
# - Installs signed pre-built release packages when a matching release target exists.
# - Falls back to local .deb package builds for older systems or custom build options.
# - Verifies both the installer signature and release metadata signatures by default.
#

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$ROOT_DIR/scripts/common.sh"
# shellcheck disable=SC1091
. "$ROOT_DIR/scripts/delegates.sh"

require_commands curl sha256sum apt-get

ARCH="$(dpkg --print-architecture)"
DOWNLOAD_DIR=""
KEEP_DOWNLOADS="no"
DOWNLOAD_ONLY="no"
FORCE_LOCAL_BUILD="no"
FORCE_PREBUILT="no"
SELF_UPDATE="no"
USER_INSTALL="no"
KEEP_BUILD_DEPS="no"
RELEASE_TAG=""
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-SoftCreatR/imei}"
TARGET_OVERRIDE=""
LOCAL_BUILD_ARGS=()
BUILD_DEPS_SNAPSHOT_PATH=""
SCRIPT_SIGNATURE_PATH="$ROOT_DIR/imei.sh.sig"
SCRIPT_SIGNATURE_KEY_PATH="$ROOT_DIR/imei.sh.sig.key"
KEYRING_DIR="$ROOT_DIR/keys"
LEGACY_PUBLIC_KEY_PATH="$ROOT_DIR/imei.sh.pem"
VERIFY_SIGNATURE="yes"

# Return the GitHub token to use for authenticated private-release downloads.
# GH_TOKEN wins so local overrides do not need to replace Actions defaults.
github_token() {
  if [[ -n "${GH_TOKEN:-}" ]]; then
    printf '%s\n' "$GH_TOKEN"
    return 0
  fi

  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    printf '%s\n' "$GITHUB_TOKEN"
    return 0
  fi

  return 1
}

# Resolve the public key for a signature.
# New signatures use a sidecar key-id file and the in-repo keyring.
# Older signatures can still fall back to the legacy top-level public key.
signature_key_path() {
  local key_id_path="$1"
  local key_id
  local key_path

  if [[ -n "$key_id_path" && -f "$key_id_path" ]]; then
    key_id="$(tr -d '\n' <"$key_id_path")"
    key_path="$KEYRING_DIR/$key_id.pem"
    if [[ -f "$key_path" ]]; then
      printf '%s\n' "$key_path"
      return 0
    fi
    die "Missing public key for key id '$key_id': $key_path"
  fi

  if [[ -f "$LEGACY_PUBLIC_KEY_PATH" ]]; then
    printf '%s\n' "$LEGACY_PUBLIC_KEY_PATH"
    return 0
  fi

  die "No public key available for signature verification."
}

verify_signature() {
  local file_path="$1"
  local signature_path="$2"
  local key_id_path="${3:-}"
  local public_key_path

  require_commands openssl
  public_key_path="$(signature_key_path "$key_id_path")"

  openssl dgst -sha512 -verify "$public_key_path" -signature "$signature_path" "$file_path" >/dev/null
}

# Verify the installer itself before doing any network or package-manager work.
# This is the trust anchor for the local script path; release downloads have their
# own signed metadata verification later in the flow.
verify_self_signature() {
  local script_path

  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

  if [[ "$VERIFY_SIGNATURE" != "yes" ]]; then
    return 0
  fi

  if [[ ! -f "$SCRIPT_SIGNATURE_PATH" ]]; then
    die "Missing installer signature: $SCRIPT_SIGNATURE_PATH"
  fi

  if ! verify_signature "$script_path" "$SCRIPT_SIGNATURE_PATH" "$SCRIPT_SIGNATURE_KEY_PATH"; then
    die "Installer signature verification failed. Use --no-sig-verify only for local development."
  fi
}

usage() {
  cat <<'EOF'
Usage: ./imei.sh [options]

Default behavior:
  1. If you run IMEI on a supported release target without custom build flags,
     it installs the pre-built .deb packages from the latest GitHub release.
  2. If you run it on an older system or pass custom build flags, it falls back
     to building clean .deb packages locally and installs those instead.

Installer options:
  --build-local                     Skip release assets and build .deb packages locally
  --user-install                    Build and install IMEI into a user-owned prefix
  --prebuilt-only                   Fail instead of falling back to a local build
  --download-only                   Download release packages without installing them
  --self-update                     Update IMEI runtime files from a signed release bundle
  --download-dir <dir>              Directory used for downloaded assets
  --keep-downloads                  Keep downloaded release assets after install
  --no-sig-verify                   Skip installer self-signature verification
  --release-tag <tag>               Install packages from a specific release tag
  --github-repository <owner/repo>  Override the GitHub repository used for releases
  --target <target>                 Override detected target (for testing)
  --help                            Show this help text

Local build options:
  --prefix <dir>
  --imagemagick-version <version>
  --aom-version <version>
  --libheif-version <version>
  --jpeg-xl-version <version>
  --imagemagick-quantum-depth <n>
  --imagemagick-opencl
  --imagemagick-build-static
  --imagemagick-with-magick-plus-plus
  --imagemagick-with-perl
  --disable-delegate <name>
  --skip-aom
  --skip-libheif
  --skip-jpeg-xl
  --work-dir <dir>
  --output-dir <dir>
  --no-install
  --keep-build-deps
  --keep-work-dir
EOF
}

# Collect an option that should be forwarded to the local package builder.
append_local_arg() {
  LOCAL_BUILD_ARGS+=("$1")
}

# Collect an option/value pair that should be forwarded to the local package builder.
append_local_arg_pair() {
  LOCAL_BUILD_ARGS+=("$1" "$2")
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --build-local)
    FORCE_LOCAL_BUILD="yes"
    shift
    ;;
  --user-install)
    USER_INSTALL="yes"
    FORCE_LOCAL_BUILD="yes"
    shift
    ;;
  --prebuilt-only)
    FORCE_PREBUILT="yes"
    shift
    ;;
  --download-only)
    DOWNLOAD_ONLY="yes"
    shift
    ;;
  --self-update)
    SELF_UPDATE="yes"
    shift
    ;;
  --download-dir)
    DOWNLOAD_DIR="$2"
    shift 2
    ;;
  --keep-downloads)
    KEEP_DOWNLOADS="yes"
    shift
    ;;
  --keep-build-deps)
    KEEP_BUILD_DEPS="yes"
    FORCE_LOCAL_BUILD="yes"
    shift
    ;;
  --no-sig-verify | --dev)
    VERIFY_SIGNATURE="no"
    shift
    ;;
  --release-tag)
    RELEASE_TAG="$2"
    shift 2
    ;;
  --github-repository)
    GITHUB_REPOSITORY="$2"
    shift 2
    ;;
  --target)
    TARGET_OVERRIDE="$2"
    shift 2
    ;;
  --help)
    usage
    exit 0
    ;;
  --prefix | --imagemagick-version | --im-version | --aom-version | --libheif-version | --heif-version | --jpeg-xl-version | --jxl-version | --imagemagick-quantum-depth | --im-q | --work-dir | --output-dir)
    append_local_arg_pair "$1" "$2"
    FORCE_LOCAL_BUILD="yes"
    shift 2
    ;;
  --imagemagick-opencl | --im-ocl | --imagemagick-build-static | --im-build-static | --imagemagick-with-magick-plus-plus | --imagemagick-with-perl | --skip-aom | --skip-libheif | --skip-heif | --skip-jpeg-xl | --skip-jxl | --no-install | --keep-work-dir)
    append_local_arg "$1"
    FORCE_LOCAL_BUILD="yes"
    shift
    ;;
  --disable-delegate)
    if ! delegate_is_known "$2"; then
      die "Unknown delegate: $2"
    fi
    append_local_arg_pair "$1" "$(delegate_normalize_name "$2")"
    FORCE_LOCAL_BUILD="yes"
    shift 2
    ;;
  *)
    die "Unknown option: $1"
    ;;
  esac
done

verify_self_signature

if [[ "$USER_INSTALL" == "yes" ]]; then
  if [[ "$FORCE_PREBUILT" == "yes" || "$DOWNLOAD_ONLY" == "yes" ]]; then
    die "--user-install cannot be combined with --prebuilt-only or --download-only."
  fi

  case " ${LOCAL_BUILD_ARGS[*]} " in
  *" --output-dir "* | *" --no-install "*)
    die "--user-install cannot be combined with --output-dir or --no-install."
    ;;
  esac
fi

# Determine the effective IMEI target, optionally honoring a manual override.
detect_target() {
  if [[ -n "$TARGET_OVERRIDE" ]]; then
    printf '%s\n' "$TARGET_OVERRIDE"
  else
    detect_local_target
  fi
}

# Download one release asset, using an auth token when the repository is private.
fetch_release_asset() {
  local base_url="$1"
  local asset_name="$2"
  local output_path="$3"
  local token=""
  local asset_url="$base_url/$asset_name"

  if token="$(github_token)"; then
    if curl -fsSL --retry 3 --retry-delay 1 \
      -H "Authorization: Bearer $token" \
      "$asset_url" \
      -o "$output_path" \
      2>/dev/null; then
      return 0
    fi
  elif fetch_file "$asset_url" "$output_path"; then
    return 0
  fi

  echo "Error: failed to download release asset '$asset_name' from $asset_url" >&2
  return 1
}

# Replace one tracked file atomically so partial self-updates do not leave broken state behind.
replace_file() {
  local source_path="$1"
  local destination_path="$2"
  local mode="${3:-}"
  local temp_path

  mkdir -p "$(dirname "$destination_path")"
  temp_path="$(dirname "$destination_path")/.$(basename "$destination_path").tmp.$$"
  cp "$source_path" "$temp_path"
  if [[ -n "$mode" ]]; then
    chmod "$mode" "$temp_path"
  fi
  mv "$temp_path" "$destination_path"
}

# Load the signed release manifest into the current shell session.
load_release_manifest() {
  local manifest_path="$1"

  # shellcheck disable=SC1090
  . "$manifest_path"
}

# Build the release asset base URL for either the latest release or a fixed tag.
release_download_base() {
  if [[ -n "$RELEASE_TAG" ]]; then
    printf 'https://github.com/%s/releases/download/%s\n' "$GITHUB_REPOSITORY" "$RELEASE_TAG"
  else
    printf 'https://github.com/%s/releases/latest/download\n' "$GITHUB_REPOSITORY"
  fi
}

# Read the package list for one target/architecture tuple from the release manifest.
target_packages_from_manifest() {
  local target="$1"
  local key
  local variable_name

  key="$(manifest_target_var "$target" "$ARCH")"
  variable_name="TARGET_${key}_PACKAGES"
  printf '%s\n' "${!variable_name:-}"
}

# Replace one extracted file in place, preserving the repository layout.
replace_extracted_file() {
  local extracted_root="$1"
  local relative_path="$2"
  local mode="${3:-}"

  replace_file "$extracted_root/$relative_path" "$ROOT_DIR/$relative_path" "$mode"
}

# Replace every file below one extracted directory while leaving unrelated local files intact.
replace_extracted_tree_files() {
  local extracted_root="$1"
  local relative_dir="$2"
  local source_dir="$extracted_root/$relative_dir"
  local source_path
  local relative_path

  [[ -d "$source_dir" ]] || return 0

  while IFS= read -r -d '' source_path; do
    relative_path="${source_path#"$extracted_root"/}"
    replace_file "$source_path" "$ROOT_DIR/$relative_path"
  done < <(find "$source_dir" -type f -print0 | sort -z)
}

# Update the local installer, helper scripts, version metadata, and public keyring
# from a signed release bundle. The bundle must be signed by a key the current
# checkout already trusts.
self_update() {
  local base_url
  local bundle_path
  local bundle_sig_path
  local bundle_sig_key_path
  local bundle_extract_dir
  local signer_key_id
  local signer_key_path

  if [[ ! -w "$ROOT_DIR" ]]; then
    die "The IMEI checkout is not writable: $ROOT_DIR"
  fi

  if [[ -z "$DOWNLOAD_DIR" ]]; then
    DOWNLOAD_DIR="$(mktemp -d)"
  else
    mkdir -p "$DOWNLOAD_DIR"
  fi

  base_url="$(release_download_base)"
  bundle_path="$DOWNLOAD_DIR/imei-update.tar.gz"
  bundle_sig_path="$DOWNLOAD_DIR/imei-update.tar.gz.sig"
  bundle_sig_key_path="$DOWNLOAD_DIR/imei-update.tar.gz.sig.key"
  bundle_extract_dir="$DOWNLOAD_DIR/imei-update"

  fetch_release_asset "$base_url" "imei-update.tar.gz" "$bundle_path"
  fetch_release_asset "$base_url" "imei-update.tar.gz.sig" "$bundle_sig_path"
  fetch_release_asset "$base_url" "imei-update.tar.gz.sig.key" "$bundle_sig_key_path"

  signer_key_id="$(tr -d '\n' <"$bundle_sig_key_path")"
  signer_key_path="$KEYRING_DIR/$signer_key_id.pem"
  if [[ ! -f "$signer_key_path" ]]; then
    die "Downloaded update bundle uses unknown key id '$signer_key_id'. Update the local keyring manually before using --self-update."
  fi

  if ! verify_signature "$bundle_path" "$bundle_sig_path" "$bundle_sig_key_path"; then
    die "Downloaded update bundle signature verification failed."
  fi

  rm -rf "$bundle_extract_dir"
  mkdir -p "$bundle_extract_dir"
  tar -xzf "$bundle_path" -C "$bundle_extract_dir"

  [[ -f "$bundle_extract_dir/imei.sh" ]] || die "Update bundle is missing imei.sh"
  [[ -d "$bundle_extract_dir/scripts" ]] || die "Update bundle is missing scripts/"

  replace_extracted_file "$bundle_extract_dir" "imei.sh" 0755
  replace_extracted_file "$bundle_extract_dir" "imei.sh.sig" 0644
  replace_extracted_file "$bundle_extract_dir" "imei.sh.sig.key" 0644
  replace_extracted_file "$bundle_extract_dir" "imei.sh.pem" 0644
  replace_extracted_file "$bundle_extract_dir" "update_version_info.sh" 0755
  replace_extracted_file "$bundle_extract_dir" "README.md" 0644
  replace_extracted_file "$bundle_extract_dir" "LICENSE.md" 0644
  replace_extracted_tree_files "$bundle_extract_dir" "scripts"
  replace_extracted_tree_files "$bundle_extract_dir" "versions"
  replace_extracted_tree_files "$bundle_extract_dir" "keys"

  printf 'Updated IMEI runtime from %s%s\n' "$GITHUB_REPOSITORY" "${RELEASE_TAG:+ ($RELEASE_TAG)}"
}

# Download, verify, and optionally install the prebuilt package set for one target.
# The manifest and checksum file must both pass signature verification first.
install_prebuilt_packages() {
  local target="$1"
  local base_url
  local manifest_path
  local manifest_sig_path
  local manifest_sig_key_path
  local checksums_path
  local checksums_sig_path
  local checksums_sig_key_path
  local packages_line
  local package_name
  local package_list=()

  if [[ "$(id -u)" -ne 0 && "$DOWNLOAD_ONLY" != "yes" ]]; then
    die "Root privileges are required to install .deb packages."
  fi

  if [[ -z "$DOWNLOAD_DIR" ]]; then
    DOWNLOAD_DIR="$(mktemp -d)"
  else
    mkdir -p "$DOWNLOAD_DIR"
  fi

  base_url="$(release_download_base)"
  manifest_path="$DOWNLOAD_DIR/release-manifest.env"
  manifest_sig_path="$DOWNLOAD_DIR/release-manifest.env.sig"
  manifest_sig_key_path="$DOWNLOAD_DIR/release-manifest.env.sig.key"
  checksums_path="$DOWNLOAD_DIR/SHA256SUMS"
  checksums_sig_path="$DOWNLOAD_DIR/SHA256SUMS.sig"
  checksums_sig_key_path="$DOWNLOAD_DIR/SHA256SUMS.sig.key"

  if ! fetch_release_asset "$base_url" "release-manifest.env" "$manifest_path" 2>/dev/null; then
    return 1
  fi
  fetch_release_asset "$base_url" "release-manifest.env.sig" "$manifest_sig_path"
  fetch_release_asset "$base_url" "release-manifest.env.sig.key" "$manifest_sig_key_path"
  verify_signature "$manifest_path" "$manifest_sig_path" "$manifest_sig_key_path"
  load_release_manifest "$manifest_path"

  packages_line="$(target_packages_from_manifest "$target")"
  if [[ -z "$packages_line" ]]; then
    return 1
  fi

  read -r -a package_list <<<"$packages_line"

  fetch_release_asset "$base_url" "SHA256SUMS" "$checksums_path"
  fetch_release_asset "$base_url" "SHA256SUMS.sig" "$checksums_sig_path"
  fetch_release_asset "$base_url" "SHA256SUMS.sig.key" "$checksums_sig_key_path"
  verify_signature "$checksums_path" "$checksums_sig_path" "$checksums_sig_key_path"

  for package_name in "${package_list[@]}"; do
    fetch_release_asset "$base_url" "$package_name" "$DOWNLOAD_DIR/$package_name"
  done

  (
    cd "$DOWNLOAD_DIR"
    sha256sum --check --ignore-missing SHA256SUMS >/dev/null
  )

  if [[ "$DOWNLOAD_ONLY" == "yes" ]]; then
    printf 'Downloaded packages to %s\n' "$DOWNLOAD_DIR"
    KEEP_DOWNLOADS="yes"
    return 0
  fi

  apt-get update -qq
  apt-get install -y "${package_list[@]/#/$DOWNLOAD_DIR/}" >/dev/null
  smoke_test_imagemagick_installation "/usr/bin/magick" "/usr/bin/identify" "JPEG" "HEIC" "JXL"
}

# Install build dependencies and delegate the actual package build to the helper scripts.
run_local_build() {
  if [[ "$USER_INSTALL" == "yes" ]]; then
    bash "$ROOT_DIR/scripts/build-user-install.sh" "${LOCAL_BUILD_ARGS[@]}"
    return 0
  fi

  if [[ "$(id -u)" -ne 0 ]]; then
    die "Root privileges are required for local package builds."
  fi

  bash "$ROOT_DIR/scripts/install-build-deps.sh" "${LOCAL_BUILD_ARGS[@]}"
  bash "$ROOT_DIR/scripts/build-packages.sh" "${LOCAL_BUILD_ARGS[@]}"
}

# Record the manual-package baseline before IMEI installs build dependencies so
# we can later mark only IMEI-added build packages as auto and autoremove them.
snapshot_manual_packages() {
  local output_path="$1"
  apt-mark showmanual | sort -u >"$output_path"
}

prepare_build_dependency_cleanup() {
  if [[ "$USER_INSTALL" == "yes" || "$KEEP_BUILD_DEPS" == "yes" ]]; then
    return 0
  fi

  BUILD_DEPS_SNAPSHOT_PATH="$(mktemp)"
  snapshot_manual_packages "$BUILD_DEPS_SNAPSHOT_PATH"
}

cleanup_build_dependencies() {
  local after_path
  local package_name
  local added_manual_packages=()

  if [[ "$USER_INSTALL" == "yes" || "$KEEP_BUILD_DEPS" == "yes" || -z "$BUILD_DEPS_SNAPSHOT_PATH" || ! -f "$BUILD_DEPS_SNAPSHOT_PATH" ]]; then
    return 0
  fi

  after_path="$(mktemp)"
  snapshot_manual_packages "$after_path"

  while IFS= read -r package_name; do
    [[ -n "$package_name" ]] || continue
    case "$package_name" in
    imei-*) continue ;;
    esac
    added_manual_packages+=("$package_name")
  done < <(comm -13 "$BUILD_DEPS_SNAPSHOT_PATH" "$after_path")

  rm -f "$after_path"

  if ((${#added_manual_packages[@]} == 0)); then
    return 0
  fi

  printf 'Removing temporary build dependencies installed by IMEI.\n'
  apt-mark auto "${added_manual_packages[@]}" >/dev/null
  apt-get autoremove -y --purge >/dev/null
}

# Remove temporary release downloads unless the caller asked to keep them.
cleanup_downloads() {
  if [[ "$KEEP_DOWNLOADS" != "yes" && -n "$DOWNLOAD_DIR" && -d "$DOWNLOAD_DIR" ]]; then
    rm -rf "$DOWNLOAD_DIR"
  fi

  if [[ -n "$BUILD_DEPS_SNAPSHOT_PATH" && -f "$BUILD_DEPS_SNAPSHOT_PATH" ]]; then
    rm -f "$BUILD_DEPS_SNAPSHOT_PATH"
  fi
}

trap cleanup_downloads EXIT

TARGET="$(detect_target)"

if ! target_is_prebuilt_supported "$TARGET" "$ARCH"; then
  if [[ "$FORCE_PREBUILT" == "yes" ]]; then
    die "No pre-built release assets are available for $TARGET ($ARCH)."
  fi
  FORCE_LOCAL_BUILD="yes"
fi

if [[ "$SELF_UPDATE" == "yes" ]]; then
  self_update
  exit 0
fi

if [[ "$DOWNLOAD_ONLY" == "yes" ]]; then
  FORCE_PREBUILT="yes"
fi

if [[ "$FORCE_LOCAL_BUILD" != "yes" ]]; then
  if install_prebuilt_packages "$TARGET"; then
    cat <<EOF
Installed pre-built IMEI packages for $TARGET.
Repository: $GITHUB_REPOSITORY
EOF
    exit 0
  fi

  if [[ "$FORCE_PREBUILT" == "yes" ]]; then
    die "No pre-built release assets are available for $TARGET ($ARCH)."
  fi
fi

append_local_arg_pair "--target" "$TARGET"
if [[ "$DOWNLOAD_ONLY" == "yes" ]]; then
  append_local_arg "--no-install"
fi
prepare_build_dependency_cleanup
run_local_build
cleanup_build_dependencies

if [[ "$USER_INSTALL" == "yes" ]]; then
  exit 0
fi

cat <<EOF
Built IMEI packages locally for $TARGET.
Packages were generated by scripts/build-packages.sh and can be removed with apt/dpkg.
EOF
