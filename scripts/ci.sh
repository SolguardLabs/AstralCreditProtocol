#!/usr/bin/env bash
set -euo pipefail

FORGE="$(bash scripts/find-forge.sh)"

"${FORGE}" fmt --check
"${FORGE}" build
FOUNDRY_PROFILE=ci "${FORGE}" test
npm ci --ignore-scripts
npm test
bash scripts/check-loc.sh
