#!/usr/bin/env bash
set -euo pipefail

if command -v forge >/dev/null 2>&1; then
  command -v forge
  exit 0
fi

if command -v forge.exe >/dev/null 2>&1; then
  command -v forge.exe
  exit 0
fi

if [[ -n "${FOUNDRY_HOME:-}" && -x "${FOUNDRY_HOME}/bin/forge" ]]; then
  printf '%s\n' "${FOUNDRY_HOME}/bin/forge"
  exit 0
fi

if [[ -n "${FOUNDRY_HOME:-}" && -x "${FOUNDRY_HOME}/bin/forge.exe" ]]; then
  printf '%s\n' "${FOUNDRY_HOME}/bin/forge.exe"
  exit 0
fi

printf 'forge executable not found\n' >&2
exit 1
