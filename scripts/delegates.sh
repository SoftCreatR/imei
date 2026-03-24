#!/usr/bin/env bash

#
# Shared delegate policy and metadata.
# Defines the default delegate set IMEI aims to support, normalizes user-facing
# delegate names, and maps delegates to pkg-config modules, package fallbacks,
# and ImageMagick configure options.
#

IMEI_DEFAULT_DELEGATES=(
  cairo
  djvu
  fftw
  fontconfig
  freetype
  gslib
  gvc
  heic
  jbig
  jpeg
  jxl
  lcms
  lqr
  lzma
  openexr
  openjp2
  pango
  png
  raqm
  raw
  rsvg
  tiff
  webp
  wmf
  xml
  zip
  zstd
)

# Normalize user-facing delegate aliases to the canonical IMEI delegate name.
delegate_normalize_name() {
  local value="${1,,}"

  case "$value" in
  avif | heif | heic) echo "heic" ;;
  graphviz | gvc) echo "gvc" ;;
  gs | ghostscript | gslib) echo "gslib" ;;
  jp2 | openjpeg | openjp2) echo "openjp2" ;;
  jpeg-xl | jpegxl | jxl) echo "jxl" ;;
  jpg | jpeg) echo "jpeg" ;;
  lcms | lcms2) echo "lcms" ;;
  lqr | liquid-rescale) echo "lqr" ;;
  pango | pangocairo) echo "pango" ;;
  svg | rsvg) echo "rsvg" ;;
  tif | tiff) echo "tiff" ;;
  xml | libxml2) echo "xml" ;;
  *) echo "$value" ;;
  esac
}

# Return success when the delegate is part of IMEI's known delegate inventory.
delegate_is_known() {
  local normalized

  normalized="$(delegate_normalize_name "$1")"
  case " ${IMEI_DEFAULT_DELEGATES[*]} " in
  *" $normalized "*) return 0 ;;
  *) return 1 ;;
  esac
}

# Map a delegate to the pkg-config module that proves dev support is present.
delegate_pkgconfig_module() {
  case "$(delegate_normalize_name "$1")" in
  cairo) echo "cairo" ;;
  djvu) echo "ddjvuapi" ;;
  fftw) echo "fftw3" ;;
  fontconfig) echo "fontconfig" ;;
  freetype) echo "freetype2" ;;
  heic) echo "libheif" ;;
  jxl) echo "libjxl" ;;
  lcms) echo "lcms2" ;;
  lqr) echo "liblqr-1" ;;
  lzma) echo "liblzma" ;;
  openexr) echo "OpenEXR" ;;
  openjp2) echo "libopenjp2" ;;
  pango) echo "pangocairo" ;;
  png) echo "libpng" ;;
  raqm) echo "raqm" ;;
  rsvg) echo "librsvg-2.0" ;;
  tiff) echo "libtiff-4" ;;
  webp) echo "libwebp" ;;
  xml) echo "libxml-2.0" ;;
  zip) echo "libzip" ;;
  zstd) echo "libzstd" ;;
  *) echo "" ;;
  esac
}

# Fallback packages for delegates that are not fully discoverable via pkg-config.
delegate_package_fallbacks() {
  case "$(delegate_normalize_name "$1")" in
  gslib) echo "ghostscript gsfonts libgs-dev" ;;
  gvc) echo "libgraphviz-dev" ;;
  heic) echo "libde265-dev libx265-dev" ;;
  jbig) echo "libjbig-dev" ;;
  jpeg) echo "libjpeg-dev" ;;
  raqm) echo "libraqm-dev libfribidi-dev libharfbuzz-dev" ;;
  raw) echo "libraw-dev" ;;
  wmf) echo "libwmf-dev" ;;
  zip) echo "libzip-dev" ;;
  *) echo "" ;;
  esac
}

# Map a delegate to the corresponding ImageMagick configure switch name.
delegate_configure_option() {
  case "$(delegate_normalize_name "$1")" in
  djvu) echo "djvu" ;;
  fftw) echo "fftw" ;;
  fontconfig) echo "fontconfig" ;;
  freetype) echo "freetype" ;;
  gslib) echo "gslib" ;;
  gvc) echo "gvc" ;;
  heic) echo "heic" ;;
  jbig) echo "jbig" ;;
  jpeg) echo "jpeg" ;;
  jxl) echo "jxl" ;;
  lcms) echo "lcms" ;;
  lqr) echo "lqr" ;;
  lzma) echo "lzma" ;;
  openexr) echo "openexr" ;;
  openjp2) echo "openjp2" ;;
  pango) echo "pango" ;;
  png) echo "png" ;;
  raqm) echo "raqm" ;;
  raw) echo "raw" ;;
  rsvg) echo "rsvg" ;;
  tiff) echo "tiff" ;;
  webp) echo "webp" ;;
  wmf) echo "wmf" ;;
  xml) echo "xml" ;;
  zstd) echo "zstd" ;;
  *) echo "" ;;
  esac
}
