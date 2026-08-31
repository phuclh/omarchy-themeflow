#!/bin/bash

set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURE_ROOT=$(mktemp -d)
trap 'rm -rf -- "${FIXTURE_ROOT}"' EXIT

add_process() {
  local pid=$1
  local comm=$2
  shift 2

  mkdir -p "${FIXTURE_ROOT}/${pid}/fd"
  printf '%s\n' "${comm}" >"${FIXTURE_ROOT}/${pid}/comm"
  printf '%s\0' "$@" >"${FIXTURE_ROOT}/${pid}/cmdline"
  ln -s /dev/pts/10 "${FIXTURE_ROOT}/${pid}/fd/0"
  ln -s /dev/pts/10 "${FIXTURE_ROOT}/${pid}/fd/1"
}

add_process 101 codex codex
add_process 102 codex codex resume
add_process 103 codex codex -c features.code_mode_host=true app-server
add_process 104 codex codex exec "status"
add_process 105 bash bash
add_process 107 codex codex fork
add_process 108 codex codex review

mkdir -p "${FIXTURE_ROOT}/106/fd"
printf '%s\n' codex >"${FIXTURE_ROOT}/106/comm"
printf '%s\0' codex >"${FIXTURE_ROOT}/106/cmdline"
ln -s /dev/null "${FIXTURE_ROOT}/106/fd/0"
ln -s /dev/null "${FIXTURE_ROOT}/106/fd/1"

actual=$(THEMEFLOW_PROC_ROOT="${FIXTURE_ROOT}" \
  "${ROOT_DIR}/scripts/refresh-codex-tui.sh" --dry-run)
expected=$'101\n102\n107'

if [[ ${actual} != "${expected}" ]]; then
  printf 'Expected refresh candidates:\n%s\nActual:\n%s\n' "${expected}" "${actual}" >&2
  exit 1
fi

printf '%s\n' "Codex TUI refresh tests passed"
