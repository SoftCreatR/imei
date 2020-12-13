"""
Copyright (c) 2020 1-2.dev
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:
The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""

import hashlib
import os
import re
import tempfile
from typing import Dict

import requests

__author__ = "Sascha Greuel"
__copyright__ = "Copyright 2020, Sascha Greuel"
__license__ = "MIT"
__maintainer__ = "Sascha Greuel"
__email__ = "hello@1-2.dev"
__status__ = "Production"

root = os.getcwd() + os.path.sep


def get_versions() -> Dict[str, str]:
    """ Returns a list of version numbers for imagemagick, libaom & libheif """
    api_base = "https://api.github.com/repos"
    file_base = "https://github.com"

    if "GITHUB_TOKEN" in os.environ:
        headers = {"Authorization": "Bearer " + os.environ['GITHUB_TOKEN']}
    else:
        headers = {}

    # Get version information for ImageMagick and write it to file
    data = requests.get(
        api_base + '/ImageMagick/ImageMagick/tags',
        headers=headers
    ).json()
    imagemagick_ver = re.sub(r'[^0-9.\-]', r'', data[1]['name'])
    open(root + 'versions' + os.path.sep + 'imagemagick.version', 'w+').write(imagemagick_ver)

    # Download ImageMagick tarball, calculate it's hash and write it to file
    open(root + 'versions' + os.path.sep + 'imagemagick.hash', 'w+').write(get_hash(
        file_base + '/ImageMagick/ImageMagick/archive/' + imagemagick_ver + '.tar.gz'
    ))

    # Get version information for aom and write it to file
    data = requests.get(
        api_base + '/jbeich/aom/tags',
        headers=headers
    ).json()
    libaom_ver = re.sub(r'[^0-9.]', r'', data[0]['name'])
    open(root + 'versions' + os.path.sep + 'aom.version', 'w+').write(libaom_ver)

    # Download aom tarball, calculate it's hash and write it to file
    open(root + 'versions' + os.path.sep + 'aom.hash', 'w+').write(get_hash(
        file_base + '/jbeich/aom/archive/v' + libaom_ver + '.tar.gz'
    ))

    # Get version information for libheif and write it to file
    data = requests.get(
        api_base + '/strukturag/libheif/tags',
        headers=headers
    ).json()
    libheif_ver = re.sub(r'[^0-9.]', r'', data[0]['name'])
    open(root + 'versions' + os.path.sep + 'libheif.version', 'w+').write(libheif_ver)

    # Download aom tarball, calculate it's hash and write it to file
    open(root + 'versions' + os.path.sep + 'libheif.hash', 'w+').write(get_hash(
        file_base + '/strukturag/libheif/releases/download/v' + libheif_ver + '/libheif-' + libheif_ver + '.tar.gz'
    ))

    # Return version information for README updates
    return {
        'imagemagick': imagemagick_ver,
        'libaom': libaom_ver,
        'libheif': libheif_ver
    }


def get_hash(url):
    """ Returns the SHA1 hash for the given file from URL """
    if "GITHUB_TOKEN" in os.environ:
        headers = {"Authorization": "Bearer " + os.environ['GITHUB_TOKEN']}
    else:
        headers = {}

    sha1 = hashlib.sha1()
    tf = tempfile.NamedTemporaryFile()

    with open(tf.name, "wb") as f:
        response = requests.get(url, headers=headers)
        f.write(response.content)

    with open(tf.name, "rb") as f:
        while True:
            chunk = f.read(sha1.block_size)
            if not chunk:
                break
            sha1.update(chunk)

    return sha1.hexdigest()


if __name__ == '__main__':
    readme_path = root + "README.md"
    readme = open(readme_path, "r").read()
    versions = get_versions()
    replacement = "\n* ImageMagick version: `" + versions['imagemagick'] + "`\n"
    replacement += "* libaom version: `" + versions['libaom'] + "`\n"
    replacement += "* libheif version: `" + versions['libheif'] + "`"

    r = re.compile(
        r'<!-- versions start -->.*<!-- versions end -->'.format(),
        re.DOTALL,
    )

    replacement = '<!-- versions start -->{}<!-- versions end -->'.format(replacement)

    open(readme_path, "w").write(r.sub(replacement, readme))
