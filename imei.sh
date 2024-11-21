#!/usr/bin/env bash

##############################################################
# Title          : IMEI - ImageMagick Easy Install           #
# Description    : ImageMagick® for Debian/Ubuntu,           #
#                  including advanced delegate support.      #
#                                                            #
# Author         : Sascha Greuel <hello@1-2.dev>             #
# Date           : 2024-06-20 11:28                          #
# License        : ISC                                       #
# Version        : 6.11.4                                    #
#                                                            #
# Usage          : bash ./imei.sh                            #
##############################################################

######################
# Check requirements #
######################

# Check if user is root
[ "$(id -u)" != "0" ] && {
  echo "Error: You must be root or use sudo to run this script"
  exit 1
}

command_exists() {
  command -v "$@" >/dev/null 2>&1
}

# Make sure, that we are on Debian or Ubuntu
if ! command_exists apt-get; then
  echo "This script cannot run on any other system than Debian or Ubuntu"
  exit 1
fi

# Checking if lsb_release is installed or install it
if ! command_exists lsb_release; then
  apt-get update && apt-get install -qq lsb-release >/dev/null 2>&1
fi

# Checking if imagemagick is already installed via apt/dpkg
if dpkg -l | grep -qE '^ii\s+imagemagick\s'; then
  echo "ImageMagick is already installed via apt/dpkg. Please uninstall it first, before proceeding"
  exit 1
fi

####################
# Script arguments #
####################

while [ $# -gt 0 ]; do
  case "$1" in
  --force)
    FORCE="yes"
    ;;
  --force-imagemagick | --force-im)
    FORCE_IMAGEMAGICK="yes"
    ;;
  --imagemagick-version* | --im-version*)
    if [[ "$1" == *=* ]]; then
      IMAGEMAGICK_VER="${1#*=}"
    else
      shift
      IMAGEMAGICK_VER="$1"
    fi
    ;;
  --imagemagick-quantum-depth* | --im-q*)
    if [[ "$1" == *=* ]]; then
      QUANTUM_DEPTH="${1#*=}"
    else
      shift
      QUANTUM_DEPTH="$1"
    fi
    ;;
  --imagemagick-opencl | --im-ocl)
    USE_OPENCL="yes"
    ;;
  --imagemagick-build-static | --im-build-static)
    BUILD_STATIC="yes"
    ;;
  --skip-aom)
    SKIP_AOM="yes"
    ;;
  --aom-version*)
    if [[ "$1" == *=* ]]; then
      AOM_VER="${1#*=}"
    else
      shift
      AOM_VER="$1"
    fi
    ;;
  --skip-libheif | --skip-heif)
    SKIP_LIBHEIF="yes"
    ;;
  --libheif-version* | --heif-version*)
    if [[ "$1" == *=* ]]; then
      LIBHEIF_VER="${1#*=}"
    else
      shift
      LIBHEIF_VER="$1"
    fi
    ;;
  --skip-jpeg-xl | --skip-jxl)
    SKIP_JXL="yes"
    ;;
  --jpeg-xl-version* | --jxl-version*)
    if [[ "$1" == *=* ]]; then
      JXL_VER="${1#*=}"
    else
      shift
      JXL_VER="$1"
    fi
    ;;
  --skip-dependencies | --skip-deps)
    SKIP_DEPS="yes"
    ;;
  --log-file*)
    if [[ "$1" == *=* ]]; then
      LOG_FILE="${1#*=}"
    else
      shift
      LOG_FILE="$1"
    fi
    ;;
  --work-dir*)
    if [[ "$1" == *=* ]]; then
      WORK_DIR="${1#*=}"
    else
      shift
      WORK_DIR="$1"
    fi
    ;;
  --build-dir*)
    if [[ "$1" == *=* ]]; then
      BUILD_DIR="${1#*=}"
    else
      shift
      BUILD_DIR="$1"
    fi
    ;;
  --config-dir*)
    if [[ "$1" == *=* ]]; then
      CONFIG_DIR="${1#*=}"
    else
      shift
      CONFIG_DIR="$1"
    fi
    ;;
  --ci)
    CI_BUILD="yes"
    ;;
  --no-sig-verify | --dev)
    VERIFY_SIGNATURE="${CYELLOW}disabled${CEND}"
    ;;
  --use-checkinstall | --checkinstall)
    CHECKINSTALL="yes"
    ;;
  --build-only)
    INSTALL="no"
    ;;
  --no-backports)
    BACKPORTS="${CYELLOW}disabled${CEND}"
    ;;
  --build-cflags*)
    if [[ "$1" == *=* ]]; then
      BUILD_CFLAGS="${1#*=}"
    else
      shift
      BUILD_CFLAGS="$1"
    fi
    ;;
  --build-cxxflags*)
    if [[ "$1" == *=* ]]; then
      BUILD_CXXFLAGS="${1#*=}"
    else
      shift
      BUILD_CXXFLAGS="$1"
    fi
    ;;
  *) ;;
  esac
  shift
done

export DEBIAN_FRONTEND=noninteractive

#############
# Variables #
#############

if [ -z "$WORK_DIR" ]; then
  WORK_DIR=/usr/local/src/imei
elif [ -d "$WORK_DIR" ] && [ "$(ls -A $WORK_DIR)" ]; then
  echo -e "${CRED}Work Dir $WORK_DIR is not empty!${CEND}" >&2
  return 1
fi

if [ -z "$BUILD_DIR" ]; then
  BUILD_DIR=/usr/local
fi

if [ -z "$CONFIG_DIR" ]; then
  CONFIG_DIR="$BUILD_DIR/etc"
