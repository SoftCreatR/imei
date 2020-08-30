<div align=center>

![Logo](https://raw.githubusercontent.com/SoftCreatR/imei/main/imei-logo.png)

# IMEI - ImageMagick Easy Install
#### Automated ImageMagick compilation from sources for Debian/Ubuntu including advanced delegate support.

[![Build Status](https://travis-ci.com/SoftCreatR/imei.svg?branch=main)](https://travis-ci.com/SoftCreatR/imei) ![Stars](https://img.shields.io/github/stars/SoftCreatR/imei.svg) ![Commits](https://img.shields.io/github/last-commit/SoftCreatR/imei/main.svg?style=flat)  
![GitHub release](https://img.shields.io/github/release/SoftCreatR/imei?style=flat) [![Codacy Badge](https://app.codacy.com/project/badge/Grade/325d797fcbbf44df9dbed8af3ba8e1f4)](https://www.codacy.com?utm_source=github.com&amp;utm_medium=referral&amp;utm_content=SoftCreatR/imei&amp;utm_campaign=Badge_Grade) [![CodeFactor](https://www.codefactor.io/repository/github/softcreatr/imei/badge?s=5d18e033891edfd7ee145472db7d46b9a0ec3b11)](https://www.codefactor.io/repository/github/softcreatr/imei)

</div>

---

<div align="center">

<a href="#features"> Features<a> •
<a href="#compatibility"> Compatibility</a> •
<a href="#usage"> Usage</a> •
<a href="#roadmap"> Roadmap</a> •
<a href="#contributing"> Contributing</a> •
<a href="#license"> License</a>

![Screenshot](https://raw.githubusercontent.com/SoftCreatR/imei/main/imei.png)

</div>

---

## Features

* Compiles the latest ImageMagick release
* Installs ImageMagick or replaces ImageMagick package previously installed
* Additional HEIF support
* Additional HEIX support
* Additional AVIF support

---

## Compatibility

Every IMEI build will be automatically tested against the latest Ubuntu LTS Versions (16.04 and newer) using Travis CI. Compatibility with other operating systems (such as Debian 10) is tested manually.

### Operating System

#### Recommended

* Ubuntu 20.04 LTS (__Focal__ Fossa)
* Ubuntu 18.04 LTS (__Bionic__ Beaver)
* Debian 10 (__Buster__)
* Raspbian 10 (__Buster__)

#### Also compatible

* Ubuntu 19.10 (__Eoan__ Ermine)
* Ubuntu 16.04 LTS (__Xenial__ Xerus)
* Debian 9 (__Stretch__)
* Raspbian 9 (__Stretch__)

---

## Usage

### One-Step Automated Install

**Default settings** :

* ImageMagick: Latest
* aom: Latest
* libheif: Latest

```bash
$ wget -qO - 1-2.dev/imei | bash
```

### Alternative Install Method

```bash
$ git clone https://github.com/SoftCreatR/imei
$ cd imei
$ sudo imei.sh
```

---

## Roadmap

* [ ] Add cronjob for automatic updates
* [ ] Add ImageMagick modules choice

## Contributing

If you have any ideas, just open an issue and describe what you would like to add/change in IMEI.

If you'd like to contribute, please fork the repository and make changes as you'd like. Pull requests are warmly welcome.

## License

[MIT](https://github.com/SoftCreatR/imei/blob/main/LICENSE) © [1-2.dev](https://1-2.dev)
