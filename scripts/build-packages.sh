#!/usr/bin/env bash

#
# Build the IMEI .deb package set for the current or requested Debian/Ubuntu target.
# This script is used both locally and in CI, and it always stages package contents
# first so installation/removal stays under dpkg control instead of make install.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/delegates.sh"

TARGET="$(detect_local_target)"
ARCH="$(dpkg --print-architecture)"
OUTPUT_DIR=""
WORK_DIR="/tmp/imei-build"
INSTALL_PACKAGES="yes"
KEEP_WORKDIR="no"
SKIP_AOM="no"
SKIP_LIBHEIF="no"
SKIP_JXL="no"
ENABLE_OPENCL="no"
BUILD_STATIC="no"
ENABLE_MAGICK_PLUS_PLUS="no"
ENABLE_PERL="no"
QUANTUM_DEPTH="16"
IMAGEMAGICK_VERSION="$(read_version_file imagemagick)"
AOM_VERSION="$(read_version_file aom)"
LIBHEIF_VERSION="$(read_version_file libheif)"
LIBJXL_VERSION="$(read_version_file libjxl)"
AOM_HASH="$(read_hash_file aom)"
LIBHEIF_HASH="$(read_hash_file libheif)"
LIBJXL_HASH="$(read_hash_file libjxl)"
IMAGEMAGICK_HASH="$(read_hash_file imagemagick)"
DISABLED_DELEGATES=()
CMAKE_GENERATOR_ARGS=()

usage() {
  cat <<'EOF'
Usage: scripts/build-packages.sh [options]

Options:
  --target <target>                  Override target label (default: detected OS)
  --output-dir <dir>                 Directory for generated .deb files
  --work-dir <dir>                   Build workspace
  --no-install                       Do not install generated packages after build
  --keep-work-dir                    Keep the build workspace after completion
  --skip-aom                         Do not build libaom
  --skip-libheif                     Do not build libheif
  --skip-jpeg-xl                     Do not build libjxl
  --imagemagick-version <version>    Override ImageMagick version
  --aom-version <version>            Override libaom version
  --libheif-version <version>        Override libheif version
  --jpeg-xl-version <version>        Override libjxl version
  --imagemagick-quantum-depth <n>    ImageMagick quantum depth (8, 16, 32)
  --imagemagick-opencl               Enable OpenCL in ImageMagick
  --imagemagick-build-static         Build ImageMagick static instead of shared
  --imagemagick-with-magick-plus-plus
                                     Build the Magick++ C++ interface
  --imagemagick-with-perl            Build PerlMagick
  --disable-delegate <name>          Disable a specific ImageMagick delegate
  --help                             Show this help text
EOF
}

disable_delegate() {
  local delegate_name

  delegate_name="$(delegate_normalize_name "$1")"
  if ! delegate_is_known "$delegate_name"; then
    die "Unknown delegate: $1"
  fi

  DISABLED_DELEGATES+=("$delegate_name")
}