fi

allowedQuantumDepth=(8 16 32)
if [[ -z "$QUANTUM_DEPTH" || ! " ${allowedQuantumDepth[*]} " =~ $QUANTUM_DEPTH ]]; then
  QUANTUM_DEPTH=16
fi

if [ -z "$BUILD_CFLAGS" ]; then
  BUILD_CFLAGS="-O3 -mtune=generic" 
fi

if [ -z "$BUILD_CXXFLAGS" ]; then
  BUILD_CXXFLAGS="-O3 -mtune=generic"
fi

START=$(date +%s)
OS_DISTRO="$(lsb_release -ds)"
OS_SHORT_CODENAME="$(lsb_release -sc)"
OS_ARCH="$(uname -m)"
GH_FILE_BASE="https://codeload.github.com"
SOURCE_LIST="/etc/apt/sources.list.d/imei.list"
LIB_DIR="/usr/local"
CMAKE_VERSION="0.0.0"

# Colors
CSI='\033['
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CYELLOW="${CSI}1;33m"
CBLUE="${CSI}1;36m"
CEND="${CSI}0m"

####################
# Helper functions #
####################

displaytime() {
  local T=$1
  local D=$((T / 60 / 60 / 24))
  local H=$((T / 60 / 60 % 24))
  local M=$((T / 60 % 60))
  local S=$((T % 60))

  ((D > 0)) && printf '%d days ' $D
  ((H > 0)) && printf '%d hours ' $H
  ((M > 0)) && printf '%d minutes ' $M
  ((D > 0 || H > 0 || M > 0)) && printf 'and '

  printf '%d seconds\n' $S
}

str_repeat() {
  printf -v v "%-*s" "$1" ""
  echo "${v// /$2}"
}

version() {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
}

cleanup() {
  if [ -d "$WORK_DIR" ]; then
    rm -rf "$WORK_DIR"
  fi

  if [ -f "$SOURCE_LIST" ]; then
    rm "$SOURCE_LIST"
  fi

  return 0
}

getClient() {
  if command -v curl &>/dev/null; then
    CLIENT="curl"
  elif command -v wget &>/dev/null; then
    CLIENT="wget"
  elif command -v http &>/dev/null; then
    CLIENT="httpie"
  else
    echo -e "${CRED}This tool requires either curl, wget or httpie to be installed.${CEND}" >&2
    return 1
  fi
}

httpGet() {
  if [[ -n "${GITHUB_TOKEN}" ]]; then
    AUTHORIZATION='{"Authorization": "Bearer '"$GITHUB_TOKEN"'}"}'
  fi

  case "$CLIENT" in
  curl) curl -A curl -s -H "$AUTHORIZATION" "$@" ;;
  wget) wget -qO- --header="$AUTHORIZATION" "$@" ;;
  httpie) http -b GET "$@" "$AUTHORIZATION" ;;
  esac
}

getImeiInfo() {
  local IMEI_INFO

  IMEI_INFO=$(httpGet "https://api.github.com/repos/SoftCreatR/imei/tags")
  IMEI_LATEST_VERSION_COMMIT=$(echo "$IMEI_INFO" | grep -oP '(?<="sha": ")[^"]*' | head -1)
  IMEI_LATEST_VERSION_NAME=$(echo "$IMEI_INFO" | grep -oP '(?<="name": ")[^"]*' | head -1)
}

########
# Init #
########

# Display execution time and clean up on exit
trap cleanup 0 1 2 3 6 15

# Clean up on execution
cleanup

# Set log file, if unset
if [ -z "$LOG_FILE" ]; then
  LOG_FILE="/var/log/imei-$START.log"
fi

# Link log file
ln -fs "$LOG_FILE" /var/log/imei.log

# Create working directory
[ ! -d "$WORK_DIR" ] && mkdir -p "$WORK_DIR"

