#!/usr/bin/env bash

# Make sure, that jq is available
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: This tool requires jq to be installed." >&2
  exit 1
fi

WORKDIR=$(dirname "$0")
API_BASE="https://api.github.com/repos"
FILE_BASE="https://codeload.github.com"
CLIENT=""
AUTHORIZATION=""

###
# Helper functions
###
getClient()
{
  if command -v curl &>/dev/null; then
    CLIENT="curl"
  elif command -v wget &>/dev/null; then
    CLIENT="wget"
  elif command -v http &>/dev/null; then
    CLIENT="httpie"
  else
    echo "Error: This tool requires either curl, wget or httpie to be installed." >&2
    return 1
  fi
}

httpGet()
{
  if [[ -n "${GITHUB_TOKEN}" ]]; then
    AUTHORIZATION='{"Authorization": "Bearer '"$GITHUB_TOKEN"'}"}'
  fi

  case "$CLIENT" in
    curl) curl -A curl -s -H "$AUTHORIZATION" "$@" ;;
    wget) wget -qO- --header="$AUTHORIZATION" "$@" ;;
    httpie) http -b GET "$@" "$AUTHORIZATION" ;;
  esac
}
###

if [ -z "$CLIENT" ]; then
  getClient || exit 1
fi

###
# Stuff that looks more complicated
# than it actually is
###

# Get version information for latest stable ImageMagick and write it to file
IMAGEMAGICK_VER=$(httpGet "$API_BASE/ImageMagick/ImageMagick/tags" | jq -r '[.[] | select(.name|test("^[0-9]+.[0-9]+.[0-9]+(-[0-9]+)?$")) | .name] | join("\n")' | sort -rV | head -1)

if [ -n "$IMAGEMAGICK_VER" ]; then
  echo "$IMAGEMAGICK_VER" > "$WORKDIR/versions/imagemagick.version"
else
  echo "Error: Failed to get version information for ImageMagick."
  exit 1
fi

# Download ImageMagick tarball, calculate it's hash and write it to file
IMAGEMAGICK_HASH=$(httpGet "$FILE_BASE/ImageMagick/ImageMagick/tar.gz/$IMAGEMAGICK_VER" | sha1sum | cut -b-40)

if [ -n "$IMAGEMAGICK_HASH" ]; then
 echo "$IMAGEMAGICK_HASH" > "$WORKDIR/versions/imagemagick.hash"
else
  echo "Error: Failed to get hash information for ImageMagick $IMAGEMAGICK_VER tarball."
  exit 1
fi

# Get version information for latest stable aom and write it to file
LIBAOM_VER=$(httpGet "$API_BASE/jbeich/aom/tags" | jq -r '[.[] | select(.name|test("^v[0-9]+.[0-9]+.[0-9]+$")) | .name[1:]] | join("\n")' | sort -rV | head -1)

if [ -n "$LIBAOM_VER" ]; then
  echo "$LIBAOM_VER" > "$WORKDIR/versions/aom.version"
else
  echo "Error: Failed to get version information for AOM."
  exit 1
fi

# Download aom tarball, calculate it's hash and write it to file
LIBAOM_HASH=$(httpGet "$FILE_BASE/jbeich/aom/tar.gz/v$LIBAOM_VER" | sha1sum | cut -b-40)

if [ -n "$LIBAOM_HASH" ]; then
 echo "$LIBAOM_HASH" > "$WORKDIR/versions/aom.hash"
else
  echo "Error: Failed to get hash information for AOM $LIBAOM_VER tarball."
  exit 1
fi

# Get version information for libheif and write it to file
LIBHEIF_VER=$(httpGet "$API_BASE/strukturag/libheif/tags" | jq -r '[.[] | select(.name|test("^v[0-9]+.[0-9]+.[0-9]+$")) | .name[1:]] | join("\n")' | sort -rV | head -1)

if [ -n "$LIBHEIF_VER" ]; then
  echo "$LIBHEIF_VER" > "$WORKDIR/versions/libheif.version"
else
  echo "Error: Failed to get version information for Libheif."
  exit 1
fi

# Download libheif tarball, calculate it's hash and write it to file
LIBHEIF_HASH=$(httpGet "$FILE_BASE/strukturag/libheif/tar.gz/v$LIBHEIF_VER" | sha1sum | cut -b-40)

if [ -n "$LIBHEIF_HASH" ]; then
 echo "$LIBHEIF_HASH" > "$WORKDIR/versions/libheif.hash"
else
  echo "Error: Failed to get hash information for Libheif $LIBHEIF_VER tarball."
  exit 1
fi

# Update README file
REPLACEMENT="\n* ImageMagick version: \`$IMAGEMAGICK_VER\`\n"
REPLACEMENT+="* libaom version: \`$LIBAOM_VER\`\n"
REPLACEMENT+="* libheif version: \`$LIBHEIF_VER\`"
sed -En '1h;1!H;${g;s/(<!-- versions start -->)(.*)(<!-- versions end -->)/\1'"$REPLACEMENT"'\3/;p;}' -i "$WORKDIR/README.md"

exit 0
