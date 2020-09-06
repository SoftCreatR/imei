#!/usr/bin/env bash

##############################################################
# Title          : IMEI - ImageMagick Easy Install           #
# Description    : ImageMagick® for Debian/Ubuntu,           #
#                  including advanced delegate support.      #
#                                                            #
# Author         : Sascha Greuel <hello@1-2.dev>             #
# Date           : 2020-09-06 19:15                          #
# License        : MIT                                       #
# Version        : 4.3.4                                     #
#                                                            #
# Usage          : bash imei.sh                              #
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
  apt-get install -qq lsb-release >/dev/null 2>&1
fi

# Check if required packages are installed or install them
required_packages="wget jq"

for package in $required_packages; do
  if ! command_exists "$package"; then
    apt-get install -qq "$package" >/dev/null 2>&1
  fi
done

####################
# Script arguments #
####################

while [ "$#" -gt 0 ]; do
  case "$1" in
  --imagemagick-version)
    IMAGEMAGICK_VER=$2
    ;;
  --aom-version)
    AOM_VER=$2
    ;;
  --libheif-version)
    LIBHEIF_VER=$2
    ;;
  --log-file)
    LOG_FILE=$2
    ;;
  --work-dir)
    WORK_DIR=$2
    ;;
  --travis)
    TRAVIS_BUILD="1"
    ;;
  *) ;;
  esac
  shift
done

export DEBIAN_FRONTEND=noninteractive

#############
# Variables #
#############

START=$(date +%s)
OS_DISTRO="$(lsb_release -ds)"
OS_ARCH="$(uname -m)"

if [ -f "$0" ]; then
  INSTALLER_VER=$(grep -oP 'Version\s+:\s+\K([\d\.]+)' "$0")
  INSTALLER_LATEST_VER=$(wget -qO- "https://1-2.dev/imei" | grep -oP 'Version\s+:\s+\K([\d\.]+)')
fi

if [ -z "$WORK_DIR" ]; then
  WORK_DIR=/usr/local/src/imei
fi

if [ -z "$LOG_FILE" ]; then
  LOG_FILE=/var/log/install-imagemagick.log
fi

if [ -z "$IMAGEMAGICK_VER" ]; then
  IMAGEMAGICK_VER=$(
    wget -qO- "https://api.github.com/repos/ImageMagick/ImageMagick/releases/latest" |
      grep -oP '"tag_name": "\K.*?(?=")' |
      sed 's/v//'
  )
fi

if [ -z "$AOM_VER" ]; then
  AOM_VER=$(
    wget -qO- "https://api.github.com/repos/jbeich/aom/tags" |
      jq -r '.[0].name' |
      cut -c2-
  )
fi

if [ -z "$LIBHEIF_VER" ]; then
  LIBHEIF_VER=$(
    wget -qO- "https://api.github.com/repos/strukturag/libheif/releases/latest" |
      grep -oP '"tag_name": "\K.*?(?=")' |
      sed 's/v//'
  )
fi

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
}

########
# Init #
########

# Display execution time and clean up on exit
trap cleanup 0 1 2 3 6 15

# Clean up on execution
cleanup

if [ -f "$LOG_FILE" ]; then
  rm "$LOG_FILE"
fi

# Create working directory
[ ! -d "$WORK_DIR" ] && mkdir -p "$WORK_DIR"