delegate_is_disabled() {
  local delegate_name

  delegate_name="$(delegate_normalize_name "$1")"
  case " ${DISABLED_DELEGATES[*]:-} " in
  *" $delegate_name "*) return 0 ;;
  *) return 1 ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --target)
    TARGET="$2"
    shift 2
    ;;
  --output-dir)
    OUTPUT_DIR="$2"
    shift 2
    ;;
  --work-dir)
    WORK_DIR="$2"
    shift 2
    ;;
  --no-install)
    INSTALL_PACKAGES="no"
    shift
    ;;
  --keep-work-dir)
    KEEP_WORKDIR="yes"
    shift
    ;;
  --skip-aom)
    SKIP_AOM="yes"
    shift
    ;;
  --skip-libheif | --skip-heif)
    SKIP_LIBHEIF="yes"
    shift
    ;;
  --skip-jpeg-xl | --skip-jxl)
    SKIP_JXL="yes"
    shift
    ;;
  --imagemagick-version | --im-version)
    IMAGEMAGICK_VERSION="$2"
    shift 2
    ;;
  --aom-version)
    AOM_VERSION="$2"
    shift 2
    ;;
  --libheif-version | --heif-version)
    LIBHEIF_VERSION="$2"
    shift 2
    ;;
  --jpeg-xl-version | --jxl-version)
    LIBJXL_VERSION="$2"
    shift 2
    ;;
  --imagemagick-quantum-depth | --im-q)
    QUANTUM_DEPTH="$2"
    shift 2
    ;;
  --imagemagick-opencl | --im-ocl)
    ENABLE_OPENCL="yes"
    shift
    ;;
  --imagemagick-build-static | --im-build-static)
    BUILD_STATIC="yes"
    shift
    ;;
  --imagemagick-with-magick-plus-plus)
    ENABLE_MAGICK_PLUS_PLUS="yes"
    shift
    ;;
  --imagemagick-with-perl)
    ENABLE_PERL="yes"
    shift
    ;;
  --disable-delegate)
    disable_delegate "$2"
    shift 2
    ;;
  --help)
    usage
    exit 0
    ;;
  *)
    die "Unknown option: $1"
    ;;
  esac
done

require_commands curl sha1sum tar make cmake dpkg-deb dpkg-shlibdeps file sed find xargs

if command_exists ninja; then
  CMAKE_GENERATOR_ARGS=(-G Ninja)
fi

case "$QUANTUM_DEPTH" in
8 | 16 | 32) ;;
*) die "Invalid quantum depth: $QUANTUM_DEPTH" ;;
esac

if [[ "$SKIP_AOM" == "yes" && "$SKIP_LIBHEIF" != "yes" ]]; then
  die "libheif requires libaom in the IMEI package layout. Use --skip-libheif together with --skip-aom."
fi

if delegate_is_disabled heic; then
  SKIP_LIBHEIF="yes"
  SKIP_AOM="yes"
fi

if delegate_is_disabled jxl; then
  SKIP_JXL="yes"
fi

if [[ "$INSTALL_PACKAGES" == "yes" && "$(id -u)" -ne 0 ]]; then
  die "scripts/build-packages.sh must run as root when package installation is enabled."
fi

if [[ -z "$OUTPUT_DIR" ]]; then
  OUTPUT_DIR="$REPO_ROOT/dist/$TARGET"
fi

mkdir -p "$OUTPUT_DIR" "$WORK_DIR"

SOURCE_DIR="$WORK_DIR/sources"
BUILD_ROOT="$WORK_DIR/build"
STAGE_ROOT="$WORK_DIR/stage"
mkdir -p "$SOURCE_DIR" "$BUILD_ROOT" "$STAGE_ROOT"

# Remove the temporary workspace unless the caller asked to inspect it afterward.
cleanup() {
  if [[ "$KEEP_WORKDIR" != "yes" ]]; then
    rm -rf "$WORK_DIR"
  fi
}

trap cleanup EXIT

run_post_install_smoke_tests() {
  local expected_formats=("JPEG")

  if [[ "$SKIP_LIBHEIF" != "yes" ]]; then
    expected_formats+=("HEIC")
  fi

  if [[ "$SKIP_JXL" != "yes" ]]; then
    expected_formats+=("JXL")
  fi

  smoke_test_imagemagick_installation "/usr/bin/magick" "/usr/bin/identify" "${expected_formats[@]}"
}

# Build the final .deb path for one package/version/architecture tuple.
package_output_path() {
  local package_name="$1"
  local deb_version="$2"
  printf '%s/%s_%s_%s.deb\n' "$OUTPUT_DIR" "$package_name" "$deb_version" "$ARCH"
}

# Recreate a directory from scratch.
reset_dir() {
  rm -rf "$1"
  mkdir -p "$1"
}

# Emit null-delimited ELF file paths from the staged package tree.
collect_elf_files() {
  local search_root="$1"
  find "$search_root" -type f -print0 | while IFS= read -r -d '' candidate; do
    if file -b "$candidate" | grep -q '^ELF '; then
      printf '%s\0' "$candidate"
    fi
  done
}

