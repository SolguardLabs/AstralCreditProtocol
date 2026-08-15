#!/usr/bin/env bash
set -euo pipefail

FORGE="$(bash scripts/find-forge.sh)"
"${FORGE}" test
npm test
