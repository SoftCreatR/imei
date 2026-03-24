#!/usr/bin/env bash

#
# Refresh the tracked upstream versions and tarball hashes used by IMEI.
# This updates the files under versions/ and rewrites the README defaults block.
#

set -euo pipefail

WORKDIR="$(cd "$(dirname "$0")" && pwd)"
GH_FILE_BASE="https://codeload.github.com"
CLIENT=""

# Pick the available HTTP client once so later helpers can stay generic.
get_client() {
  local cmd

  for cmd in curl wget; do
    if command -v "$cmd" >/dev/null 2>&1; then
      CLIENT="$cmd"
      return 0
    fi
  done

  echo "Error: This script requires curl or wget." >&2
  return 1
}

# Fetch a URL to stdout through the selected client implementation.
http_get() {
  case "$CLIENT" in
  curl) curl -fsSL "$1" ;;
  wget) wget -qO- "$1" ;;
  *) return 1 ;;
  esac
}

# Normalize upstream version tags down to the numeric value IMEI stores in versions/.
sanitize_version() {
  printf '%s\n' "${1//[^0-9.-]/}"
}

# Resolve the newest upstream tag that matches the expected release pattern.
latest_tag() {
  local repo="$1"
  local regex="$2"

  git ls-remote --tags --sort='v:refname' --refs "https://github.com/$repo.git" \
    | awk -F/ '{print $NF}' \
    | grep -E "$regex" \
    | tail -n1
}

# Hash the upstream release tarball so later builds can verify downloads.
tarball_sha1() {
  local repo="$1"
  local version="$2"

  http_get "$GH_FILE_BASE/$repo/tar.gz/$version" | sha1sum | awk '{print $1}'
}

# Refresh one component's tracked version file and tarball hash file.
write_component_version() {
  local repo="$1"
  local tag_regex="$2"
  local version_file="$3"
  local hash_file="$4"
  local raw_version
  local clean_version

  raw_version="$(latest_tag "$repo" "$tag_regex")"
  [[ -n "$raw_version" ]] || {
    echo "Error: Failed to determine a version for $repo." >&2
    exit 1
  }

  clean_version="$(sanitize_version "$raw_version")"
  printf '%s\n' "$clean_version" >"$version_file"
  tarball_sha1 "$repo" "$raw_version" >"$hash_file"
}

# Rewrite the README defaults section from the tracked versions in versions/.
update_readme_defaults() {
  local imagemagick_version
  local aom_version
  local libheif_version
  local libjxl_version
  local replacement

  imagemagick_version="$(<"$WORKDIR/versions/imagemagick.version")"
  aom_version="$(<"$WORKDIR/versions/aom.version")"
  libheif_version="$(<"$WORKDIR/versions/libheif.version")"
  libjxl_version="$(<"$WORKDIR/versions/libjxl.version")"

  replacement=$'* ImageMagick version: `'"$imagemagick_version"$' (Q16)`\n'
  replacement+=$'* libaom version: `'"$aom_version"$'`\n'
  replacement+=$'* libheif version: `'"$libheif_version"$'`\n'
  replacement+=$'* libjxl version: `'"$libjxl_version"$'`'

  perl -0pi -e "s|<!-- versions start -->.*?<!-- versions end -->|<!-- versions start -->\n$replacement\n<!-- versions end -->|s" "$WORKDIR/README.md"
}

get_client

write_component_version "ImageMagick/ImageMagick" '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]+)?$' "$WORKDIR/versions/imagemagick.version" "$WORKDIR/versions/imagemagick.hash"
write_component_version "SoftCreatR/aom" '^v[0-9]+\.[0-9]+\.[0-9]+$' "$WORKDIR/versions/aom.version" "$WORKDIR/versions/aom.hash"
write_component_version "strukturag/libheif" '^v[0-9]+\.[0-9]+\.[0-9]+$' "$WORKDIR/versions/libheif.version" "$WORKDIR/versions/libheif.hash"
write_component_version "libjxl/libjxl" '^v[0-9]+\.[0-9]+(\.[0-9]+)?$' "$WORKDIR/versions/libjxl.version" "$WORKDIR/versions/libjxl.hash"
update_readme_defaults