# Generate a DEBIAN/shlibs file from the staged shared libraries in the package.
create_shlibs_file() {
  local stage_dir="$1"
  local package_name="$2"
  local shlibs_path="$stage_dir/DEBIAN/shlibs"
  local entries=()
  local file_path
  local base_name
  local lib_name
  local major

  while IFS= read -r -d '' file_path; do
    base_name="$(basename "$file_path")"
    if [[ "$base_name" =~ ^(lib[^.]+)\.so\.([0-9]+)(\..*)?$ ]]; then
      lib_name="${BASH_REMATCH[1]}"
      major="${BASH_REMATCH[2]}"
      entries+=("$lib_name $major $package_name")
    fi
  done < <(find "$stage_dir" -type f -name 'lib*.so.*' -print0)

  if ((${#entries[@]} == 0)); then
    return
  fi

  printf '%s\n' "${entries[@]}" | sort -u >"$shlibs_path"
}

# Write the Debian control metadata for a staged package tree.
write_control_file() {
  local stage_dir="$1"
  local package_name="$2"
  local deb_version="$3"
  local description="$4"
  local depends="$5"
  local recommends="$6"
  local provides="$7"
  local conflicts="$8"
  local architecture="$9"

  {
    echo "Package: $package_name"
    echo "Version: $deb_version"
    echo "Section: graphics"
    echo "Priority: optional"
    echo "Architecture: $architecture"
    echo "Maintainer: $IMEI_MAINTAINER"
    echo "Homepage: $IMEI_HOMEPAGE"
    if [[ -n "$depends" ]]; then
      echo "Depends: $depends"
    fi
    if [[ -n "$recommends" ]]; then
      echo "Recommends: $recommends"
    fi
    if [[ -n "$provides" ]]; then
      echo "Provides: $provides"
    fi
    if [[ -n "$conflicts" ]]; then
      echo "Conflicts: $conflicts"
      echo "Replaces: $conflicts"
    fi
    echo "Description: $(escape_control_value "$description")"
  } >"$stage_dir/DEBIAN/control"
}

# Ask dpkg-shlibdeps for runtime dependencies based on the staged ELF files.
compute_package_dependencies() {
  local stage_dir="$1"
  local package_name="$2"
  local elf_files=()
  local dep_output
  local dep_line
  local shlibdeps_dir

  while IFS= read -r -d '' file_path; do
    elf_files+=("$file_path")
  done < <(collect_elf_files "$stage_dir")

  if ((${#elf_files[@]} == 0)); then
    return 0
  fi

  shlibdeps_dir="$(mktemp -d)"
  mkdir -p "$shlibdeps_dir/debian"
  cat >"$shlibdeps_dir/debian/control" <<EOF
Source: imei
Section: graphics
Priority: optional
Maintainer: $IMEI_MAINTAINER
Standards-Version: 4.6.0

Package: $package_name
Architecture: $ARCH
Description: temporary control file for dependency generation
EOF

  dep_output="$(
    cd "$shlibdeps_dir"
    dpkg-shlibdeps \
      --ignore-missing-info \
      -O \
      -x"$package_name" \
      -l"$stage_dir$IMEI_PREFIX/lib" \
      -l"$IMEI_PREFIX/lib" \
      "${elf_files[@]}"
  )"
  rm -rf "$shlibdeps_dir"

  dep_line="$(printf '%s\n' "$dep_output" | sed -n 's/^shlibs:Depends=//p' | tail -n1)"
  printf '%s\n' "$dep_line"
}

# Turn a staged install tree into a .deb, combining explicit and auto-detected deps.
build_package_from_stage() {
  local stage_dir="$1"
  local package_name="$2"
  local deb_version="$3"
  local description="$4"
  local extra_depends="$5"
  local recommends="$6"
  local provides="$7"
  local conflicts="$8"
  local output_path="$9"
  local depends
  local combined_depends

  mkdir -p "$stage_dir/DEBIAN"
  create_shlibs_file "$stage_dir" "$package_name"
  write_control_file "$stage_dir" "$package_name" "$deb_version" "$description" "" "$recommends" "$provides" "$conflicts" "$ARCH"

  depends="$(compute_package_dependencies "$stage_dir" "$package_name")"

  if [[ -n "$extra_depends" && -n "$depends" ]]; then
    combined_depends="$extra_depends, $depends"
  elif [[ -n "$extra_depends" ]]; then
    combined_depends="$extra_depends"
  else
    combined_depends="$depends"
  fi

  write_control_file "$stage_dir" "$package_name" "$deb_version" "$description" "$combined_depends" "$recommends" "$provides" "$conflicts" "$ARCH"
  dpkg-deb --build --root-owner-group "$stage_dir" "$output_path" >/dev/null
}

# Install a locally built package when the caller requested immediate installation.
install_built_package() {
  local package_path="$1"

  if [[ "$INSTALL_PACKAGES" == "yes" ]]; then
    apt-get install -y "$package_path" >/dev/null
  fi
}

# Build and package IMEI's private libaom runtime.
build_aom() {
  local upstream_version="$1"
  local deb_version
  local source_archive="$SOURCE_DIR/aom-$upstream_version.tar.gz"
  local source_dir="$SOURCE_DIR/aom-$upstream_version"
  local build_dir="$BUILD_ROOT/aom"
  local stage_dir="$STAGE_ROOT/aom"
  local output_path

  deb_version="$(deb_version_from_upstream "$upstream_version")-1~$(sanitize_version "$TARGET")"
  output_path="$(package_output_path "imei-libaom" "$deb_version")"

  if [[ "$SKIP_AOM" == "yes" ]]; then
    return 0
  fi

  echo "Building imei-libaom $upstream_version for $TARGET"

  download_source_archive "aom" "$GH_FILE_BASE/SoftCreatR/aom/tar.gz/v$upstream_version" "$AOM_HASH" "$source_archive"
  rm -rf "$source_dir"
  tar -xf "$source_archive" -C "$SOURCE_DIR"
  reset_dir "$build_dir"
  reset_dir "$stage_dir"

  run_logged_command "aom configure" \
    cmake -S "$source_dir" -B "$build_dir" \
      "${CMAKE_GENERATOR_ARGS[@]}" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$IMEI_PREFIX" \
      -DCMAKE_INSTALL_LIBDIR=lib \
      -DCMAKE_INSTALL_RPATH="$IMEI_PREFIX/lib" \
      -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
      -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
      -DBUILD_SHARED_LIBS=ON \
      -DENABLE_DOCS=0 \
      -DENABLE_TESTS=0 \
      -DENABLE_EXAMPLES=0 \
      -DENABLE_CCACHE=0
  run_logged_command "aom build" cmake --build "$build_dir" --parallel "$(nproc)"
  run_logged_command "aom install" env DESTDIR="$stage_dir" cmake --install "$build_dir"
  normalize_runtime_library_locations \
    "$stage_dir$IMEI_PREFIX" \
    "$stage_dir$IMEI_PREFIX/lib" \
    'libaom.so*'
  require_runtime_libraries \
    "$stage_dir$IMEI_PREFIX/lib" \
    'libaom.so*'

  build_package_from_stage \
    "$stage_dir" \
    "imei-libaom" \
    "$deb_version" \
    "AV1 video codec runtime built by IMEI." \
    "" \
    "" \
    "" \
    "" \
    "$output_path"

  install_built_package "$output_path"
}

# Build and package IMEI's private libheif runtime against the IMEI libaom stack.
build_libheif() {
  local upstream_version="$1"
  local deb_version
  local source_archive="$SOURCE_DIR/libheif-$upstream_version.tar.gz"
  local source_dir="$SOURCE_DIR/libheif-$upstream_version"
  local build_dir="$BUILD_ROOT/libheif"
  local stage_dir="$STAGE_ROOT/libheif"
  local output_path
  local extra_depends="imei-libaom"

  if [[ "$SKIP_LIBHEIF" == "yes" ]]; then
    return 0
  fi

  deb_version="$(deb_version_from_upstream "$upstream_version")-1~$(sanitize_version "$TARGET")"
  output_path="$(package_output_path "imei-libheif" "$deb_version")"

  echo "Building imei-libheif $upstream_version for $TARGET"

  download_source_archive "libheif" "$GH_FILE_BASE/strukturag/libheif/tar.gz/v$upstream_version" "$LIBHEIF_HASH" "$source_archive"
  rm -rf "$source_dir"
  tar -xf "$source_archive" -C "$SOURCE_DIR"
  patch_libheif_source_compatibility "$source_dir"
  reset_dir "$build_dir"
  reset_dir "$stage_dir"

  run_logged_command "libheif configure" \
    env PKG_CONFIG_PATH="$IMEI_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
      cmake -S "$source_dir" -B "$build_dir" \
        "${CMAKE_GENERATOR_ARGS[@]}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$IMEI_PREFIX" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_INSTALL_RPATH="$IMEI_PREFIX/lib" \
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
        -DBUILD_SHARED_LIBS=ON \
        -DBUILD_TESTING=OFF \
        -DWITH_EXAMPLES=OFF \
        -DWITH_EXAMPLE_HEIF_THUMB=OFF \
        -DWITH_EXAMPLE_HEIF_VIEW=OFF \
        -DWITH_GDK_PIXBUF=OFF \
        -DBUILD_DOCUMENTATION=OFF \
        -DCMAKE_DISABLE_FIND_PACKAGE_Doxygen=ON \
        -DWITH_AOM_DECODER=ON \
        -DWITH_AOM_ENCODER=ON \
        -DWITH_LIBDE265=ON \
        -DWITH_X265=ON

  run_logged_command "libheif build" cmake --build "$build_dir" --parallel "$(nproc)"
  run_logged_command "libheif install" env DESTDIR="$stage_dir" cmake --install "$build_dir"
  normalize_runtime_library_locations \
    "$stage_dir$IMEI_PREFIX" \
    "$stage_dir$IMEI_PREFIX/lib" \
    'libheif.so*'
  require_runtime_libraries \
    "$stage_dir$IMEI_PREFIX/lib" \
    'libheif.so*'

  build_package_from_stage \
    "$stage_dir" \
    "imei-libheif" \
    "$deb_version" \
    "HEIF/AVIF runtime built by IMEI." \
    "$extra_depends" \
    "" \
    "" \
    "" \
    "$output_path"

  install_built_package "$output_path"
}

# Build and package IMEI's private libjxl runtime.
build_libjxl() {
  local upstream_version="$1"
  local deb_version
  local source_archive="$SOURCE_DIR/libjxl-$upstream_version.tar.gz"
  local source_dir="$SOURCE_DIR/libjxl-$upstream_version"
  local build_dir="$BUILD_ROOT/libjxl"
  local stage_dir="$STAGE_ROOT/libjxl"
  local output_path
  local force_system_brotli="ON"
  local force_system_hwy="ON"
  local force_system_lcms2="ON"
  local enable_skcms="OFF"

  if [[ "$SKIP_JXL" == "yes" ]]; then
    return 0
  fi

  deb_version="$(deb_version_from_upstream "$upstream_version")-1~$(sanitize_version "$TARGET")"
  output_path="$(package_output_path "imei-libjxl" "$deb_version")"

  echo "Building imei-libjxl $upstream_version for $TARGET"

  download_source_archive "libjxl" "$GH_FILE_BASE/libjxl/libjxl/tar.gz/v$upstream_version" "$LIBJXL_HASH" "$source_archive"
  rm -rf "$source_dir"
  tar -xf "$source_archive" -C "$SOURCE_DIR"
  reset_dir "$build_dir"
  reset_dir "$stage_dir"

  populate_libjxl_third_party_deps \
    "$source_dir" \
    brotli \
    highway \
    skcms \
    sjpeg \
    zlib \
    libpng \
    libjpeg-turbo

  if libjxl_dep_is_vendored "$source_dir" brotli; then
    force_system_brotli="OFF"
  fi
  if libjxl_dep_is_vendored "$source_dir" highway; then
    force_system_hwy="OFF"
  fi
  if ! pkg-config --exists 'lcms2 >= 2.12'; then
    force_system_lcms2="OFF"
    enable_skcms="ON"
  fi

  run_logged_command "libjxl configure" \
    env PKG_CONFIG_PATH="$IMEI_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
      cmake -S "$source_dir" -B "$build_dir" \
        "${CMAKE_GENERATOR_ARGS[@]}" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX="$IMEI_PREFIX" \
        -DCMAKE_INSTALL_LIBDIR=lib \
        -DCMAKE_INSTALL_RPATH="$IMEI_PREFIX/lib" \
        -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
        -DCMAKE_INSTALL_RPATH_USE_LINK_PATH=ON \
        -DCMAKE_PREFIX_PATH="$IMEI_PREFIX" \
        -DBUILD_TESTING=OFF \
        -DJPEGXL_ENABLE_TOOLS=OFF \
        -DJPEGXL_ENABLE_DEVTOOLS=OFF \
        -DJPEGXL_ENABLE_DOXYGEN=OFF \
        -DJPEGXL_ENABLE_MANPAGES=OFF \
        -DJPEGXL_ENABLE_BENCHMARK=OFF \
        -DJPEGXL_ENABLE_EXAMPLES=OFF \
        -DJPEGXL_ENABLE_JNI=OFF \
        -DJPEGXL_ENABLE_SJPEG=OFF \
        -DJPEGXL_ENABLE_OPENEXR=OFF \
        -DJPEGXL_ENABLE_JPEGLI=OFF \
        -DJPEGXL_ENABLE_SKCMS="$enable_skcms" \
        -DJPEGXL_ENABLE_TCMALLOC=OFF \
        -DJPEGXL_ENABLE_PLUGINS=OFF \
        -DJPEGXL_FORCE_SYSTEM_BROTLI="$force_system_brotli" \
        -DJPEGXL_FORCE_SYSTEM_LCMS2="$force_system_lcms2" \
        -DJPEGXL_FORCE_SYSTEM_HWY="$force_system_hwy"
  run_logged_command "libjxl build" cmake --build "$build_dir" --parallel "$(nproc)"
  run_logged_command "libjxl install" env DESTDIR="$stage_dir" cmake --install "$build_dir"
  normalize_runtime_library_locations \
    "$stage_dir$IMEI_PREFIX" \
    "$stage_dir$IMEI_PREFIX/lib" \
    'libjxl*.so*' \
    'libjxl_cms*.so*'
  require_runtime_libraries \
    "$stage_dir$IMEI_PREFIX/lib" \
    'libjxl.so*' \
    'libjxl_threads.so*' \
    'libjxl_cms.so*'

  build_package_from_stage \
    "$stage_dir" \
    "imei-libjxl" \
    "$deb_version" \
    "JPEG XL runtime built by IMEI." \
    "" \
    "" \
    "" \
    "" \
    "$output_path"

  install_built_package "$output_path"
}

# Expose the installed ImageMagick CLI tools in /usr/bin while keeping files under /opt/imei.
create_imagemagick_symlinks() {
  local stage_dir="$1"
  local bin_dir="$stage_dir$IMEI_PREFIX/bin"
  local link_dir="$stage_dir/usr/bin"
  local binary

  mkdir -p "$link_dir"

  find "$bin_dir" -maxdepth 1 \( -type f -o -type l \) -print0 | while IFS= read -r -d '' binary; do
    ln -sf "${binary#"$stage_dir"}" "$link_dir/$(basename "$binary")"
  done
}

# IMEI exports ImageMagick command names into /usr/bin, so distro ImageMagick
# command packages must be treated as conflicting system installs.
imagemagick_conflict_packages() {
  printf '%s\n' \
    imagemagick \
    imagemagick-6-common \
    imagemagick-6.q16 \
    imagemagick-6.q16hdri \
    imagemagick-7-common \
    imagemagick-7.q16 \
    imagemagick-7.q16hdri \
    graphicsmagick-imagemagick-compat
}

join_lines_by() {
  local delimiter="$1"
  local item
  local output=""

  while IFS= read -r item; do
    [[ -n "$item" ]] || continue
    if [[ -z "$output" ]]; then
      output="$item"
    else
      output+="$delimiter$item"
    fi
  done

  printf '%s\n' "$output"
}

# Translate one delegate policy entry into an ImageMagick configure flag.
append_delegate_configure_arg() {
  local delegate_name="$1"
  local configure_option
  local enable_mode="with"

  configure_option="$(delegate_configure_option "$delegate_name")"
  if [[ -z "$configure_option" ]]; then
    return 0
  fi

  if delegate_is_disabled "$delegate_name"; then
    enable_mode="without"
  fi

  IMAGEMAGICK_CONFIGURE_ARGS+=("--${enable_mode}-${configure_option}")
}

# Build the ImageMagick package against the already-built private delegate stack.
# Delegate toggles are derived from the shared delegate policy so dependency
# installation and configure flags stay aligned.
build_imagemagick() {
  local upstream_version="$1"
  local deb_version
  local source_archive="$SOURCE_DIR/ImageMagick-$upstream_version.tar.gz"
  local source_dir="$SOURCE_DIR/ImageMagick-$upstream_version"
  local build_dir="$BUILD_ROOT/imagemagick"
  local stage_dir="$STAGE_ROOT/imagemagick"
  local output_path
  local extra_depends=()
  local dir_name="ImageMagick-$upstream_version"
  local static_flag="disable"
  local shared_flag="enable"
  local opencl_flag="disable"
  local magick_plus_plus_flag="without"
  local perl_flag="without"
  local heic_flag="without"
  local jxl_flag="without"
  local provided_packages
  local conflict_packages
  IMAGEMAGICK_CONFIGURE_ARGS=()

  deb_version="$(deb_version_from_upstream "$upstream_version")-1~$(sanitize_version "$TARGET")"
  output_path="$(package_output_path "imei-imagemagick" "$deb_version")"

  if [[ "$BUILD_STATIC" != "yes" ]]; then
    static_flag="disable"
    shared_flag="enable"
  else
    static_flag="enable"
    shared_flag="disable"
  fi

  if [[ "$ENABLE_OPENCL" == "yes" ]]; then
    opencl_flag="enable"
  fi
  if [[ "$ENABLE_MAGICK_PLUS_PLUS" == "yes" ]]; then
    magick_plus_plus_flag="with"
  fi
  if [[ "$ENABLE_PERL" == "yes" ]]; then
    perl_flag="with"
  fi

  if [[ "${upstream_version%%.*}" == "6" ]]; then
    dir_name="ImageMagick6-$upstream_version"
    download_source_archive "imagemagick" "$GH_FILE_BASE/ImageMagick/ImageMagick6/tar.gz/$upstream_version" "$IMAGEMAGICK_HASH" "$source_archive"
  else
    download_source_archive "imagemagick" "$GH_FILE_BASE/ImageMagick/ImageMagick/tar.gz/$upstream_version" "$IMAGEMAGICK_HASH" "$source_archive"
  fi

  echo "Building imei-imagemagick $upstream_version for $TARGET"

  rm -rf "$source_dir" "${SOURCE_DIR:?}/$dir_name"
  tar -xf "$source_archive" -C "$SOURCE_DIR"
  source_dir="$SOURCE_DIR/$dir_name"
  reset_dir "$build_dir"
  reset_dir "$stage_dir"

  if [[ "$SKIP_AOM" != "yes" ]]; then
    extra_depends+=("imei-libaom")
  fi
  if [[ "$SKIP_LIBHEIF" != "yes" ]]; then
    extra_depends+=("imei-libheif")
    heic_flag="with"
  fi
  if [[ "$SKIP_JXL" != "yes" ]]; then
    extra_depends+=("imei-libjxl")
    jxl_flag="with"
  fi

  append_delegate_configure_arg djvu
  append_delegate_configure_arg fftw
  append_delegate_configure_arg fontconfig
  append_delegate_configure_arg freetype
  append_delegate_configure_arg gslib
  append_delegate_configure_arg gvc
  append_delegate_configure_arg jbig
  append_delegate_configure_arg jpeg
  append_delegate_configure_arg lcms
  append_delegate_configure_arg lqr
  append_delegate_configure_arg lzma
  append_delegate_configure_arg openexr
  append_delegate_configure_arg openjp2
  append_delegate_configure_arg pango
  append_delegate_configure_arg png
  append_delegate_configure_arg raqm
  append_delegate_configure_arg raw
  append_delegate_configure_arg rsvg
  append_delegate_configure_arg tiff
  append_delegate_configure_arg webp
  append_delegate_configure_arg wmf
  append_delegate_configure_arg xml
  append_delegate_configure_arg zstd
  IMAGEMAGICK_CONFIGURE_ARGS+=("--${heic_flag}-heic" "--${jxl_flag}-jxl")

  (
    cd "$source_dir"
    run_logged_command "ImageMagick configure" \
      env \
        PKG_CONFIG_PATH="$IMEI_PREFIX/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
        CPPFLAGS="-I$IMEI_PREFIX/include" \
        LDFLAGS="-L$IMEI_PREFIX/lib -Wl,-rpath,$IMEI_PREFIX/lib" \
        ./configure \
        --prefix="$IMEI_PREFIX" \
        --sysconfdir="$IMEI_PREFIX/etc" \
        --"${static_flag}"-static \
        --"${shared_flag}"-shared \
        --enable-openmp \
        --enable-cipher \
        --enable-hdri \
        --disable-docs \
        --"${opencl_flag}"-opencl \
        --with-threads \
        --with-modules \
        --with-quantum-depth="$QUANTUM_DEPTH" \
        --"${magick_plus_plus_flag}"-magick-plus-plus \
        --"${perl_flag}"-perl \
        --without-jemalloc \
        --without-tcmalloc \
        --without-umem \
        --without-autotrace \
        --with-bzlib \
        --with-x \
        --with-zlib \
        --without-dps \
        --without-flif \
        --without-fpx \
        "${IMAGEMAGICK_CONFIGURE_ARGS[@]}"
    patch_imagemagick_version_branding "$source_dir"
    run_logged_command "ImageMagick build" make --jobs="$(nproc)"
    run_logged_command "ImageMagick install" env DESTDIR="$stage_dir" make install
  )

  create_imagemagick_symlinks "$stage_dir"

  provided_packages="imagemagick"
  conflict_packages="$(imagemagick_conflict_packages | join_lines_by ', ')"

  build_package_from_stage \
    "$stage_dir" \
    "imei-imagemagick" \
    "$deb_version" \
    "ImageMagick with private IMEI delegate libraries installed under $IMEI_PREFIX." \
    "$(join_by ', ' "${extra_depends[@]}")" \
    "" \
    "$provided_packages" \
    "$conflict_packages" \
    "$output_path"

  install_built_package "$output_path"
}

build_aom "$AOM_VERSION"
build_libheif "$LIBHEIF_VERSION"
build_libjxl "$LIBJXL_VERSION"
build_imagemagick "$IMAGEMAGICK_VERSION"

if [[ "$INSTALL_PACKAGES" == "yes" ]]; then
  run_post_install_smoke_tests
fi

cat <<EOF
Build completed.
Target: $TARGET
Architecture: $ARCH
Output directory: $OUTPUT_DIR
EOF