# Check if working directory was created
if [[ ! "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
  echo -e "${CRED}Could not create temp directory $WORK_DIR${CEND}"
  exit 1
fi

if [ -z "$CLIENT" ]; then
  getClient || exit 1
fi

if [ -z "$IMEI_LATEST_VERSION_NAME" ]; then
  getImeiInfo || exit 1
fi

###################
# Integrity check #
###################

if [ -z "$CI_BUILD" ] && [ -z "$VERIFY_SIGNATURE" ] && [ -f "$0" ]; then
  if [[ -z "$IMEI_LATEST_VERSION_COMMIT" || -z "$IMEI_LATEST_VERSION_NAME" ]]; then
    echo -e " ${CRED}Signature verification failed! (1)${CEND}"
    exit 1
  fi

  SIGNATURE_FILE="/tmp/imei.sh.sig"
  PUBLIC_KEY_FILE="/tmp/imei.sh.pem"

  sigCleanup() {
    if [ -f "$SIGNATURE_FILE" ]; then
      rm "$SIGNATURE_FILE"
    fi

    if [ -f "$PUBLIC_KEY_FILE" ]; then
      rm "$PUBLIC_KEY_FILE"
    fi
  }

  # Install OpenSSL, if it's not already installed
  if ! command_exists openssl; then
    apt-get update && apt-get install -qq openssl >/dev/null 2>&1
  fi

  if {
    httpGet "https://raw.githubusercontent.com/SoftCreatR/imei/$IMEI_LATEST_VERSION_COMMIT/imei.sh.sig" >"$SIGNATURE_FILE"

    if [ ! -f "$PUBLIC_KEY_FILE" ]; then
      httpGet "https://raw.githubusercontent.com/SoftCreatR/imei/$IMEI_LATEST_VERSION_COMMIT/imei.sh.pem" >"$PUBLIC_KEY_FILE"
    fi

    openssl dgst -sha512 -verify "$PUBLIC_KEY_FILE" -signature "$SIGNATURE_FILE" "$0"
  } >>"$LOG_FILE" 2>&1; then
    sigCleanup

    echo -ne "\ec"
  else
    sigCleanup

    echo -ne "\ec"

    echo -e " ${CRED}Signature verification failed! (2)${CEND}"
    echo ""
    echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
    exit 1
  fi
fi

##################
# Version checks #
##################

if [ -f "$0" ]; then
  INSTALLER_VER=$(grep -oP 'Version\s+:\s+\K([\d\.]+)' "$0")
  INSTALLER_LATEST_VER="$IMEI_LATEST_VERSION_NAME"
fi

if [ -z "$IMAGEMAGICK_VER" ]; then
  IMAGEMAGICK_VER=$(httpGet "https://raw.githubusercontent.com/SoftCreatR/imei/main/versions/imagemagick.version")
  IMAGEMAGICK_HASH=$(httpGet "https://raw.githubusercontent.com/SoftCreatR/imei/main/versions/imagemagick.hash")
fi

if [ -z "$AOM_VER" ]; then
  AOM_VER=$(httpGet "https://raw.githubusercontent.com/SoftCreatR/imei/main/versions/aom.version")
  AOM_HASH=$(httpGet "https://raw.githubusercontent.com/SoftCreatR/imei/main/versions/aom.hash")
fi

if [ -z "$LIBHEIF_VER" ]; then
  LIBHEIF_VER=$(httpGet "https://raw.githubusercontent.com/SoftCreatR/imei/main/versions/libheif.version")
  LIBHEIF_HASH=$(httpGet "https://raw.githubusercontent.com/SoftCreatR/imei/main/versions/libheif.hash")
fi

if [ -z "$JXL_VER" ]; then
  JXL_VER=$(httpGet "https://raw.githubusercontent.com/SoftCreatR/imei/main/versions/libjxl.version")
  JXL_HASH=$(httpGet "https://raw.githubusercontent.com/SoftCreatR/imei/main/versions/libjxl.hash")
fi

# Make sure, that a version number for ImageMagick has been set
if [ -z "$IMAGEMAGICK_VER" ]; then
  echo -e "${CRED}Unable to determine version number for ImageMagick${CEND}"

  exit 1
fi

# Make sure, that a version number for aom has been set
if [ -z "$AOM_VER" ]; then
  echo -e "${CRED}Unable to determine version number for aom${CEND}"

  exit 1
fi

# Make sure, that a version number for libheif has been set
if [ -z "$LIBHEIF_VER" ]; then
  echo -e "${CRED}Unable to determine version number for libheif${CEND}"

  exit 1
fi

# Make sure, that a version number for JPEG XL has been set
if [ -z "$JXL_VER" ]; then
  echo -e "${CRED}Unable to determine version number for JPEG XL${CEND}"

  exit 1
fi

if command_exists magick; then
  INSTALLED_IMAGEMAGICK_VER=$(magick -version | grep -oP 'Version: ImageMagick \K([\d\.\-]+)')
fi

if [ -L "$LIB_DIR/lib/libaom.so" ]; then
  INSTALLED_AOM_VER=$(readlink -f "$LIB_DIR/lib/libaom.so" | xargs basename | grep -oP 'libaom.so.\K([\d\.]+)')
fi

if [ -L "$LIB_DIR/lib/libheif.so" ]; then
  INSTALLED_LIBHEIF_VER=$(readlink -f "$LIB_DIR/lib/libheif.so" | xargs basename | grep -oP 'libheif.so.\K([\d\.]+)')
fi

if [ -L "$LIB_DIR/lib/libjxl.so" ]; then
  INSTALLED_JXL_VER=$(readlink -f "$LIB_DIR/lib/libjxl.so" | xargs basename | grep -oP 'libjxl.so.\K([\d\.]+)')
fi

#######################
# Installer functions #
#######################

# Speed up the compilation process
NUM_CORES=$(nproc || echo 1)
export CC=gcc CXX=g++ MAKEFLAGS="-j$((NUM_CORES + 1)) -l${NUM_CORES}"

# Build dependencies
install_deps() {
  echo -ne ' Installing dependencies       [..]\r'

  if [ -n "$SKIP_DEPS" ]; then
    echo -ne " Installing dependencies       [${CYELLOW}SKIPPED${CEND}]\\r"
    echo ""

    return
  fi

  if {
    if [ -f "$SOURCE_LIST" ]; then
      rm "$SOURCE_LIST"
    fi

    # Allow installation of source files
    {
      if [[ "${OS_DISTRO,,}" == *"ubuntu"* ]]; then
        if [[ "${OS_ARCH}" == "aarch64" ]]; then
          echo 'deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ '"$OS_SHORT_CODENAME"' main restricted'
          echo 'deb-src [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ '"$OS_SHORT_CODENAME"' main restricted universe multiverse'

          if [ -z "$BACKPORTS" ]; then
            echo 'deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ '"$OS_SHORT_CODENAME"'-backports main restricted universe multiverse'
            echo 'deb-src [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ '"$OS_SHORT_CODENAME"'-backports main restricted universe multiverse'
          fi
        else
          echo 'deb http://archive.ubuntu.com/ubuntu '"$OS_SHORT_CODENAME"' main restricted'
          echo 'deb-src http://archive.ubuntu.com/ubuntu '"$OS_SHORT_CODENAME"' main restricted universe multiverse'

          if [ -z "$BACKPORTS" ]; then
            echo 'deb http://archive.ubuntu.com/ubuntu '"$OS_SHORT_CODENAME"'-backports main restricted universe multiverse'
            echo 'deb-src http://archive.ubuntu.com/ubuntu '"$OS_SHORT_CODENAME"'-backports main restricted universe multiverse'
          fi
        fi
      elif [[ "${OS_DISTRO,,}" == *"debian"* ]]; then
        if [[ "${OS_ARCH}" == "aarch64" ]]; then
          echo 'deb [arch=arm64] http://deb.debian.org/debian '"$OS_SHORT_CODENAME"' main contrib non-free'
          echo 'deb-src [arch=arm64] http://deb.debian.org/debian '"$OS_SHORT_CODENAME"' main contrib non-free'

          if [ -z "$BACKPORTS" ]; then
            echo 'deb [arch=arm64] http://deb.debian.org/debian '"$OS_SHORT_CODENAME"'-backports main contrib non-free'
            echo 'deb-src [arch=arm64] http://deb.debian.org/debian '"$OS_SHORT_CODENAME"'-backports main contrib non-free'
          fi
        else
          echo 'deb http://deb.debian.org/debian '"$OS_SHORT_CODENAME"' main contrib non-free'
          echo 'deb-src http://deb.debian.org/debian '"$OS_SHORT_CODENAME"' main contrib non-free'

          if [ -z "$BACKPORTS" ]; then
            echo 'deb http://deb.debian.org/debian '"$OS_SHORT_CODENAME"'-backports main contrib non-free'
            echo 'deb-src http://deb.debian.org/debian '"$OS_SHORT_CODENAME"'-backports main contrib non-free'
          fi
        fi
      elif [[ "${OS_DISTRO,,}" == *"raspbian"* ]]; then
        if [[ "${OS_ARCH}" == "aarch64" ]]; then
          echo 'deb [arch=arm64] http://archive.raspbian.org/raspbian '"$OS_SHORT_CODENAME"' main contrib non-free'
          echo 'deb-src [arch=arm64] http://archive.raspbian.org/raspbian '"$OS_SHORT_CODENAME"' main contrib non-free'

          if [ -z "$BACKPORTS" ]; then
            echo 'deb [arch=arm64] http://archive.raspbian.org/raspbian '"$OS_SHORT_CODENAME"'-backports main contrib non-free'
            echo 'deb-src [arch=arm64] http://archive.raspbian.org/raspbian '"$OS_SHORT_CODENAME"'-backports main contrib non-free'
          fi
        else
          echo 'deb http://archive.raspbian.org/raspbian '"$OS_SHORT_CODENAME"' main contrib non-free'
          echo 'deb-src http://archive.raspbian.org/raspbian '"$OS_SHORT_CODENAME"' main contrib non-free'

          if [ -z "$BACKPORTS" ]; then
            echo 'deb http://archive.raspbian.org/raspbian '"$OS_SHORT_CODENAME"'-backports main contrib non-free'
            echo 'deb-src http://archive.raspbian.org/raspbian '"$OS_SHORT_CODENAME"'-backports main contrib non-free'
          fi
        fi
      else
        SKIP_BUILD_DEP="yes"
      fi
    } >>"$SOURCE_LIST"

    # Update package list and satisfy build dependencies for imagemagick
    apt-get update -qq
    
    if [ -n "$SKIP_BUILD_DEP" ]; then
      apt-get build-dep -qq imagemagick -y
    fi

    # Install minimum build dependencies
    PKG_LIST=(git curl make cmake automake libtool yasm g++ pkg-config perl)

    if [ -n "$CHECKINSTALL" ]; then
      PKG_LIST+=(checkinstall)
    fi

    apt-get install -y "${PKG_LIST[@]}"

    # Install imagemagick + delegates build dependencies
    PKG_LIST=(libde265-dev libx265-dev libltdl-dev libopenjp2-7-dev liblcms2-dev libbrotli-dev libzip-dev libbz2-dev liblqr-1-0-dev libzstd-dev libgif-dev libjpeg-dev libopenexr-dev libpng-dev libwebp-dev librsvg2-dev libwmf-dev libxml2-dev libxml2 libtiff-dev libraw-dev ghostscript gsfonts ffmpeg libpango1.0-dev libdjvulibre-dev libfftw3-dev libgs-dev libgraphviz-dev)

    if [[ "${OS_SHORT_CODENAME,,}" != *"stretch"* && "${OS_SHORT_CODENAME,,}" != *"xenial"* ]]; then
      PKG_LIST+=(libraqm-dev libraqm0)
    fi

    apt-get install -y "${PKG_LIST[@]}"

    CMAKE_VERSION=$(cmake --version | head -n1 | cut -d" " -f3)
  } >>"$LOG_FILE" 2>&1; then
    echo -ne " Installing dependencies       [${CGREEN}OK${CEND}]\\r"
    echo ""
  else
    echo -ne " Installing dependencies       [${CRED}FAILURE${CEND}]\\r"
    echo ""
    echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
    echo ""

    exit 1
  fi
}

# Build aom
install_aom() {
  cd "$WORK_DIR" || exit 1

  if {
    echo -ne ' Building aom                  [..]\r'

    if [ "$(version "$CMAKE_VERSION")" -lt "$(version 3.6)" ]; then
      echo -ne " Building aom                  [${CYELLOW}SKIPPED (CMAKE version $CMAKE_VERSION not sufficient)${CEND}]\\r"
      echo ""

      return
    fi

    if [ -z "$SKIP_AOM" ] && [ -z "$SKIP_LIBHEIF" ]; then
      if [ -z "$FORCE" ] && [ -n "$INSTALLED_AOM_VER" ] && [ "$(version "$INSTALLED_AOM_VER")" -ge "$(version "$AOM_VER")" ]; then
        echo -ne " Building aom                  [${CYELLOW}SKIPPED${CEND}]\\r"
        echo ""

        return
      fi
    else
      echo -ne " Building aom                  [${CYELLOW}SKIPPED${CEND}]\\r"
      echo ""

      return
    fi

    {
      if [ -n "$AOM_VER" ]; then
        httpGet "$GH_FILE_BASE/SoftCreatR/aom/tar.gz/v$AOM_VER" >"aom-$AOM_VER.tar.gz"

        if [ -n "$AOM_HASH" ]; then
          if [ "$(sha1sum "aom-$AOM_VER.tar.gz" | cut -b-40)" != "$AOM_HASH" ]; then
            echo -ne " Building aom                  [${CRED}FAILURE${CEND}]\\r"
            echo ""
            echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
            echo ""
          fi
        fi

        # see https://github.com/SoftCreatR/imei/issues/9
        CMAKE_FLAGS=(-DBUILD_SHARED_LIBS=1 -DENABLE_DOCS=0 -DENABLE_TESTS=0 -DENABLE_CCACHE=1)

        if [[ "${OS_DISTRO,,}" == *"raspbian"* ]]; then
          CMAKE_FLAGS+=(-DCMAKE_C_FLAGS="-mfloat-abi=hard -march=armv7-a -marm -mfpu=neon")
        fi

        tar -xf "aom-$AOM_VER.tar.gz" &&
          mkdir "$WORK_DIR/build_aom" &&
          cd "$WORK_DIR/build_aom" &&
          cmake "../aom-$AOM_VER/" "${CMAKE_FLAGS[@]}" &&
          make

        if [ -n "$CHECKINSTALL" ]; then
          echo "AV1 Video Codec Library (IMEI v$INSTALLER_VER)" >>description-pak &&
            checkinstall \
              --default \
              --nodoc \
              --pkgname="imei-libaom" \
              --pkglicense="BSD-2-Clause" \
              --pkgversion="$AOM_VER" \
              --pkgrelease="imei$INSTALLER_VER" \
              --pakdir="$BUILD_DIR" \
              --provides="libaom3 \(= $AOM_VER\)" \
              --fstrans=no \
              --backup=no \
              --deldoc=yes \
              --deldesc=yes \
              --delspec=yes \
              --install="${INSTALL:-"yes"}"

              if [ -n "$INSTALL" ]; then
                make uninstall
              fi
        else
          make install
        fi

        ldconfig $LIB_DIR
      fi
    } >>"$LOG_FILE" 2>&1
  }; then
    UPDATE_LIBHEIF="yes"

    echo -ne " Building aom                  [${CGREEN}OK${CEND}]\\r"
    echo ""
  else
    echo -ne " Building aom                  [${CRED}FAILURE${CEND}]\\r"
    echo ""
    echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
    echo ""

    exit 1
  fi
}

# Build libheif
install_libheif() {
  IM_HEIC="without"

  cd "$WORK_DIR" || exit 1

  if {
    echo -ne ' Building libheif              [..]\r'

    if [ -z "$SKIP_LIBHEIF" ]; then
      if [ -z "$FORCE" ] && [ -z "$UPDATE_LIBHEIF" ] && [ -n "$INSTALLED_LIBHEIF_VER" ] && [ "$(version "$INSTALLED_LIBHEIF_VER")" -ge "$(version "$LIBHEIF_VER")" ]; then
        echo -ne " Building libheif              [${CYELLOW}SKIPPED${CEND}]\\r"
        echo ""

        return
      fi
    else
      echo -ne " Building libheif              [${CYELLOW}SKIPPED${CEND}]\\r"
      echo ""

      return
    fi

    if [ ! -L "$LIB_DIR/lib/libaom.so" ]; then
      echo -ne " Building libheif              [${CYELLOW}SKIPPED (aom is required but not installed)${CEND}]\\r"
      echo ""

      return
    fi

    {
      if [ -n "$LIBHEIF_VER" ]; then
        httpGet "$GH_FILE_BASE/strukturag/libheif/tar.gz/v$LIBHEIF_VER" >"libheif-$LIBHEIF_VER.tar.gz"

        if [ -n "$LIBHEIF_HASH" ]; then
          if [ "$(sha1sum "libheif-$LIBHEIF_VER.tar.gz" | cut -b-40)" != "$LIBHEIF_HASH" ]; then
            echo -e " Building libheif              [${CRED}FAILURE${CEND}]\\r"
            echo ""
            echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
            echo ""
          fi
        fi

        # see https://github.com/SoftCreatR/imei/issues/78
        if [ "$(version "$LIBHEIF_VER")" -lt "$(version 1.16.0)" ]; then
          tar -xf "libheif-$LIBHEIF_VER.tar.gz" &&
            cd "libheif-$LIBHEIF_VER" &&
            ./autogen.sh &&
            ./configure &&
            make
        else
          tar -xf "libheif-$LIBHEIF_VER.tar.gz" &&
            cd "libheif-$LIBHEIF_VER" &&
            mkdir build &&
            cd build &&
            cmake --preset=release ..
          make
        fi

        if [ -n "$CHECKINSTALL" ]; then
          echo "ISO/IEC 23008-12:2017 HEIF file format decoder (IMEI v$INSTALLER_VER)" >>description-pak &&
            checkinstall \
              --default \
              --nodoc \
              --pkgname="imei-libheif" \
              --pkglicense="GPL-2.0-or-later" \
              --pkgversion="$LIBHEIF_VER" \
              --pkgrelease="imei$INSTALLER_VER" \
              --pakdir="$BUILD_DIR" \
              --requires="libde265-dev,libx265-dev,imei-libaom" \
              --provides="libheif1 \(= $LIBHEIF_VER\)" \
              --fstrans=no \
              --backup=no \
              --deldoc=yes \
              --deldesc=yes \
              --delspec=yes \
              --install="${INSTALL:-"yes"}"

              if [ -n "$INSTALL" ]; then
                make uninstall
              fi
        else
          make install
        fi

        ldconfig $LIB_DIR
      fi
    } >>"$LOG_FILE" 2>&1
  }; then
    UPDATE_IMAGEMAGICK="yes"
    IM_HEIC="with"

    echo -ne " Building libheif              [${CGREEN}OK${CEND}]\\r"
    echo ""
  else
    echo -e " Building libheif              [${CRED}FAILURE${CEND}]\\r"
    echo ""
    echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
    echo ""

    exit 1
  fi
}

# Build JPEG XL
install_jxl() {
  IM_JXL="without"

  cd "$WORK_DIR" || exit 1

  if {
    echo -ne ' Building jpegxl               [..]\r'

    if [ "$(version "$CMAKE_VERSION")" -lt "$(version 3.10)" ]; then
      echo -ne " Building jpegxl               [${CYELLOW}SKIPPED (CMAKE version $CMAKE_VERSION not sufficient)${CEND}]\\r"
      echo ""

      return
    fi

    if [ -z "$SKIP_JXL" ]; then
      if [ -z "$FORCE" ] && [ -z "$UPDATE_LIBHEIF" ] && [ -n "$INSTALLED_JXL_VER" ] && [ "$(version "$INSTALLED_JXL_VER")" -ge "$(version "$JXL_VER")" ]; then
        echo -ne " Building jpegxl               [${CYELLOW}SKIPPED${CEND}]\\r"
        echo ""

        return
      fi
    else
      echo -ne " Building jpegxl               [${CYELLOW}SKIPPED${CEND}]\\r"
      echo ""

      return
    fi

    {
      if [ -n "$JXL_VER" ]; then
        httpGet "$GH_FILE_BASE/libjxl/libjxl/tar.gz/v$JXL_VER" >"libjxl-$JXL_VER.tar.gz"

        if [ -n "$JXL_HASH" ]; then
          if [ "$(sha1sum "libjxl-$JXL_VER.tar.gz" | cut -b-40)" != "$JXL_HASH" ]; then
            echo -e " Building jpegxl               [${CRED}FAILURE${CEND}]\\r"
            echo ""
            echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
            echo ""
          fi
        fi

        tar -xf "libjxl-$JXL_VER.tar.gz" &&
          cd "libjxl-$JXL_VER"
          
          # 45e552880a862c56ab3b356b8ff28c0b0ff8ac94@libjxl
          # shellcheck disable=SC2016
          sed -i 's/varname="\${varname\/\[\\\/-\]\/_}"/varname="\${varname\/\/\[\\\/-\]\/_}"/' ./deps.sh

          ./deps.sh &&
          mkdir "build" &&
          cd "build" &&
          cmake -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF .. &&
          cmake --build .

        if [ -n "$CHECKINSTALL" ]; then
          echo "JPEG XL image format reference implementation (IMEI v$INSTALLER_VER)" >>description-pak &&
            checkinstall \
              --default \
              --nodoc \
              --pkgname="imei-libjxl" \
              --pkglicense="Apache-2.0" \
              --pkgversion="$JXL_VER" \
              --pkgrelease="imei$INSTALLER_VER" \
              --pakdir="$BUILD_DIR" \
              --requires="libgif7,libjpeg-dev,libopenexr-dev,libbrotli-dev" \
              --provides="libjxl$JXL_VER \(= $JXL_VER\)" \
              --fstrans=no \
              --backup=no \
              --deldoc=yes \
              --deldesc=yes \
              --delspec=yes \
              --install="${INSTALL:-"yes"}"

              if [ -n "$INSTALL" ]; then
                make uninstall
              fi
        else
          cmake --install .
        fi

        ldconfig $LIB_DIR
      fi
    } >>"$LOG_FILE" 2>&1
  }; then
    UPDATE_IMAGEMAGICK="yes"
    IM_JXL="with"

    echo -ne " Building jpegxl               [${CGREEN}OK${CEND}]\\r"
    echo ""
  else
    echo -e " Building jpegxl               [${CRED}FAILURE${CEND}]\\r"
    echo ""
    echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
    echo ""

    exit 1
  fi
}

# Build ImageMagick
install_imagemagick() {
  cd "$WORK_DIR" || exit 1

  if {
    if [ "$QUANTUM_DEPTH" -eq 8 ]; then
      echo -ne ' Building ImageMagick (Q'"$QUANTUM_DEPTH"')     [..]\r'
    else
      echo -ne ' Building ImageMagick (Q'"$QUANTUM_DEPTH"')    [..]\r'
    fi

    if [ -z "$FORCE" ] && [ -z "$FORCE_IMAGEMAGICK" ] && [ -z "$UPDATE_IMAGEMAGICK" ] && [ -n "$INSTALLED_IMAGEMAGICK_VER" ] && [ "$(version "${INSTALLED_IMAGEMAGICK_VER//-/}")" -ge "$(version "${IMAGEMAGICK_VER//-/}")" ]; then
      if [ "$QUANTUM_DEPTH" -eq 8 ]; then
        echo -ne " Building ImageMagick (Q$QUANTUM_DEPTH)     [${CYELLOW}SKIPPED${CEND}]\\r"
      else
        echo -ne " Building ImageMagick (Q$QUANTUM_DEPTH)    [${CYELLOW}SKIPPED${CEND}]\\r"
      fi

      echo ""

      return
    fi

    {
      if [ -n "$IMAGEMAGICK_VER" ]; then
        DIR_SUFFIX=""
        MAIN_VER="7"

        if [ "$(echo "$IMAGEMAGICK_VER" | cut -b-1)" -eq 6 ]; then
          DIR_SUFFIX="6"
          MAIN_VER="6"

          httpGet "$GH_FILE_BASE/ImageMagick/ImageMagick6/tar.gz/$IMAGEMAGICK_VER" >"ImageMagick-$IMAGEMAGICK_VER.tar.gz"
        else
          httpGet "$GH_FILE_BASE/ImageMagick/ImageMagick/tar.gz/$IMAGEMAGICK_VER" >"ImageMagick-$IMAGEMAGICK_VER.tar.gz"
        fi

        if [ -n "$IMAGEMAGICK_HASH" ]; then
          if [ "$(sha1sum "ImageMagick-$IMAGEMAGICK_VER.tar.gz" | cut -b-40)" != "$IMAGEMAGICK_HASH" ]; then
            if [ "$QUANTUM_DEPTH" -eq 8 ]; then
              echo -e " Building ImageMagick (Q$QUANTUM_DEPTH)     [${CRED}FAILURE${CEND}]\\r"
            else
              echo -e " Building ImageMagick (Q$QUANTUM_DEPTH)    [${CRED}FAILURE${CEND}]\\r"
            fi

            echo ""
            echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
            echo ""
          fi
        fi

        # see https://github.com/SoftCreatR/imei/issues/69
        if [ -n "$USE_OPENCL" ]; then
          OPENCL_C="disable"
        else
          OPENCL_C="enable"
        fi

        # see https://github.com/SoftCreatR/imei/issues/100
        if [ -n "$BUILD_STATIC" ]; then
          STATIC_C="enable"
          SHARED_C="disable"
        else
          STATIC_C="disable"
          SHARED_C="enable"
        fi

        tar -xf "ImageMagick-$IMAGEMAGICK_VER.tar.gz" &&
          cd "ImageMagick$DIR_SUFFIX-$IMAGEMAGICK_VER" &&
          ./configure --prefix="$BUILD_DIR" --sysconfdir="$CONFIG_DIR" \
            CFLAGS="$BUILD_CFLAGS" \
            CXXFLAGS="$BUILD_CXXFLAGS" \
            --${STATIC_C}-static \
            --${SHARED_C}-shared \
            --enable-openmp \
            --enable-cipher \
            --enable-hdri \
            --enable-docs \
            --${OPENCL_C}-opencl \
            --with-threads \
            --with-modules \
            --with-quantum-depth="$QUANTUM_DEPTH" \
            --with-magick-plus-plus \
            --with-perl \
            --without-jemalloc \
            --without-tcmalloc \
            --without-umem \
            --without-autotrace \
            --with-bzlib \
            --with-x \
            --with-zlib \
            --with-zstd \
            --without-dps \
            --with-fftw \
            --without-flif \
            --without-fpx \
            --with-djvu \
            --with-fontconfig \
            --with-freetype \
            --with-raqm \
            --with-gslib \
            --with-gvc \
            --${IM_HEIC}-heic \
            --with-jbig \
            --with-jpeg \
            --${IM_JXL}-jxl \
            --with-lcms \
            --with-openjp2 \
            --with-lqr \
            --with-lzma \
            --with-openexr \
            --with-pango \
            --with-png \
            --with-raw \
            --with-rsvg \
            --with-tiff \
            --with-webp \
            --with-wmf \
            --with-xml \
            --with-dejavu-font-dir='/usr/share/fonts/truetype/ttf-dejavu' \
            --with-gs-font-dir='/usr/share/fonts/type1/gsfonts' \
            --with-urw-base35-font-dir='/usr/share/fonts/type1/urw-base35' \
            --with-fontpath='/usr/share/fonts/type1' \
            PSDelegate='/usr/bin/gs' &&
          make

        if [ -n "$CHECKINSTALL" ]; then
          REQUIRES="libraqm0,libgomp1,libfftw3-dev,liblcms2-2,libfontconfig1,libxext6,libltdl7,liblqr-1-0-dev,webp\|libwebp-dev,libjpeg-dev,libzip-dev,libice-dev,libsm-dev,libxml2\|libxml2-dev"
          RECOMMENDS=""

          if [ "$IM_HEIC" == "with" ]; then
            REQUIRES="${REQUIRES},imei-libaom,imei-libheif"
          else
            RECOMMENDS="${RECOMMENDS:+$RECOMMENDS,}imei-libaom,imei-libheif"
          fi

          if [ "$IM_JXL" == "with" ]; then
            REQUIRES="${REQUIRES},imei-libaom,imei-libjxl"
          else
            RECOMMENDS="${RECOMMENDS:+$RECOMMENDS,}imei-libaom,imei-libjxl"
          fi

          if [ "$IM_HEIC" == "without" ] && [ "$IM_JXL" == "without" ]; then
            REQUIRES="${REQUIRES//,imei-libaom/}"
          else
            RECOMMENDS="${RECOMMENDS//imei-libaom,/}"
          fi

          echo "image manipulation programs (IMEI v$INSTALLER_VER)" >>description-pak &&
            checkinstall \
              --default \
              --nodoc \
              --pkgname=imei-imagemagick \
              --pkglicense="Apache-2.0" \
              --pkgversion="$IMAGEMAGICK_VER" \
              --pkgrelease="imei$INSTALLER_VER" \
              --pakdir="$BUILD_DIR" \
              --conflicts="imagemagick" \
              --requires="${REQUIRES}" \
              --recommends="${RECOMMENDS}" \
              --provides="imagemagick \(= $IMAGEMAGICK_VER\),imagemagick-$MAIN_VER.q$QUANTUM_DEPTH \(= $IMAGEMAGICK_VER\),libmagickcore-$MAIN_VER.q$QUANTUM_DEPTH \(= $IMAGEMAGICK_VER\),libmagickwand-$MAIN_VER.q$QUANTUM_DEPTH \(= $IMAGEMAGICK_VER\)" \
              --fstrans=no \
              --backup=no \
              --deldoc=yes \
              --deldesc=yes \
              --delspec=yes \
              --install="${INSTALL:-"yes"}"
        else
          make install
        fi

        ldconfig $LIB_DIR
      fi
    } >>"$LOG_FILE" 2>&1
  }; then
    if [ "$QUANTUM_DEPTH" -eq 8 ]; then
      echo -ne " Building ImageMagick (Q$QUANTUM_DEPTH)     [${CGREEN}OK${CEND}]\\r"
    else
      echo -ne " Building ImageMagick (Q$QUANTUM_DEPTH)    [${CGREEN}OK${CEND}]\\r"
    fi

    echo ""
  else
    if [ "$QUANTUM_DEPTH" -eq 8 ]; then
      echo -e " Building ImageMagick (Q$QUANTUM_DEPTH)    [${CRED}FAILURE${CEND}]\\r"
    else
      echo -e " Building ImageMagick (Q$QUANTUM_DEPTH)   [${CRED}FAILURE${CEND}]\\r"
    fi

    echo ""
    echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
    echo ""

    exit 1
  fi
}

finish_installation() {
  echo -ne ' Verifying installation        [..]\r'

  if [ -z "$INSTALL" ]; then
    # Check if ImageMagick version matches
    {
      VERIFY_INSTALLATION=$("$BUILD_DIR/bin/identify" -version | grep -oP "$IMAGEMAGICK_VER")
    } >>"$LOG_FILE" 2>&1

    if [ -n "$VERIFY_INSTALLATION" ]; then
      echo -ne " Verifying installation        [${CGREEN}OK${CEND}]\\r"
      echo ""
      echo ""
      echo -e " ${CBLUE}Process has been finished successfully after $(displaytime $(($(date +%s) - START)))!${CEND}"
      echo ""
    else
      echo -ne " Verifying installation        [${CRED}FAILURE${CEND}]\\r"
      echo ""
      echo ""
      echo -e " ${CRED}Please check $LOG_FILE for details.${CEND}"
      echo ""
      echo -e " ${CBLUE}Process has been finished after $(displaytime $(($(date +%s) - START)))!${CEND}"
      echo ""
    fi
  else
    echo -ne " Verifying installation        [${CYELLOW}SKIPPED (Checkinstall is set to build-only)${CEND}]\\r"
    echo ""
    echo ""
    echo -e " ${CBLUE}Process has been finished after $(displaytime $(($(date +%s) - START)))!${CEND}"
    echo ""
  fi
}

######################
# Install everything #
######################

#echo -ne "\ec"
echo -ne "\033c"

WELCOME_TXT="Welcome to IMEI - ImageMagick Easy Install ${INSTALLER_VER}"
WELCOME_LEN=${#WELCOME_TXT}

echo ""
echo " $(str_repeat "$WELCOME_LEN" "#")"
echo " $WELCOME_TXT"
echo " $(str_repeat "$WELCOME_LEN" "#")"
echo ""

if [ -z "$CI_BUILD" ] && [ -n "$INSTALLER_VER" ] && [ "$(version "$INSTALLER_VER")" -lt "$(version "$INSTALLER_LATEST_VER")" ]; then
  echo -e " ${CYELLOW}A newer installer version ($INSTALLER_LATEST_VER) is available!${CEND}"
  echo ""
fi

echo " Detected OS     : $OS_DISTRO"
echo " Detected Arch   : $OS_ARCH"
echo " Detected Cores  : $NUM_CORES"
echo ""
echo " Used web client : $CLIENT"
echo ""
echo " Work Dir        : $WORK_DIR"
echo " Build Dir       : $BUILD_DIR"
echo " Config Dir      : $CONFIG_DIR"
echo " Log File        : $LOG_FILE"
echo ""
echo " Force Build All : ${FORCE:-"no"}"
echo " Force Build IM  : ${FORCE_IMAGEMAGICK:-"no"}"
echo " Checkinstall    : ${CHECKINSTALL:-"no"}"
echo " CI Build        : ${CI_BUILD:-"no"}"
echo " Signature Check : ${VERIFY_SIGNATURE:-"yes"}"
echo ""

if [ -n "$CI_BUILD" ]; then
  echo " ####################"
  echo " Version Information"
  echo " ####################"
  echo ""
  echo " libaom Version  : $AOM_VER"
  echo " libheif Version : $LIBHEIF_VER"
  echo " libjxl Version  : $JXL_VER"
  echo " IM Version      : $IMAGEMAGICK_VER"
  echo ""
fi

echo " #####################"
echo " Installation Process"
echo " #####################"
echo ""

# Run installer functions
install_deps
install_aom
install_libheif
install_jxl
install_imagemagick
finish_installation

exit 0
