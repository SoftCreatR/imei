#!/usr/bin/env bash

WORKDIR=$(dirname "$0")
GH_FILE_BASE="https://codeload.github.com"
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
    curl) curl -A curl -s  "$@" ;;
    wget) wget -qO- "$@" ;;
    httpie) http -b GET "$@" ;;
  esac
}

sanitizeVersion() {
  echo "${1//[^0-9\-.]/}"
}

getLatestVersion() {
  local repo="$1"
  local tag_pattern="$2"

  local version=$(git ls-remote --tags --sort="v:refname" --refs "https://github.com/$repo.git" | awk -F/ '{print $NF}' | grep -oE "$tag_pattern" | sort -rV | head -1)

  if [ -z "$version" ]; then
    echo "Error: Failed to get version information for $repo." >&2
    exit 1
  fi

  echo "$version"
}

getTarballHash() {
  local repo="$1"
  local version="$2"

  local hash=$(httpGet "$GH_FILE_BASE/$repo/tar.gz/$version" | sha1sum | cut -b-40)

  if [ -z "$hash" ]; then
    echo "Error: Failed to get hash information for $repo $version tarball." >&2
    exit 1
  fi

  echo "$hash"
}

getVersionInfoAndWriteToFile() {
  local repo="$1"
  local tag_pattern="$2"
  local version_file="$3"
  local hash_file="$4"

  local version=$(getLatestVersion "$repo" "$tag_pattern")

  if [ -z "$version" ]; then
    echo "Error: Failed to get version information for $repo." >&2
    exit 1
  fi

  local sanitized_version=$(sanitizeVersion "$version")
  echo "$sanitized_version" > "$version_file"

  local hash=$(getTarballHash "$repo" "$version")

  if [ -z "$hash" ]; then
    echo "Error: Failed to get hash information for $repo $version tarball." >&2
    exit 1
  fi

  echo "$hash" > "$hash_file"

  echo "$version"
}

###
# Main
###

if ! getClient; then
  exit 1
fi

# Get version information and write it to files
IMAGEMAGICK_VER=$(getVersionInfoAndWriteToFile "ImageMagick/ImageMagick" '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$' "$WORKDIR/versions/imagemagick.version" "$WORKDIR/versions/imagemagick.hash")
LIBAOM_VER=$(getVersionInfoAndWriteToFile "jbeich/aom" '^v[0-9]+\.[0-9]+\.[0-9]+$' "$WORKDIR/versions/aom.version" "$WORKDIR/versions/aom.hash")
LIBHEIF_VER=$(getVersionInfoAndWriteToFile "strukturag/libheif" '^v[0-9]+\.[0-9]+\.[0-9]+$' "$WORKDIR/versions/libheif.version" "$WORKDIR/versions/libheif.hash")
LIBJXL_VER=$(getVersionInfoAndWriteToFile "libjxl/libjxl" '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' "$WORKDIR/versions/libjxl.version" "$WORKDIR/versions/libjxl.hash")

# Update README file
REPLACEMENT="\n* ImageMagick version: \`$(sanitizeVersion $IMAGEMAGICK_VER) (Q16)\`\n"
REPLACEMENT+="* libaom version: \`$(sanitizeVersion $LIBAOM_VER)\`\n"
REPLACEMENT+="* libheif version: \`$(sanitizeVersion $LIBHEIF_VER)\`\n"
REPLACEMENT+="* libjxl version: \`$(sanitizeVersion $LIBJXL_VER)\`"
sed -En '1h;1!H;${g;s/(<!-- versions start -->)(.*)(<!-- versions end -->)/\1'"$REPLACEMENT"'\3/;p;}' -i "$WORKDIR/README.md"

exit 0
