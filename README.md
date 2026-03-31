<div align=center>

# IMEI - ImageMagick Easy Install
#### Signed ImageMagick `.deb` packages for Debian and Ubuntu, with pre-built releases and local package builds.

[![Release Packages](https://img.shields.io/github/actions/workflow/status/SoftCreatR/imei/main.yml?branch=main&style=flat-square)](https://github.com/SoftCreatR/imei/actions/workflows/main.yml)
[![CI](https://img.shields.io/github/actions/workflow/status/SoftCreatR/imei/ci.yml?branch=main&label=ci&style=flat-square)](https://github.com/SoftCreatR/imei/actions/workflows/ci.yml)
[![GitHub release](https://img.shields.io/github/release/SoftCreatR/imei?style=flat-square)](https://github.com/SoftCreatR/imei/releases)
[![GitHub license](https://img.shields.io/github/license/SoftCreatR/imei?style=flat-square&color=lightgray)](LICENSE.md)

</div>

---

## What IMEI Does

IMEI installs ImageMagick and selected delegate libraries as proper Debian packages instead of running `make install` directly on the target system.

That gives you two installation paths:

* pre-built signed `.deb` packages for supported release targets
* local package builds for older systems or custom build options

In both cases, the end result is still managed by `apt` / `dpkg`, so removal stays clean.

## Why IMEI Exists

IMEI is meant to solve the two common problems with ad-hoc ImageMagick install scripts:

* building everything on the target machine can take too long
* hand-installed files are hard to remove cleanly later

IMEI keeps the convenience of an install script, but the actual installation happens through generated `.deb` packages.

## Security Model

IMEI verifies signatures in two places by default:

* the local `imei.sh` script verifies itself against `imei.sh.sig`
* pre-built release installs verify signed release metadata before any `.deb` is installed

The release install path verifies:

* `release-manifest.env`
* `SHA256SUMS`
* the downloaded package hashes listed in `SHA256SUMS`

IMEI supports key rotation through the files in `keys/`. New signatures can point to a specific public key by key id, while older signatures can still be preserved in the keyring.

Notes:

* `--no-sig-verify` disables only installer self-verification and is intended for local development or recovery cases
* self-update only trusts release bundles signed by a key that already exists in the local keyring
* if you rotate to a brand-new key that is not yet trusted locally, one manual keyring refresh is still required once

## Compatibility

Pre-built release assets are currently intended for these `amd64` and `arm64` targets:

* Debian 11 (Bullseye)
* Debian 12 (Bookworm)
* Debian 13 (Trixie)
* Ubuntu 20.04 (**Focal** Fossa)
* Ubuntu 22.04 (**Jammy** Jellyfish)
* Ubuntu 24.04 (**Noble** Numbat)
* Ubuntu 26.04 (**Resolute** Raccoon)

Other Debian and Ubuntu systems, including Ubuntu non-LTS releases, or other architectures, can still use IMEI through local package builds.

## Runtime Container

IMEI also publishes a small runtime container image built from the released `ubuntu24.04` IMEI packages.

Image:

```bash
ghcr.io/softcreatr/imei-imagemagick:latest
```

Example:

```bash
docker run --rm ghcr.io/softcreatr/imei-imagemagick:latest -version
```

The container image is intentionally a secondary delivery format:

* it uses one base target only: `ubuntu24.04` (amd64 / arm64)
* it is meant to provide the full ImageMagick 7 runtime in Dockerized environments, including longer-lived containers
* the primary supported install path for host systems remains the signed `.deb` packages

## Package Layout

IMEI currently builds and installs these packages:

* `imei-libaom`
* `imei-libheif`
* `imei-libjxl`
* `imei-imagemagick`

The private runtime stack is installed below `/opt/imei`.

`imei-imagemagick` exposes the CLI tools through `/usr/bin`, while the delegate libraries remain under `/opt/imei` so IMEI does not overwrite distro `libaom`, `libheif`, or `libjxl` packages.

## Default Behavior

Running `sudo ./imei.sh` does this:

1. verifies the installer signature
2. detects the local Debian/Ubuntu target
3. checks whether a matching signed pre-built release exists
4. installs pre-built packages when a match exists
5. otherwise falls back to a local `.deb` build

This means supported current targets should normally use release assets, while older or customized installs automatically drop to the local build path.

## Installation

The primary install path is the one-step bootstrap launcher:

```bash
t=$(mktemp) && \
wget 'https://dist.1-2.dev/imei.sh' -qO "$t" && \
bash "$t" && \
rm "$t"
```

Manual verification of the bootstrap launcher still works too:

```bash
wget https://dist.1-2.dev/imei.sh && \
wget https://dist.1-2.dev/imei.sh.sig && \
wget https://dist.1-2.dev/imei.sh.pem && \
openssl dgst -sha512 -verify imei.sh.pem -signature imei.sh.sig imei.sh
```

The bootstrap launcher first tries to fetch the signed IMEI runtime bundle from the release assets. If that bundle is unavailable, it falls back to the repository source tree on `main`, where IMEI then follows its normal behavior: use pre-built packages when available, otherwise build locally.

If you want to pass options through the one-step installer, append them after `bash "$t"`:

```bash
t=$(mktemp) && \
wget 'https://dist.1-2.dev/imei.sh' -qO "$t" && \
bash "$t" --build-local && \
rm "$t"
```

Manual checkout install:

```bash
git clone https://github.com/SoftCreatR/imei && \
cd imei && \
chmod +x imei.sh && \
sudo ./imei.sh
```

## Self-Update

To update the local IMEI checkout itself:

```bash
./imei.sh --self-update
```

This downloads the signed IMEI runtime bundle from the selected release and updates:

* `imei.sh`
* `scripts/*`
* `versions/*`
* the public keyring in `keys/*`

## User Install Mode

IMEI also supports an unprivileged source-build mode for installation into a user-owned prefix.

Example:

```bash
./imei.sh --user-install
```

Default user prefix:

```bash
~/.local/imei
```

Custom user prefix:

```bash
./imei.sh --user-install --prefix "$HOME/.opt/imei"
```

User-install mode:

* does not use `apt` or `dpkg`
* does not install system-wide files under `/usr/bin`
* does not provide package-managed removal
* expects the required system build dependencies to already be installed

After installation:

```bash
. "$HOME/.local/imei/imei-env.sh"
```

Removal:

```bash
rm -rf "$HOME/.local/imei"
```

## Pre-Built Release Commands

Install only from release assets and fail instead of building locally:

```bash
sudo ./imei.sh --prebuilt-only
```

Download release packages without installing them:

```bash
sudo ./imei.sh --download-only --keep-downloads
```

Install from a specific release tag:

```bash
sudo ./imei.sh --release-tag im-7.1.2-18_aom-3.13.2_heif-1.21.2_jxl-0.11.2
```

Test against a different release repository:

```bash
sudo ./imei.sh --github-repository SoftCreatR/imei-private-test
```

## Local Build Commands

Force a local package build:

```bash
sudo ./imei.sh --build-local
```

Common examples:

```bash
sudo ./imei.sh --build-local --imagemagick-version 7.1.2-18
sudo ./imei.sh --build-local --aom-version 3.13.2
sudo ./imei.sh --build-local --libheif-version 1.21.2
sudo ./imei.sh --build-local --jpeg-xl-version 0.11.2
sudo ./imei.sh --build-local --imagemagick-quantum-depth 8
sudo ./imei.sh --build-local --imagemagick-opencl
sudo ./imei.sh --build-local --imagemagick-build-static
sudo ./imei.sh --build-local --imagemagick-with-magick-plus-plus
sudo ./imei.sh --build-local --imagemagick-with-perl
sudo ./imei.sh --build-local --disable-delegate raqm
sudo ./imei.sh --build-local --skip-jpeg-xl
sudo ./imei.sh --build-local --work-dir /tmp/imei-build
sudo ./imei.sh --build-local --output-dir /tmp/imei-dist
sudo ./imei.sh --build-local --keep-build-deps
```

## PHP imagick

IMEI does not ship a separate `php-imagick` package. To make PHP use the IMEI ImageMagick installation, rebuild the `imagick` extension against `/opt/imei`.

Important notes:

* the distro `php-imagick` package is usually built against the distro ImageMagick libraries, not IMEI
* `imagick` uses MagickCore and MagickWand, not Magick++, so `--imagemagick-with-magick-plus-plus` is not required
* after upgrading IMEI to a newer ImageMagick release, rebuild the PHP `imagick` extension too

Recommended path with PECL:

```bash
sudo apt install php-dev php-pear pkg-config
sudo apt remove php-imagick --purge || true
sudo pecl uninstall imagick || true
sudo pecl channel-update pecl.php.net

export PKG_CONFIG_PATH=/opt/imei/lib/pkgconfig
export CPPFLAGS="-I/opt/imei/include"
export LDFLAGS="-L/opt/imei/lib -Wl,-rpath,/opt/imei/lib"

printf "\n" | sudo -E pecl install imagick
```

Enable the extension if PECL did not already do it:

```bash
PHP_VERSION="$(php -r 'echo PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION;')"
echo "extension=imagick.so" | sudo tee "/etc/php/${PHP_VERSION}/mods-available/imagick.ini" >/dev/null
sudo phpenmod imagick
```

Restart PHP afterward:

```bash
sudo systemctl restart php"${PHP_VERSION}"-fpm
```

If you use Apache instead of PHP-FPM:

```bash
sudo systemctl restart apache2
```

Verify that PHP is using the IMEI build:

```bash
php --ri imagick
php -r '$i = new Imagick(); print_r($i->getVersion());'
php -r '$i = new Imagick(); print_r($i->queryFormats("HEI*"));'
php -r '$i = new Imagick(); print_r($i->queryFormats("AVIF"));'
php -r '$i = new Imagick(); print_r($i->queryFormats("JXL"));'
```

If `pecl install imagick` still links against the wrong ImageMagick, build it manually:

```bash
sudo apt install php-dev pkg-config
sudo apt remove php-imagick --purge || true
pecl download imagick
tar -xf imagick-*.tgz
cd imagick-*/
phpize

export PKG_CONFIG_PATH=/opt/imei/lib/pkgconfig
export CPPFLAGS="-I/opt/imei/include"
export LDFLAGS="-L/opt/imei/lib -Wl,-rpath,/opt/imei/lib"

./configure --with-php-config="$(command -v php-config)"
make -j"$(nproc)"
sudo make install
```

## Available Installer Options

General behavior:

* without any options, `sudo ./imei.sh` verifies the installer, detects the local target, prefers a matching signed pre-built release, and falls back to a local package build if no supported release asset exists
* most build-specific flags force the local build path automatically, because a published pre-built package cannot be reconfigured on the target machine

Installer path options:

* `--build-local`
  Forces a local build instead of using release assets. Default: off.
* `--user-install`
  Uses the unprivileged source-build backend and installs into a user-owned prefix such as `~/.local/imei`. Default: off.
* `--prebuilt-only`
  Restricts IMEI to release assets and fails if no exact pre-built target is available. Default: off.
* `--download-only`
  Downloads the selected release assets but does not install them. Default: off.
* `--self-update`
  Updates the local IMEI checkout itself from the signed self-update bundle instead of installing ImageMagick. Default: off.
* `--download-dir <dir>`
  Uses a custom directory for downloaded release assets. Default: a temporary directory.
* `--keep-downloads`
  Preserves downloaded release assets after install or download-only mode completes. Default: off.
* `--no-sig-verify`
  Skips only the local `imei.sh` self-signature check. Release metadata verification still applies to pre-built installs. Default: off.
* `--release-tag <tag>`
  Installs or downloads assets from a specific GitHub release tag instead of `latest`. Default: latest release.
* `--github-repository <owner/repo>`
  Uses another GitHub repository as the release source. Default: `SoftCreatR/imei`.
* `--target <target>`
  Overrides automatic target detection. Mainly useful for testing, CI, or release-asset inspection. Default: detected local target.
* `--help`
  Prints the built-in command help and exits.

Local build and user-install options:

* `--prefix <dir>`
  Overrides the install prefix for `--user-install`. Default: `~/.local/imei`. In the normal package-managed path, IMEI still installs under `/opt/imei`.
* `--imagemagick-version <version>`
  Builds a specific ImageMagick release instead of the version pinned in `versions/imagemagick`.
* `--aom-version <version>`
  Builds a specific `libaom` release instead of the pinned default.
* `--libheif-version <version>`
  Builds a specific `libheif` release instead of the pinned default.
* `--jpeg-xl-version <version>`
  Builds a specific `libjxl` release instead of the pinned default.
* `--imagemagick-quantum-depth <n>`
  Sets the ImageMagick quantum depth. Valid values: `8`, `16`, `32`. Default: `16`.
* `--imagemagick-opencl`
  Enables OpenCL support in the local ImageMagick build. Default: off.
* `--imagemagick-build-static`
  Builds ImageMagick static instead of shared. Default: shared build.
* `--imagemagick-with-magick-plus-plus`
  Builds the Magick++ C++ interface in the local ImageMagick build. Default: off for faster builds.
* `--imagemagick-with-perl`
  Builds PerlMagick in the local ImageMagick build. Default: off for faster builds.
* `--disable-delegate <name>`
  Disables a specific ImageMagick delegate from IMEI's default delegate set. Can be passed multiple times. Default: no delegates disabled.
* `--skip-aom`
  Skips building `libaom`. Default: off. This also requires skipping `libheif`, because IMEI's `libheif` build expects the IMEI `libaom` stack.
* `--skip-libheif`
  Skips building `libheif` and the `heic` delegate path. Default: off.
* `--skip-jpeg-xl`
  Skips building `libjxl` and the `jxl` delegate path. Default: off.
* `--work-dir <dir>`
  Uses a custom build workspace instead of IMEI's temporary work directory.
* `--output-dir <dir>`
  Writes generated `.deb` files to a custom directory during local package builds. Default: `dist/<target>`.
* `--no-install`
  Builds the local `.deb` packages without installing them afterward. Only applies to the package-build path, not `--user-install`.
* `--keep-build-deps`
  Keeps the temporary build dependencies that IMEI installed for the local package build. Default: off. Without this flag, IMEI removes build-only packages it introduced after a successful local build.
* `--keep-work-dir`
  Keeps the build workspace after completion for debugging or inspection. Default: off.

Important combinations and limits:

* `--user-install` cannot be combined with `--prebuilt-only` or `--download-only`
* `--user-install` cannot be combined with `--output-dir` or `--no-install`
* `--prebuilt-only` is useful when you want a hard failure instead of a surprise local compile
* any option that changes build features, versions, delegates, or install style should be treated as a local-build request

## Delegate Support

IMEI aims to build ImageMagick with as much delegate support as the target distro can reasonably provide.

Default behavior:

* delegates are enabled by default
* local builds can disable specific delegates explicitly with `--disable-delegate <name>`
* dependency installation and ImageMagick configure flags are driven from the shared delegate policy in `scripts/delegates.sh`

This keeps the intended delegate set explicit without hardcoding every distro-specific package name forever.

## Private Repository Testing

IMEI can download release assets from another repository through `--github-repository`.

For private repositories:

* `GH_TOKEN` is preferred
* `GITHUB_TOKEN` also works
* when using `sudo`, preserve the environment with `sudo -E`

Example:

```bash
export GH_TOKEN=...
sudo -E ./imei.sh --github-repository owner/private-repo
```

In GitHub Actions, `GITHUB_TOKEN` is available automatically, but it still needs to be passed into the shell environment when a workflow step runs the script.

## Removal

Remove the installed IMEI packages cleanly through `apt`:

```bash
sudo apt remove imei-imagemagick imei-libheif imei-libjxl imei-libaom --purge
```

## Default Versions

<!-- versions start -->
* ImageMagick version: `7.1.2-18 (Q16)`
* libaom version: `3.13.2`
* libheif version: `1.21.2`
* libjxl version: `0.11.2`
<!-- versions end -->

## Operational Notes

* `imei-imagemagick` is intended to be mutually exclusive with distro ImageMagick command packages. If stock ImageMagick is already installed, `apt` may remove it to install IMEI. Installing stock ImageMagick afterward may remove `imei-imagemagick` for the same reason. Use `--user-install` if you need IMEI without taking over `/usr/bin`.
* pre-built release assets are target-specific; if no exact match exists, IMEI falls back to a local build unless `--prebuilt-only` is set
* release metadata must match the published asset filenames exactly, so release generation normalizes filenames before creating the manifest and checksums
* `--user-install` is a separate source-build backend and intentionally does not try to behave like a package-managed install

## License

[ISC](LICENSE.md) © [1-2.dev](https://1-2.dev)
