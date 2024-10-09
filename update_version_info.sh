#!/usr/bin/env bash

WORKDIR=$(dirname "$0")
GH_FILE_BASE="https://codeload.github.com"
GL_FILE_BASE="https://gitlab.com"
CLIENT=""

###
# Functions
###

getClient() {
  for cmd in curl wget httpie; do
    if command -v "$cmd" &>/dev/null; then
      CLIENT="$cmd"
      break
    fi
  done

  if [ -z "$CLIENT" ]; then
    echo "Error: This tool requires either curl, wget, or httpie to be installed." >&2
    return 1
  fi
}

httpGet() {
  case "$CLIENT" in
  curl) curl -A curl -s "$@" ;;
  wget) wget -qO- "$@" ;;
  httpie) http -b GET "$@" ;;
  esac
}

sanitizeVersion() {
  echo "${1//[^0-9\-.]/}"
}

getLatestVersion() {
  local REPO="$1"
  local TAG_PATTERN="$2"
  local PLATFORM="$3"
  local VERSION=""
  local BASE_URL=""

  if [ "$PLATFORM" = "github" ]; then
    BASE_URL="https://github.com"
  elif [ "$PLATFORM" = "gitlab" ]; then
    BASE_URL="https://gitlab.com"
  else
    echo "Error: Unsupported PLATFORM '$PLATFORM' in getLatestVersion." >&2
    exit 1
  fi

  VERSION=$(git ls-remote --tags --sort="v:refname" --refs "$BASE_URL/$REPO.git" | awk -F/ '{print $NF}' | grep -oE "$TAG_PATTERN" | sort -rV | head -1)

  if [ -z "$VERSION" ]; then
    echo "Error: Failed to get VERSION information for $REPO." >&2
    exit 1
  fi

  echo "$VERSION"
}

getTarballHash() {
  local REPO="$1"
  local VERSION="$2"
  local PLATFORM="$3"
  local HASH=""
  local URL=""

  if [ "$PLATFORM" = "github" ]; then
    URL="$GH_FILE_BASE/$REPO/tar.gz/$VERSION"
  elif [ "$PLATFORM" = "gitlab" ]; then
    URL="$GL_FILE_BASE/$REPO/-/archive/$VERSION/$REPO-$VERSION.tar.gz"
  else
    echo "Error: Unsupported PLATFORM '$PLATFORM' in getTarballHash." >&2
    exit 1
  fi

  HASH=$(httpGet "$URL" | sha1sum | cut -b-40)

  if [ -z "$HASH" ]; then
    echo "Error: Failed to get hash information for $REPO $VERSION tarball." >&2
    exit 1
  fi

  echo "$HASH"
}

getVersionInfoAndWriteToFile() {
  local REPO="$1"
  local TAG_PATTERN="$2"
  local VERSION_FILE="$3"
  local HASH_FILE="$4"
  local PLATFORM="$5"

  VERSION=$(getLatestVersion "$REPO" "$TAG_PATTERN" "$PLATFORM")

  if [ -z "$VERSION" ]; then
    echo "Error: Failed to get version information for $REPO." >&2
    exit 1
  fi

  sanitized_version=$(sanitizeVersion "$VERSION")
  echo "$sanitized_version" >"$VERSION_FILE"

  HASH=$(getTarballHash "$REPO" "$VERSION" "$PLATFORM")

  if [ -z "$HASH" ]; then
    echo "Error: Failed to get hash information for $REPO $VERSION tarball." >&2
    exit 1
  fi

  echo "$HASH" >"$HASH_FILE"

  echo "$VERSION"
}

###
# Main
###

if ! getClient; then
  exit 1
fi

# Get version information and write it to files
IMAGEMAGICK_VER=$(getVersionInfoAndWriteToFile "ImageMagick/ImageMagick" '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$' "$WORKDIR/versions/imagemagick.version" "$WORKDIR/versions/imagemagick.hash" "github")
LIBAOM_VER=$(getVersionInfoAndWriteToFile "jbeich/aom" '^v[0-9]+\.[0-9]+\.[0-9]+$' "$WORKDIR/versions/aom.version" "$WORKDIR/versions/aom.hash" "github")
LIBHEIF_VER=$(getVersionInfoAndWriteToFile "strukturag/libheif" '^v[0-9]+\.[0-9]+\.[0-9]+$' "$WORKDIR/versions/libheif.version" "$WORKDIR/versions/libheif.hash" "github")
LIBJXL_VER=$(getVersionInfoAndWriteToFile "libjxl/libjxl" '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' "$WORKDIR/versions/libjxl.version" "$WORKDIR/versions/libjxl.hash" "github")
SVT_VER=$(getVersionInfoAndWriteToFile "AOMediaCodec/SVT-AV1" '^v[0-9]+\.[0-9]+\.[0-9]+$' "$WORKDIR/versions/svt.version" "$WORKDIR/versions/svt.hash" "gitlab")

# Update README file
REPLACEMENT="\n* ImageMagick version: \`$(sanitizeVersion "$IMAGEMAGICK_VER") (Q16)\`\n"
REPLACEMENT+="* libaom version: \`$(sanitizeVersion "$LIBAOM_VER")\`\n"
REPLACEMENT+="* libheif version: \`$(sanitizeVersion "$LIBHEIF_VER")\`\n"
REPLACEMENT+="* libjxl version: \`$(sanitizeVersion "$LIBJXL_VER")\`\n"
REPLACEMENT+="* SVT-AV1 version: \`$(sanitizeVersion "$SVT_VER")\`"
sed -En '1h;1!H;${g;s/(<!-- versions start -->)(.*)(<!-- versions end -->)/\1'"$REPLACEMENT"'\3/;p;}' -i "$WORKDIR/README.md"

exit 0
