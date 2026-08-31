#!/bin/bash

# Ask interactive Codex TUIs to redraw after the terminal palette changes.
# SIGWINCH is the normal terminal-resize notification. It does not restart a
# session, alter its transcript, or make an API request.

set -u

proc_root=${THEMEFLOW_PROC_ROOT:-/proc}
dry_run=false

if [[ ${1:-} == "--dry-run" ]]; then
  dry_run=true
fi

for process_dir in "${proc_root}"/[0-9]*; do
  [[ -d ${process_dir} ]] || continue
  pid=${process_dir##*/}

  [[ -r ${process_dir}/comm && -r ${process_dir}/cmdline ]] || continue
  IFS= read -r comm <"${process_dir}/comm" || continue
  [[ ${comm} == "codex" ]] || continue

  stdin_target=$(readlink "${process_dir}/fd/0" 2>/dev/null) || continue
  stdout_target=$(readlink "${process_dir}/fd/1" 2>/dev/null) || continue
  [[ ${stdin_target} == /dev/pts/* || ${stdin_target} == /dev/tty* ]] || continue
  [[ ${stdout_target} == /dev/pts/* || ${stdout_target} == /dev/tty* ]] || continue

  argv=()
  mapfile -d '' -t argv <"${process_dir}/cmdline" || continue
  [[ ${#argv[@]} -gt 0 ]] || continue

  is_non_tui=false
  for arg in "${argv[@]:1}"; do
    case ${arg} in
      app-server|exec|exec-server|mcp-server|review)
        is_non_tui=true
        break
        ;;
    esac
  done
  [[ ${is_non_tui} == false ]] || continue

  if [[ ${dry_run} == true ]]; then
    printf '%s\n' "${pid}"
  else
    kill -WINCH -- "${pid}" 2>/dev/null || true
  fi
done
