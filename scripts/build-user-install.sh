#!/usr/bin/env bash

#
# Build and install IMEI into a user-owned prefix without using apt or dpkg.
# This is an opt-in alternative to the normal package-managed workflow and is
# intended for unprivileged installs under paths like ~/.local/imei.
#

set -euo pipefail

export IMEI_PREFIX="${IMEI_PREFIX:-$HOME/.local/imei}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/delegates.sh"

TARGET="$(detect_local_target)"
WORK_DIR="/tmp/imei-user-build"
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
Usage: scripts/build-user-install.sh [options]

Options:
  --prefix <dir>                    Install prefix (default: ~/.local/imei)
  --target <target>                 Override target label (informational)
  --work-dir <dir>                  Build workspace
  --keep-work-dir                   Keep the build workspace after completion
  --skip-aom                        Do not build libaom
  --skip-libheif                    Do not build libheif
  --skip-jpeg-xl                    Do not build libjxl
  --imagemagick-version <version>   Override ImageMagick version
  --aom-version <version>           Override libaom version
  --libheif-version <version>       Override libheif version
  --jpeg-xl-version <version>       Override libjxl version
  --imagemagick-quantum-depth <n>   ImageMagick quantum depth (8, 16, 32)
  --imagemagick-opencl              Enable OpenCL in ImageMagick
  --imagemagick-build-static        Build ImageMagick static instead of shared
  --imagemagick-with-magick-plus-plus
                                    Build the Magick++ C++ interface
  --imagemagick-with-perl           Build PerlMagick
  --disable-delegate <name>         Disable a specific ImageMagick delegate
  --help                            Show this help text
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
  --prefix)
    IMEI_PREFIX="${2/#\~/$HOME}"
    shift 2
    ;;
  --target)
    TARGET="$2"
    shift 2
    ;;
  --work-dir)
    WORK_DIR="$2"
    shift 2
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

require_commands curl sha1sum tar make cmake pkg-config sed find xargs

if command_exists ninja; then
  CMAKE_GENERATOR_ARGS=(-G Ninja)
fi

case "$QUANTUM_DEPTH" in
8 | 16 | 32) ;;
*) die "Invalid quantum depth: $QUANTUM_DEPTH" ;;
esac

if [[ "$SKIP_AOM" == "yes" && "$SKIP_LIBHEIF" != "yes" ]]; then
  die "libheif requires libaom in the IMEI install layout. Use --skip-libheif together with --skip-aom."
fi

if delegate_is_disabled heic; then
  SKIP_LIBHEIF="yes"
  SKIP_AOM="yes"
fi

if delegate_is_disabled jxl; then
  SKIP_JXL="yes"
fi

mkdir -p "$WORK_DIR" "$IMEI_PREFIX"

SOURCE_DIR="$WORK_DIR/sources"
BUILD_ROOT="$WORK_DIR/build"
mkdir -p "$SOURCE_DIR" "$BUILD_ROOT"

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

  PATH="$IMEI_PREFIX/bin:$PATH" \
    LD_LIBRARY_PATH="$IMEI_PREFIX/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    smoke_test_imagemagick_installation "$IMEI_PREFIX/bin/magick" "$IMEI_PREFIX/bin/identify" "${expected_formats[@]}"
}

reset_dir() {
  rm -rf "$1"
  mkdir -p "$1"
}

write_environment_file() {
  local env_file="$IMEI_PREFIX/imei-env.sh"
  mkdir -p "$IMEI_PREFIX/bin"

  cat >"$env_file" <<EOF
#!/usr/bin/env bash
export IMEI_PREFIX="$IMEI_PREFIX"
export PATH="$IMEI_PREFIX/bin:\$PATH"
export LD_LIBRARY_PATH="$IMEI_PREFIX/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export PKG_CONFIG_PATH="$IMEI_PREFIX/lib/pkgconfig\${PKG_CONFIG_PATH:+:\$PKG_CONFIG_PATH}"
EOF
  chmod 0755 "$env_file"
}

build_aom() {
  local upstream_version="$1"
  local source_archive="$SOURCE_DIR/aom-$upstream_version.tar.gz"
  local source_dir="$SOURCE_DIR/aom-$upstream_version"
  local build_dir="$BUILD_ROOT/aom"

  if [[ "$SKIP_AOM" == "yes" ]]; then
    return 0
  fi

  echo "Building libaom $upstream_version for user prefix $IMEI_PREFIX"

  download_source_archive "aom" "$GH_FILE_BASE/SoftCreatR/aom/tar.gz/v$upstream_version" "$AOM_HASH" "$source_archive"
  rm -rf "$source_dir"
  tar -xf "$source_archive" -C "$SOURCE_DIR"
  reset_dir "$build_dir"

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
  run_logged_command "aom install" cmake --install "$build_dir"
  normalize_runtime_library_locations \
    "$IMEI_PREFIX" \
    "$IMEI_PREFIX/lib" \
    'libaom.so*'
  require_runtime_libraries \
    "$IMEI_PREFIX/lib" \
    'libaom.so*'
}

