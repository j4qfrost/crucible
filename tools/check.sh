#!/usr/bin/env bash
# tools/check.sh — full pre-commit check.
#
# Runs the same gates the verification routine would run, in this order:
#
#   1. Pkg.test() — full unit + deterministic integration suite
#   2. tools/regenerate_docs.jl — fail if docs/IR.md is stale relative
#      to src/spec/schema.json
#   3. tools/regenerate_fixtures.sh check — fail if the recorded
#      AnthropicProvider fixture has drifted (only when ANTHROPIC_API_KEY
#      is set; skipped silently otherwise)
#
# Usage:
#   ./tools/check.sh                 # all gates
#   ./tools/check.sh --skip-fixtures # skip the LLM drift check
#
# Exit codes: 0 = all green, non-zero = at least one gate failed.

set -euo pipefail
cd "$(dirname "$0")/.."

SKIP_FIXTURES=0
[[ "${1:-}" == "--skip-fixtures" ]] && SKIP_FIXTURES=1

echo "=========================================================="
echo "[1/3] julia --project -e 'using Pkg; Pkg.test()'"
echo "=========================================================="
julia --project -e 'using Pkg; Pkg.test()'

echo
echo "=========================================================="
echo "[2/3] regenerate docs/IR.md and check for changes"
echo "=========================================================="
cp docs/IR.md docs/IR.md.before-check
julia --project tools/regenerate_docs.jl
if ! cmp -s docs/IR.md docs/IR.md.before-check; then
  echo "ERROR: docs/IR.md was out of date. Regenerated; please commit." >&2
  diff -u docs/IR.md.before-check docs/IR.md >&2 || true
  rm -f docs/IR.md.before-check
  exit 3
fi
rm -f docs/IR.md.before-check

echo
echo "=========================================================="
echo "[3/3] AnthropicProvider fixture drift check"
echo "=========================================================="
if [[ "$SKIP_FIXTURES" == "1" ]]; then
  echo "(skipped via --skip-fixtures)"
elif [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "(skipped — ANTHROPIC_API_KEY not set)"
else
  ./tools/regenerate_fixtures.sh check
fi

echo
echo "=========================================================="
echo "all gates green"
echo "=========================================================="
