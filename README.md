<div align=center>

# IMEI - ImageMagick Easy Install
#### Automated ImageMagick compilation from sources for Debian/Ubuntu including advanced delegate support.

[![Build](https://img.shields.io/github/workflow/status/SoftCreatR/imei/Main?style=flat-square)](https://github.com/SoftCreatR/imei/actions/workflows/Main.yml)

[![Commits](https://img.shields.io/github/last-commit/SoftCreatR/imei?style=flat-square)](https://github.com/SoftCreatR/imei/commits/main) [![GitHub release](https://img.shields.io/github/release/SoftCreatR/imei?style=flat-square)](https://github.com/SoftCreatR/imei/releases) [![GitHub license](https://img.shields.io/github/license/SoftCreatR/imei?style=flat-square&color=lightgray)](LICENSE.md) [![Plant Tree](https://img.shields.io/badge/dynamic/json?color=brightgreen&label=Plant%20Tree&query=%24.total&url=https%3A%2F%2Fpublic.offset.earth%2Fusers%2Fsoftcreatr%2Ftrees&style=flat-square)](https://ecologi.com/softcreatr?r=61212ab3fc69b8eb8a2014f4)  ![Installs](https://img.shields.io/badge/dynamic/json?style=flat-square&color=blue&label=installs&query=value&url=https%3A%2F%2Fapi.countapi.xyz%2Fget%2Fsoftcreatr%2Fimei) [![GitHub file size in bytes](https://img.shields.io/github/size/SoftCreatR/imei/imei.sh?style=flat-square)](https://github.com/SoftCreatR/imei/blob/main/imei.sh)

[![Codacy grade](https://img.shields.io/codacy/grade/db0b2b5f22454f4280e4623de9f7075f?style=flat-square&label=codacy%20grade)](https://app.codacy.com/gh/SoftCreatR/imei/dashboard) [![CodeFactor Grade](https://img.shields.io/codefactor/grade/github/SoftCreatR/imei?style=flat-square&label=codefactor%20rating)](https://www.codefactor.io/repository/github/softcreatr/imei)

</div>

---

<div align="center">

<a href="#features"> Features<a> •
<a href="#compatibility"> Compatibility</a> •
<a href="#usage"> Usage</a> •
<a href="#contributing"> Contributing</a> •
<a href="#license"> License</a>

![Screenshot](screenshot.png)

</div>

---

## Features

* Compiles the latest ImageMagick release
* Installs ImageMagick or updates ImageMagick package previously installed (via IMEI)
* Additional HEIF/HEIC/HEIX support
* Additional AVIF support
* Additional JPEG XL support

---

## Compatibility

Every IMEI build will be automatically tested against the latest Ubuntu LTS Versions (16.04 and newer) using GitHub Actions. Compatibility with other operating systems (such as Debian 10, or Ubuntu 21.04) is tested manually.

### Operating System

#### Recommended

* Ubuntu 22.04 (__Jammy__ Jellyfish)
* Debian 11 (__Bullseye__)

#### Also compatible

* Ubuntu 21.10 (__Impish__ Indri)
* Ubuntu 21.04 (__Hirsute__ Hippo)
* Ubuntu 20.10 (__Groovy__ Gorilla)
* Ubuntu 20.04 (__Focal__ Fossa)
* Ubuntu 19.10 (__Eoan__ Ermine)
* Ubuntu 19.04 (__Disco__ Dingo)
* Ubuntu 18.10 (__Cosmic__ Cuttlefish)
* Ubuntu 18.04 (__Bionic__ Beaver)
* Ubuntu 17.10 (__Artful__ Aardvark)
* Ubuntu 17.04 (__Zesty__ Zapus)
* Ubuntu 16.10 (__Yakkety__ Yak)
* Ubuntu 16.04 (__Xenial__ Xerus)
* Debian 12 (__Bookworm__)
* Debian 10 (__Buster__)
* Debian 9 (__Stretch__)

#### Known issues

* For JPEG XL, CMake 3.10 or newer is required. On older systems (e.g. Debian 9), the maintainers version isn't sufficient. In this case, JPEG XL compilation will be skipped.
* For libaom, CMake 3.6 or newer is required. On older systems, the maintainers version may be not sufficient. In this case, libaom compilation will be skipped. Without libaom, libheif will be skipped too.
* When building using GitHub actions, `heic` isn't reported as built-in delegate. While it did in the past, it stopped out of sudden. So you better avoid using it as assertion for tests.

---

## Usage

### One-Step Automated Install

```bash
t=$(mktemp) && \
wget 'https://dist.1-2.dev/imei.sh' -qO "$t" && \
bash "$t" && \
rm "$t"
```

### Alternative Install Method

```bash
git clone https://github.com/SoftCreatR/imei && \
cd imei && \
chmod +x imei.sh && \
./imei.sh
```

### Verify installer integrity

Though the installer performs a self check upon startup, you can also perform it manually.
To do so, `openssl` is required:

```bash
wget https://dist.1-2.dev/imei.sh && \                                  # Download IMEI
wget https://dist.1-2.dev/imei.sh.sig && \                              # Download signature file
wget https://dist.1-2.dev/imei.sh.pem && \                              # Download public key
openssl dgst -sha512 -verify imei.sh.pem -signature imei.sh.sig imei.sh # Verify
```

### Alternative integrity check

```bash
git clone https://github.com/SoftCreatR/imei && \
cd imei && \
openssl dgst -sha512 -verify imei.sh.pem -signature imei.sh.sig imei.sh
```

#### Options available

Currently available build options are

* `--skip-dependencies` / `--skip-deps` : Skip installation of dependencies
* `--imagemagick-version` / `--im-version` : Build the given ImageMagick version (e.g. `7.0.10-28`)
* `--force-imagemagick` / `--force-im` : Force building of ImageMagick only, even if it's are already installed in a newer or the latest version
* `--imagemagick-quantum-depth` / `--im-q` : ImageMagick Quantum Depth (8, 16 or 32)
* `--aom-version` : Build the given aom version (e.g. `2.0.0`)
* `--skip-aom` : Skip building aom
* `--libheif-version` / `--heif-version` : Build the given libheif version (e.g. `1.8.0`)
* `--skip-libheif` / `--skip-heif` : Skip building libheif
* `--jpeg-xl-version` / `--jxl-version` : Build the given JPEG XL version (e.g. `0.3.3`)
* `--skip-jpeg-xl` / `--skip-jxl` : Skip building JPEG XL
* `--log-file` : Log everything to the file provided
* `--work-dir` : Download, extract & build within the directory provided
* `--build-dir` : Build target directory for ImageMagick
* `--config-dir` : Config target directory for ImageMagick
* `--force` : Force building of components, even if they are already installed in a newer or the latest version

Additional options / switches:

* `--no-sig-verify` / `--dev` : Disable signature verification on startup
* `--use-checkinstall` / `--checkinstall` : Use `checkinstall` instead of `make`
* `--no-backports` : Disable temporary installation of OS backports (they may be used anyways, depending on your server configuration)

**Default options** :

<!-- versions start -->
* ImageMagick version: `7.1.0-53 (Q16)`
* libaom version: `3.5.0`
* libheif version: `1.14.0`
* libjxl version: `0.7.0`<!-- versions end -->
* Log File: `/var/log/imei.log`
* Work Dir: `/usr/local/src/imei`
* Build Dir: `/usr/local`
* Config Dir: `/usr/local/etc`

### checkinstall vs. make

IMEI supports both, `checkinstall` and `make`. While `checkinstall` creates packages that you can uninstall at a later time (e.g. `apt remove imei-imagemagick`), `make` doesn't, therefore it may be harder to remove everything, that has been installed by IMEI. However, `checkinstall` isn't always available and it contains some bugs, that might result in a broken installation of IMEI`s packages.

IMEI uses `make` by default, but you can use `checkinstall` via option (see "Additional options / switches") instead.

---

## Contributing

If you have any ideas, just open an issue and describe what you would like to add/change in IMEI.

If you'd like to contribute, please fork the repository and make changes as you'd like. Pull requests are warmly welcome.

## License 🌳

[ISC](LICENSE.md) © [1-2.dev](https://1-2.dev)

This package is Treeware. If you use it in production, then we ask that you [**buy the world a tree**](https://ecologi.com/softcreatr?r=61212ab3fc69b8eb8a2014f4) to thank us for our work. By contributing to the ecologi project, you’ll be creating employment for local families and restoring wildlife habitats.