build_libheif() {
  local upstream_version="$1"
  local source_archive="$SOURCE_DIR/libheif-$upstream_version.tar.gz"
  local source_dir="$SOURCE_DIR/libheif-$upstream_version"
  local build_dir="$BUILD_ROOT/libheif"

  if [[ "$SKIP_LIBHEIF" == "yes" ]]; then
    return 0
  fi

  echo "Building libheif $upstream_version for user prefix $IMEI_PREFIX"

  download_source_archive "libheif" "$GH_FILE_BASE/strukturag/libheif/tar.gz/v$upstream_version" "$LIBHEIF_HASH" "$source_archive"
  rm -rf "$source_dir"
  tar -xf "$source_archive" -C "$SOURCE_DIR"
  patch_libheif_source_compatibility "$source_dir"
  reset_dir "$build_dir"

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
        -DCMAKE_PREFIX_PATH="$IMEI_PREFIX" \
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
  run_logged_command "libheif install" cmake --install "$build_dir"
  normalize_runtime_library_locations \
    "$IMEI_PREFIX" \
    "$IMEI_PREFIX/lib" \
    'libheif.so*'
  require_runtime_libraries \
    "$IMEI_PREFIX/lib" \
    'libheif.so*'
}

build_libjxl() {
  local upstream_version="$1"
  local source_archive="$SOURCE_DIR/libjxl-$upstream_version.tar.gz"
  local source_dir="$SOURCE_DIR/libjxl-$upstream_version"
  local build_dir="$BUILD_ROOT/libjxl"
  local force_system_brotli="ON"
  local force_system_hwy="ON"
  local force_system_lcms2="ON"
  local enable_skcms="OFF"

  if [[ "$SKIP_JXL" == "yes" ]]; then
    return 0
  fi

  echo "Building libjxl $upstream_version for user prefix $IMEI_PREFIX"

  download_source_archive "libjxl" "$GH_FILE_BASE/libjxl/libjxl/tar.gz/v$upstream_version" "$LIBJXL_HASH" "$source_archive"
  rm -rf "$source_dir"
  tar -xf "$source_archive" -C "$SOURCE_DIR"
  reset_dir "$build_dir"

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
  run_logged_command "libjxl install" cmake --install "$build_dir"
  normalize_runtime_library_locations \
    "$IMEI_PREFIX" \
    "$IMEI_PREFIX/lib" \
    'libjxl*.so*' \
    'libjxl_cms*.so*'
  require_runtime_libraries \
    "$IMEI_PREFIX/lib" \
    'libjxl.so*' \
    'libjxl_threads.so*' \
    'libjxl_cms.so*'
}

build_imagemagick() {
  local upstream_version="$1"
  local source_archive="$SOURCE_DIR/ImageMagick-$upstream_version.tar.gz"
  local source_dir="$SOURCE_DIR/ImageMagick-$upstream_version"
  local build_dir="$BUILD_ROOT/imagemagick"
  local dir_name="ImageMagick-$upstream_version"
  local static_flag="disable"
  local shared_flag="enable"
  local opencl_flag="disable"
  local magick_plus_plus_flag="without"
  local perl_flag="without"
  local heic_flag="without"
  local jxl_flag="without"
  local configure_args=()

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

  echo "Building ImageMagick $upstream_version for user prefix $IMEI_PREFIX"

  rm -rf "$source_dir" "${SOURCE_DIR:?}/$dir_name"
  tar -xf "$source_archive" -C "$SOURCE_DIR"
  source_dir="$SOURCE_DIR/$dir_name"
  reset_dir "$build_dir"

  if [[ "$SKIP_LIBHEIF" != "yes" ]]; then
    heic_flag="with"
  fi
  if [[ "$SKIP_JXL" != "yes" ]]; then
    jxl_flag="with"
  fi

  for delegate_name in "${IMEI_DEFAULT_DELEGATES[@]}"; do
    local option_name=""
    local enable_mode="with"

    case "$delegate_name" in
    heic | jxl | zip) continue ;;
    esac

    option_name="$(delegate_configure_option "$delegate_name")"
    [[ -n "$option_name" ]] || continue

    if delegate_is_disabled "$delegate_name"; then
      enable_mode="without"
    fi

    configure_args+=("--${enable_mode}-${option_name}")
  done
  configure_args+=("--${heic_flag}-heic" "--${jxl_flag}-jxl")

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
        "${configure_args[@]}"
    patch_imagemagick_version_branding "$source_dir"
    run_logged_command "ImageMagick build" make --jobs="$(nproc)"
    run_logged_command "ImageMagick install" make install
  )
}

write_environment_file
build_aom "$AOM_VERSION"
build_libheif "$LIBHEIF_VERSION"
build_libjxl "$LIBJXL_VERSION"
build_imagemagick "$IMAGEMAGICK_VERSION"
write_environment_file
run_post_install_smoke_tests

cat <<EOF
User install completed.
Target: $TARGET
Prefix: $IMEI_PREFIX

Add IMEI to your shell with:
  . "$IMEI_PREFIX/imei-env.sh"

Remove the user install with:
  rm -rf "$IMEI_PREFIX"
EOF
