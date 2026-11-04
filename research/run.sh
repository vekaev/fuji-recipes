#!/usr/bin/env bash
# research/run.sh "description": build, score, print one line. Set EVAL_LIB to the eval library.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build 2>&1 | grep -E "error" && exit 1
FUJI_SIMULATE=1 FUJI_RECIPES="${EVAL_LIB:?set EVAL_LIB to the eval library}" .build/debug/fuji match --score
