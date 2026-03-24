#!/usr/bin/env bash

#
# Print the synthetic IMEI release tag derived from the tracked component versions.
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/common.sh"

stack_release_tag
