import os
import pathlib
import re

import requests

root = pathlib.Path(__file__).parent.resolve()


def get_versions():
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
    versions = get_versions()

    for key, value in versions.items():
        file = open('versions/' + key + '.version', 'w+').write(value)
