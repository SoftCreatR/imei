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

import os
import re
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
    if "GITHUB_TOKEN" in os.environ:
        headers = {"Authorization": "Bearer " + os.environ['GITHUB_TOKEN']}
    else:
        headers = {}

    data = requests.get('https://api.github.com/repos/ImageMagick/ImageMagick/releases/latest', headers=headers).json()
    imagemagick_version = re.sub(r'[^0-9.\-]', r'', data['tag_name'])

    data = requests.get('https://api.github.com/repos/jbeich/aom/tags', headers=headers).json()
    libaom_version = re.sub(r'[^0-9.]', r'', data[0]['name'])

    data = requests.get('https://api.github.com/repos/strukturag/libheif/releases/latest', headers=headers).json()
    libheif_version = re.sub(r'[^0-9.]', r'', data['tag_name'])

    return {
        'imagemagick': imagemagick_version,
        'libaom': libaom_version,
        'libheif': libheif_version
    }


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

    # Update version files
    for key, value in versions.items():
        file = open(root + 'versions' + os.path.sep + key + '.version', 'w+').write(value)
