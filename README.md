<div align=center>

# IMEI - ImageMagick Easy Install
#### Automated ImageMagick compilation from sources for Debian/Ubuntu including advanced delegate support.

[![Build](https://img.shields.io/github/workflow/status/SoftCreatR/imei/Main?style=flat-square)](https://github.com/SoftCreatR/imei/actions/workflows/Main.yml)

[![Commits](https://img.shields.io/github/last-commit/SoftCreatR/imei?style=flat-square)](https://github.com/SoftCreatR/imei/commits/main) [![GitHub release](https://img.shields.io/github/release/SoftCreatR/imei?style=flat-square)](https://github.com/SoftCreatR/imei/releases) [![GitHub license](https://img.shields.io/github/license/SoftCreatR/imei?style=flat-square&color=lightgray)](LICENSE.md) ![Installs](https://img.shields.io/badge/dynamic/json?style=flat-square&color=blue&label=installs&query=value&url=https%3A%2F%2Fapi.countapi.xyz%2Fget%2Fsoftcreatr%2Fimei) [![GitHub file size in bytes](https://img.shields.io/github/size/SoftCreatR/imei/imei.sh?style=flat-square)](https://github.com/SoftCreatR/imei/blob/main/imei.sh)

[![Codacy grade](https://img.shields.io/codacy/grade/db0b2b5f22454f4280e4623de9f7075f?style=flat-square&label=codacy%20grade)](https://app.codacy.com/gh/SoftCreatR/imei/dashboard) [![CodeFactor Grade](https://img.shields.io/codefactor/grade/github/SoftCreatR/imei?style=flat-square&label=codefactor%20rating)](https://www.codefactor.io/repository/github/softcreatr/imei)

</div>

---

<div align="center">

<a href="#features"> Features<a> •
<a href="#compatibility"> Compatibility</a> •
<a href="#usage"> Usage</a> •
<a href="#contributing"> Contributing</a> •
<a href="#license"> License</a>

![Screenshot](imei.png)

</div>

---

## Features

* Compiles the latest ImageMagick release
* Installs ImageMagick or updates ImageMagick package previously installed (via IMEI)
* Additional HEIF support
* Additional HEIX support
* Additional AVIF support
* Additional JPEG XL support

---

## Compatibility

Every IMEI build will be automatically tested against the latest Ubuntu LTS Versions (16.04 and newer) using GitHub Actions. Compatibility with other operating systems (such as Debian 10) is tested manually.

### Operating System

#### Recommended

* Ubuntu 21.04 (__Hirsute__ Hippo)
* Ubuntu 20.10 (__Groovy__ Gorilla)
* Ubuntu 20.04 LTS (__Focal__ Fossa)
* Ubuntu 18.04 LTS (__Bionic__ Beaver)
* Debian 10 (__Buster__)
* Raspbian 10 (__Buster__)

#### Also compatible

* Ubuntu 19.10 (__Eoan__ Ermine)
* Ubuntu 16.04 LTS (__Xenial__ Xerus)
* Debian 9 (__Stretch__)
* Raspbian 9 (__Stretch__)

#### Known issues

* For JPEG XL, CMake 3.10 or newer is required. On older systems (e.g. Debian 9), the maintainers version isn't sufficient. In this case, JPEG XL compilation will be skipped

---

## Usage

### One-Step Automated Install

```bash
bash <(curl -sL dist.1-2.dev/imei) --no-sig-verify
```

### Alternative Install Method

```bash
git clone https://github.com/SoftCreatR/imei
cd imei
sudo ./imei.sh
```

### Verify installer integrity

Though the installer performs a self check upon startup, you can also perform it manually.
To do so, `openssl` is required:

```bash
wget https://dist.1-2.dev/imei && \                                    # Download IMEI
wget https://dist.1-2.dev/imei.sh.sig && \                             # Download signature file
wget https://dist.1-2.dev/public.pem && \                              # Download public key
openssl dgst -sha512 -verify public.pem -signature imei.sh.sig imei.sh # Verify
```

### Alternative integrity check

```bash
git clone https://github.com/SoftCreatR/imei
cd imei
openssl dgst -sha512 -verify public.pem -signature imei.sh.sig imei.sh
```

#### Options available

Currently available build options are

* `--skip-dependencies` / `--skip-deps` : Skip installation of dependencies
* `--imagemagick-version` / `--im-version` : Build the given ImageMagick version (e.g. `7.0.10-28`)
* `--aom-version` : Build the given aom version (e.g. `2.0.0`)
* `--skip-aom` : Skip building aom
* `--libheif-version` / `--heif-version` : Build the given libheif version (e.g. `1.8.0`)
* `--skip-libheif` / `--skip-heif` : Skip building libheif
* `--jpeg-xl-version` / `--jxl-version` : Build the given JPEG XL version (e.g. `0.3.3`)
* `--skip-jpeg-xl` / `--skip-jxl` : Skip building JPEG XL
* `--log-file` : Log everything to the file provided
* `--work-dir` : Download, extract & build within the directory provided
* `--build-dir` : Build target directory
* `--force` : Force building of components, even if they are already installed in a newer or the latest version
* `--no-sig-verify` / `--dev` : Disable signature verification on startup

**Default options** :

<!-- versions start -->
* ImageMagick version: `7.1.0-2`
* libaom version: `3.1.1`
* libheif version: `1.12.0`
* libjxl version: `0.3.7`<!-- versions end -->
* Log File: `/var/log/imei.log`
* Work Dir: `/usr/local/src/imei`
* Build Dir: `/usr/local`

---

## Contributing

If you have any ideas, just open an issue and describe what you would like to add/change in IMEI.

If you'd like to contribute, please fork the repository and make changes as you'd like. Pull requests are warmly welcome.

## License

[ISC](LICENSE.md) © [1-2.dev](https://1-2.dev)
