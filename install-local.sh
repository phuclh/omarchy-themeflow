#!/bin/bash

set -euo pipefail

PLUGIN_ID="io.github.phuclh.themeflow"
SOURCE_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
CONFIG_BASE=${XDG_CONFIG_HOME:-"${HOME}/.config"}
PLUGIN_ROOT="${CONFIG_BASE}/omarchy/plugins"
TARGET_DIR="${PLUGIN_ROOT}/${PLUGIN_ID}"

if [[ -e ${TARGET_DIR} || -L ${TARGET_DIR} ]]; then
  echo "Themeflow is already installed at ${TARGET_DIR}" >&2
  echo "Remove or update that installation before running this installer again." >&2
  exit 1
fi

omarchy plugin validate "${SOURCE_DIR}"
mkdir -p "${PLUGIN_ROOT}"
cp -a "${SOURCE_DIR}" "${TARGET_DIR}"

omarchy-shell shell rescanPlugins >/dev/null
omarchy plugin enable "${PLUGIN_ID}" --section right

echo "Themeflow installed and enabled."