# Check if working directory was created
if [[ ! "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
  echo -e "${CRED}Could not create temp directory $WORK_DIR${CEND}"

  exit 1
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

#######################
# Installer functions #
#######################

# Speed up the compilation process
NUM_CORES=$(nproc || echo 1)
export MAKEFLAGS="-j$((NUM_CORES + 1)) -l${NUM_CORES}"

# Build dependencies
install_deps() {
  echo -ne ' Installing dependencies       [..]\r'

  if {
    # Update package list
    if [ -z "$TRAVIS_BUILD" ]; then
      apt-get update -qq
    fi

    # Allow installation of source files
    sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list

    # Satisfy build dependencies for imagemagick
    apt-get build-dep -qq imagemagick -y

    # Install build dependencies
    apt-get install git make cmake automake yasm g++ pkg-config libde265-dev libx265-dev -y
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

    {
      [ -n "$AOM_VER" ] &&
        wget -c --show-progress "https://github.com/jbeich/aom/archive/v$AOM_VER.tar.gz" \
          -O "aom-$AOM_VER.tar.gz" &&
        tar -xf "aom-$AOM_VER.tar.gz" &&
        mkdir "$WORK_DIR/build_aom" &&
        cd "$WORK_DIR/build_aom" &&
        cmake "../aom-$AOM_VER/" \
          -DENABLE_TESTS=0 \
          -DENABLE_DOCS=0 \
          -DBUILD_SHARED_LIBS=1 \
          -O3 &&
        make &&
        make install &&
        ldconfig
    } >>"$LOG_FILE" 2>&1
  }; then
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
  cd "$WORK_DIR" || exit 1

  if {
    echo -ne ' Building libheif              [..]\r'

    {
      [ -n "$LIBHEIF_VER" ] &&
        wget -c --show-progress "https://github.com/strukturag/libheif/releases/download/v$LIBHEIF_VER/libheif-$LIBHEIF_VER.tar.gz" &&
        tar -xf "libheif-$LIBHEIF_VER.tar.gz" &&
        cd "libheif-$LIBHEIF_VER" &&
        ./configure \
          CFLAGS="-g -O3 -Wall -pthread" \
          --disable-dependency-tracking \
          --disable-examples \
          --disable-go &&
        make install &&
        ldconfig
    } >>"$LOG_FILE" 2>&1
  }; then
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

# Build ImageMagick
install_imagemagick() {
  cd "$WORK_DIR" || exit 1

  if {
    echo -ne ' Building ImageMagick          [..]\r'

    {
      [ -n "$IMAGEMAGICK_VER" ] &&
        wget -c --show-progress "https://github.com/ImageMagick/ImageMagick/archive/$IMAGEMAGICK_VER.tar.gz" \
          -O "ImageMagick-$IMAGEMAGICK_VER.tar.gz" &&
        tar -xf "ImageMagick-$IMAGEMAGICK_VER.tar.gz" &&
        cd "ImageMagick-$IMAGEMAGICK_VER" &&
        ./configure \
          CC=gcc \
          CFLAGS="-O3 -march=native" \
          CXX=g++ \
          CXXFLAGS="-O3 -march=native" \
          --prefix=/usr \
          --without-magick-plus-plus \
          --without-perl \
          --disable-shared \
          --disable-dependency-tracking \
          --disable-docs \
          --with-jemalloc=yes \
          --with-tcmalloc=yes \
          --with-umem=yes \
          --with-heic=yes &&
        make install &&
        ldconfig
    } >>"$LOG_FILE" 2>&1
  }; then
    echo -ne " Building ImageMagick          [${CGREEN}OK${CEND}]\\r"
    echo ""
  else
    echo -e " Building ImageMagick          [${CRED}FAILURE${CEND}]\\r"
    echo ""
    echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
    echo ""

    exit 1
  fi
}

finish_installation() {
  echo -ne ' Verifying installation        [..]\r'

  # Check if ImageMagick version matches
  if command_exists identify; then
    VERIFY_INSTALLATION=$(identify -version | grep -oP "$IMAGEMAGICK_VER")

    if [ -n "$VERIFY_INSTALLATION" ]; then
      echo -ne " Verifying installation        [${CGREEN}OK${CEND}]\\r"
      echo ""
      echo -e " ${CGREEN}ImageMagick was compiled successfully after $(displaytime $(($(date +%s) - START)))!${CEND}"
      echo ""

      setup_cron
    else
      echo -ne " Verifying installation        [${CRED}FAILURE${CEND}]\\r"
      echo ""
      echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
      echo ""
    fi
  else
    echo -ne " Verifying installation        [${CRED}FAILURE${CEND}]\\r"
    echo ""
    echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
    echo ""
  fi
}

setup_cron() {
  if [ -n "$TRAVIS_BUILD" ] || [ -f /etc/cron.daily/imei ]; then
    return
  fi

  while true; do
    read -rp " Do you want to setup IMEI auto-update cronjob? (y/n): " yn </dev/tty

    case $yn in
    [Yy]*)
      CRON_SETUP="y"
      break
      ;;
    [Nn]*)
      return
      ;;
    *)
      echo -e " ${CYELLOW}Please answer yes or no.${CEND}"
      echo ""
      ;;
    esac
  done

  echo ""

  if [ "$CRON_SETUP" = "y" ]; then
    if {
      wget -c --show-progress "https://1-2.dev/imei-cron" \
        -O "/etc/cron.daily/imei" &&
        chmod +x /etc/cron.daily/imei
    } >>"$LOG_FILE" 2>&1; then
      echo -e " Installing IMEI Cronjob       [${CGREEN}OK${CEND}]"
      echo ""
    else
      echo -e " Installing IMEI Cronjob       [${CRED}FAIL${CEND}]"
      echo ""
      echo -e " ${CBLUE}Please check $LOG_FILE for details.${CEND}"
      echo ""

      exit 1
    fi
  fi
}

######################
# Install everything #
######################

clear

WELCOME_TXT="Welcome to IMEI - ImageMagick Easy Install ${INSTALLER_VER}"
WELCOME_LEN=${#WELCOME_TXT}

echo " $(str_repeat "$WELCOME_LEN" "#")"
echo " $WELCOME_TXT"
echo " $(str_repeat "$WELCOME_LEN" "#")"
echo ""

if [ -z "$TRAVIS_BUILD" ] && [ -n "$INSTALLER_VER" ] && [ "$(version "$INSTALLER_VER")" -lt "$(version "$INSTALLER_LATEST_VER")" ]; then
  echo -e " ${CYELLOW}A newer installer version ($INSTALLER_LATEST_VER) is available!${CEND}"
  echo ""
fi

echo " Detected OS    : $OS_DISTRO"
echo " Detected Arch  : $OS_ARCH"
echo " Detected Cores : $NUM_CORES"
echo ""
echo " ImageMagick release : $IMAGEMAGICK_VER"
echo " aom release         : $AOM_VER"
echo " libheif release     : $LIBHEIF_VER"
echo ""
echo " Work Dir : $WORK_DIR"
echo " Log File : $LOG_FILE"
echo ""

echo " #####################"
echo " Installation Process"
echo " #####################"
echo ""

# Run installer functions
install_deps
install_aom
install_libheif
install_imagemagick
finish_installation

exit 0
