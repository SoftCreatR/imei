#!/usr/bin/env bash

#
# Bootstrap build dependencies for IMEI.
# - Uses distro source-package metadata as the baseline via apt-get build-dep.
# - Adds delegate-aware dependency resolution so IMEI's desired feature set is
#   installed even when distro ImageMagick packaging leaves delegates optional.
#

set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Error: scripts/install-build-deps.sh must run as root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/delegates.sh"

GENERATED_LIST="/etc/apt/sources.list.d/imei-src.list"
GENERATED_SOURCES="/etc/apt/sources.list.d/imei-src.sources"

BOOTSTRAP_PACKAGES=(
  apt-file
  ca-certificates
  curl
  dpkg-dev
  file
  git
  ninja-build
  pkg-config
)

APT_FILE_READY="no"
SKIP_AOM="no"
SKIP_LIBHEIF="no"
SKIP_JXL="no"
ENABLE_MAGICK_PLUS_PLUS="no"
ENABLE_PERL="no"
DISABLED_DELEGATES=()

package_exists() {
  apt-cache show "$1" >/dev/null 2>&1
}

detect_debian_signed_by() {
  local sources_files=()
  local signed_by=""

  shopt -s nullglob
  sources_files=(/etc/apt/sources.list.d/*.sources)
  shopt -u nullglob

  if ((${#sources_files[@]} > 0)); then
    signed_by="$(
      awk '
        BEGIN { IGNORECASE = 1 }
        /^Signed-By:[[:space:]]+/ {
          sub(/^Signed-By:[[:space:]]+/, "")
          print
          exit
        }
      ' "${sources_files[@]}"
    )"
  fi

  if [[ -n "$signed_by" ]]; then
    printf '%s\n' "$signed_by"
    return 0
  fi

  if [[ -f /usr/share/keyrings/debian-archive-keyring.pgp ]]; then
    printf '%s\n' "/usr/share/keyrings/debian-archive-keyring.pgp"
  else
    printf '%s\n' "/usr/share/keyrings/debian-archive-keyring.gpg"
  fi
}

disable_delegate() {
  local delegate_name

  delegate_name="$(delegate_normalize_name "$1")"
  if ! delegate_is_known "$delegate_name"; then
    echo "Error: Unknown delegate: $1" >&2
    exit 1
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

configure_eol_ubuntu_repositories() {
  local old_releases_base="http://old-releases.ubuntu.com/ubuntu"
  local list_input
  local sources_input

  [[ -r /etc/os-release ]] || return 0
  # shellcheck disable=SC1091
  . /etc/os-release

  [[ "${ID:-}" == "ubuntu" ]] || return 0
  if ! grep -RqsE 'https?://((archive|security)\.ubuntu\.com/ubuntu|ports\.ubuntu\.com/ubuntu-ports)' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    return 0
  fi

  for list_input in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
    [[ -f "$list_input" ]] || continue
    sed -i \
      -e "s|https\\?://archive.ubuntu.com/ubuntu|$old_releases_base|g" \
      -e "s|https\\?://security.ubuntu.com/ubuntu|$old_releases_base|g" \
      -e "s|https\\?://ports.ubuntu.com/ubuntu-ports|$old_releases_base|g" \
      "$list_input"
  done

  for sources_input in /etc/apt/sources.list.d/*.sources; do
    [[ -f "$sources_input" ]] || continue
    sed -i \
      -e "s|https\\?://archive.ubuntu.com/ubuntu|$old_releases_base|g" \
      -e "s|https\\?://security.ubuntu.com/ubuntu|$old_releases_base|g" \
      -e "s|https\\?://ports.ubuntu.com/ubuntu-ports|$old_releases_base|g" \
      "$sources_input"
  done
}

ubuntu_release_index_available() {
  local archive_base="$1"
  local security_base="$2"
  local ubuntu_codename="$3"
  local probe_list

  probe_list="$(mktemp)"
  cat >"$probe_list" <<EOF
deb-src $archive_base $ubuntu_codename main restricted universe multiverse
deb-src $archive_base ${ubuntu_codename}-updates main restricted universe multiverse
deb-src $archive_base ${ubuntu_codename}-backports main restricted universe multiverse
deb-src $security_base ${ubuntu_codename}-security main restricted universe multiverse
EOF

  if apt-get update \
    -o Dir::Etc::sourcelist="$probe_list" \
    -o Dir::Etc::sourceparts="-" \
    -o APT::Get::List-Cleanup="0" \
    -qq >/dev/null 2>&1; then
    rm -f "$probe_list"
    return 0
  fi

  rm -f "$probe_list"
  return 1
}

resolve_ubuntu_source_bases() {
  local ubuntu_codename="$1"
  local archive_base="http://archive.ubuntu.com/ubuntu"
  local security_base="http://security.ubuntu.com/ubuntu"
  local old_releases_base="http://old-releases.ubuntu.com/ubuntu"

  if grep -Rqs 'old-releases.ubuntu.com/ubuntu' /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
    printf '%s\n%s\n' "$old_releases_base" "$old_releases_base"
    return 0
  fi

  if ubuntu_release_index_available "$archive_base" "$security_base" "$ubuntu_codename"; then
    printf '%s\n%s\n' "$archive_base" "$security_base"
    return 0
  fi

  printf '%s\n%s\n' "$old_releases_base" "$old_releases_base"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
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
  --target | --work-dir | --output-dir | --imagemagick-version | --im-version | --aom-version | --libheif-version | --heif-version | --jpeg-xl-version | --jxl-version | --imagemagick-quantum-depth | --im-q)
    shift 2
    ;;
  --imagemagick-opencl | --im-ocl | --imagemagick-build-static | --im-build-static | --no-install | --keep-work-dir)
    shift
    ;;
  *)
    shift
    ;;
  esac
done

if delegate_is_disabled heic; then
  SKIP_LIBHEIF="yes"
  SKIP_AOM="yes"
fi

if delegate_is_disabled jxl; then
  SKIP_JXL="yes"
fi

# Mirror the existing binary APT sources as temporary deb-src entries so
# apt-get build-dep can resolve source-package metadata on stock systems.
ensure_source_repositories() {
  local list_input
  local sources_input
  local ubuntu_codename
  local debian_codename
  local archive_base
  local security_base
  local debian_signed_by
  local ubuntu_bases

  rm -f "$GENERATED_LIST" "$GENERATED_SOURCES"

  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
  fi

  if [[ "${ID:-}" == "ubuntu" ]]; then
    ubuntu_codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    [[ -n "$ubuntu_codename" ]] || {
      echo "Error: unable to determine Ubuntu codename for temporary source repositories." >&2
      exit 1
    }

    ubuntu_bases="$(resolve_ubuntu_source_bases "$ubuntu_codename")"
    archive_base="$(printf '%s\n' "$ubuntu_bases" | sed -n '1p')"
    security_base="$(printf '%s\n' "$ubuntu_bases" | sed -n '2p')"

    cat >"$GENERATED_LIST" <<EOF
deb-src $archive_base $ubuntu_codename main restricted universe multiverse
deb-src $archive_base ${ubuntu_codename}-updates main restricted universe multiverse
deb-src $archive_base ${ubuntu_codename}-backports main restricted universe multiverse
deb-src $security_base ${ubuntu_codename}-security main restricted universe multiverse
EOF
    return 0
  fi

  if [[ "${ID:-}" == "debian" ]]; then
    debian_codename="${VERSION_CODENAME:-}"
    [[ -n "$debian_codename" ]] || {
      echo "Error: unable to determine Debian codename for temporary source repositories." >&2
      exit 1
    }

    archive_base="http://deb.debian.org/debian"
    security_base="http://security.debian.org/debian-security"
    debian_signed_by="$(detect_debian_signed_by)"

    cat >"$GENERATED_SOURCES" <<EOF
Types: deb-src
URIs: $archive_base
Suites: $debian_codename ${debian_codename}-updates
Components: main
Signed-By: $debian_signed_by

Types: deb-src
URIs: $security_base
Suites: ${debian_codename}-security
Components: main
Signed-By: $debian_signed_by
EOF

    case "$debian_codename" in
    bullseye) ;;
    *)
      cat >>"$GENERATED_SOURCES" <<EOF

Types: deb-src
URIs: $archive_base
Suites: ${debian_codename}-backports
Components: main
Signed-By: $debian_signed_by
EOF
      ;;
    esac

    return 0
  fi

  for list_input in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
    [[ -f "$list_input" ]] || continue

    awk '
      /^[[:space:]]*deb[[:space:]]/ && $0 !~ /^[[:space:]]*deb-src[[:space:]]/ {
        sub(/^[[:space:]]*deb[[:space:]]+/, "deb-src ")
        print
      }
    ' "$list_input" >>"$GENERATED_LIST"
  done

  for sources_input in /etc/apt/sources.list.d/*.sources; do
    [[ -f "$sources_input" ]] || continue

    awk '
      BEGIN {
        stanza = ""
      }
      {
        if ($0 ~ /^[[:space:]]*$/) {
          if (stanza != "") {
            print stanza
            print ""
            stanza = ""
          }
          next
        }

        line = $0
        if (line ~ /^Types:[[:space:]]+/) {
          line = "Types: deb-src"
        }

        if (stanza == "") {
          stanza = line
        } else {
          stanza = stanza "\n" line
        }
      }
      END {
        if (stanza != "") {
          print stanza
        }
      }
    ' "$sources_input" >>"$GENERATED_SOURCES"
  done
}

# Remove the temporary deb-src configuration after dependency installation.
cleanup_source_repositories() {
  rm -f "$GENERATED_LIST" "$GENERATED_SOURCES"
  apt-get update -qq || true
}

# Resolve the source package name that backs one of the provided binary packages.
resolve_source_from_binary() {
  local binary_package
  local source_name

  for binary_package in "$@"; do
    if ! package_exists "$binary_package"; then
      continue
    fi

    source_name="$(
      apt-cache show "$binary_package" \
        | awk '
            /^Source:/ { print $2; found = 1; exit }
            /^Package:/ && !found { print $2; exit }
          '
    )"

    if [[ -n "$source_name" ]]; then
      printf '%s\n' "$source_name"
      return 0
    fi
  done

  return 1
}

# Pick the source package to use for build-dep, falling back to a known source name.
resolve_component_source() {
  local fallback_source="$1"
  shift
  local source_name=""

  if source_name="$(resolve_source_from_binary "$@")"; then
    printf '%s\n' "$source_name"
    return 0
  fi

  printf '%s\n' "$fallback_source"
}

# Install the minimal toolchain needed before any source/delegate resolution can happen.
install_bootstrap_packages() {
  if ! apt-get update -qq; then
    configure_eol_ubuntu_repositories
    apt-get update -qq
  fi
  apt-get install -y "${BOOTSTRAP_PACKAGES[@]}"
}

# Ask APT to install the distro-maintained build dependencies for one source package.
install_component_build_deps() {
  local label="$1"
  local source_name="$2"

  if ! apt-cache showsrc "$source_name" >/dev/null 2>&1; then
    echo "Warning: source package '$source_name' is unavailable on this target; skipping distro build-dep for $label." >&2
    return 1
  fi

  echo "Installing build dependencies for $label via source package: $source_name"
  DEB_BUILD_PROFILES="nocheck nodoc" \
    apt-get build-dep --arch-only -y "$source_name"
}

# Install the minimal ImageMagick baseline when distro build-deps on archived
# Ubuntu releases reference binary packages that no longer exist in old-releases.
install_imagemagick_fallback_build_deps() {
  echo "Installing fallback build dependencies for imagemagick from IMEI baseline"

  ensure_packages_if_available \
    build-essential \
    cmake \
    libbz2-dev \
    libltdl-dev \
    zlib1g-dev
}

# Refresh apt-file once per run so file-to-package lookups stay cheap afterward.
ensure_apt_file_index() {
  if [[ "$APT_FILE_READY" == "yes" ]]; then
    return 0
  fi

  apt-file update >/dev/null 2>&1
  APT_FILE_READY="yes"
}

# Resolve a pkg-config module or delegate fallback to the package that provides it.
# This avoids hardcoding distro-specific package names for versioned -dev packages.
resolve_file_provider() {
  local pattern="$1"
  local provider

  ensure_apt_file_index

  provider="$(
    apt-file search -x "$pattern" 2>/dev/null \
      | cut -d: -f1 \
      | sort -u \
      | awk '
          /-dev$/ { print; found = 1; exit }
          !found { first = $0 }
          END {
            if (!found && first != "") {
              print first
            }
          }
        '
  )"

  if [[ -n "$provider" ]]; then
    printf '%s\n' "$provider"
    return 0
  fi

  return 1
}

# Install one concrete package if it is not already present.
ensure_package_installed() {
  local package_name="$1"

  if dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q "install ok installed"; then
    return 0
  fi

  apt-get install -y "$package_name"
}

# Best-effort install for optional packages that may exist in package metadata
# but have broken dependency chains on archived/EOL repositories.
try_ensure_package_installed() {
  local package_name="$1"

  if dpkg-query -W -f='${Status}' "$package_name" 2>/dev/null | grep -q "install ok installed"; then
    return 0
  fi

  if ! apt-get install -y "$package_name"; then
    echo "Warning: unable to install optional package '$package_name'; continuing." >&2
    return 1
  fi
}

# Ensure a pkg-config module is available, resolving the provider package dynamically.
ensure_pkgconfig_module() {
  local module_name="$1"
  local provider
  local escaped_module

  if pkg-config --exists "$module_name"; then
    return 0
  fi

  escaped_module="$(printf '%s' "$module_name" | sed -E 's/[][(){}.^$+*?|\\]/\\&/g')"
  provider="$(resolve_file_provider "/(pkgconfig|pkg-config)/${escaped_module}\\.pc$")" || return 1
  ensure_package_installed "$provider"
  pkg-config --exists "$module_name"
}

# Ensure the packages needed for one enabled delegate are installed.
# Some delegates are pkg-config driven, others need package fallbacks for tools
# or libraries that are not cleanly discoverable from .pc files alone.
ensure_delegate_support() {
  local delegate_name="$1"
  local module_name
  local package_name
  local fallback_packages

  if delegate_is_disabled "$delegate_name"; then
    return 0
  fi

  module_name="$(delegate_pkgconfig_module "$delegate_name")"
  if [[ -n "$module_name" ]]; then
    if ! ensure_pkgconfig_module "$module_name"; then
      echo "Warning: unable to resolve a package for pkg-config module '$module_name'." >&2
    fi
  fi

  fallback_packages="$(delegate_package_fallbacks "$delegate_name")"
  if [[ -n "$fallback_packages" ]]; then
    for package_name in $fallback_packages; do
      if package_exists "$package_name"; then
        ensure_package_installed "$package_name"
      fi
    done
  fi
}

# Best-effort installer for packages that may exist only on some distros/releases.
ensure_packages_if_available() {
  local package_name

  for package_name in "$@"; do
    if package_exists "$package_name"; then
      try_ensure_package_installed "$package_name" || true
    fi
  done
}

# Install delegate-related packages needed to preserve IMEI's default feature set.
install_optional_packages() {
  local delegate_name

  for delegate_name in "${IMEI_DEFAULT_DELEGATES[@]}"; do
    if [[ "$delegate_name" == "heic" && "$SKIP_LIBHEIF" == "yes" ]]; then
      continue
    fi

    if [[ "$delegate_name" == "jxl" && "$SKIP_JXL" == "yes" ]]; then
      continue
    fi

    ensure_delegate_support "$delegate_name"
  done

  ensure_packages_if_available \
    ffmpeg \
    ghostscript \
    gsfonts \
    libbrotli-dev \
    libcrypt-dev \
    libde265-dev \
    libgraphviz-dev \
    libgs-dev \
    libhwy-dev \
    libjbig-dev \
    libjpeg-dev \
    liblcms2-dev \
    liblzma-dev \
    libraw-dev \
    libwmf-dev \
    libx11-dev \
    libxext-dev

  if [[ "$ENABLE_MAGICK_PLUS_PLUS" == "yes" ]]; then
    ensure_packages_if_available g++
  fi

  if [[ "$ENABLE_PERL" == "yes" ]]; then
    ensure_packages_if_available perl libperl-dev
  fi
}

# Install the upstream-documented libjxl build prerequisites when the distro
# does not ship jpeg-xl source metadata for apt-get build-dep.
install_libjxl_fallback_build_deps() {
  echo "Installing fallback build dependencies for libjxl from upstream requirements"

  ensure_packages_if_available \
    cmake \
    pkg-config \
    libbrotli-dev \
    libgif-dev \
    libhwy-dev \
    libjpeg-dev \
    liblcms2-dev \
    libopenexr-dev \
    libpng-dev \
    libwebp-dev
}

install_bootstrap_packages
trap cleanup_source_repositories EXIT
ensure_source_repositories
apt-get update -qq

if [[ "$SKIP_AOM" != "yes" ]]; then
  install_component_build_deps "aom" "$(resolve_component_source aom libaom-dev aom-tools)"
fi

if [[ "$SKIP_LIBHEIF" != "yes" ]]; then
  install_component_build_deps "libheif" "$(resolve_component_source libheif libheif-dev libheif1)"
fi

if [[ "$SKIP_JXL" != "yes" ]]; then
  if ! install_component_build_deps "libjxl" "$(resolve_component_source jpeg-xl libjxl-dev)"; then
    install_libjxl_fallback_build_deps
  fi
fi

if ! install_component_build_deps "imagemagick" "$(resolve_component_source imagemagick libmagickwand-dev imagemagick)"; then
  install_imagemagick_fallback_build_deps
fi
install_optional_packages
