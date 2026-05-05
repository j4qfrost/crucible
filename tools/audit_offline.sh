#!/usr/bin/env bash
# tools/audit_offline.sh — composite air-gap audit gate.
#
# Runs every check that bears on the docs/AIR_GAPPED.md commitments
# in one shot. Designed for:
#
#   - operator pre-deployment verification ("is this box clean?")
#   - CI nightly air-gap regression
#   - manual audit during compliance reviews
#
# Steps (sequential; first failure aborts):
#
#   1. tools/check_workspace.py            — 8 invariants (incl. egress baseline)
#   2. tools/inventory_egress.py           — full egress inventory dump
#   3. python -m crucible doctor --offline — Python install + air-gap audit
#   4. crucible doctor --offline           — Julia install + air-gap audit
#                                            (skipped if Julia binary absent)
#
# Exit code = number of failed steps. 0 means every layer is air-gap clean.
#
# Usage:
#   ./tools/audit_offline.sh                  # full audit
#   ./tools/audit_offline.sh --skip-julia     # Python-only (faster on CI)
#   ./tools/audit_offline.sh --quiet          # only print failures + summary

set -uo pipefail   # NOT -e: we tally failures rather than aborting
cd "$(dirname "$0")/.."

SKIP_JULIA=0
QUIET=0
for arg in "$@"; do
  case "$arg" in
    --skip-julia) SKIP_JULIA=1 ;;
    --quiet)      QUIET=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 2 ;;
  esac
done

# Pick the Python interpreter that has crucible installed. Prefer the
# venv so the run reflects the real install — falling back to system
# python lets bare-metal CI use whichever one has the package on path.
PY=""
if [[ -x "python/.venv/bin/python" ]]; then
  PY="python/.venv/bin/python"
elif command -v python3 >/dev/null 2>&1; then
  PY="python3"
elif command -v python >/dev/null 2>&1; then
  PY="python"
else
  echo "audit_offline: no python interpreter found on PATH" >&2
  exit 99
fi

n_failed=0
n_steps=0

run_step() {
  # $1 = step label, rest = command
  local label="$1"; shift
  n_steps=$((n_steps + 1))
  if [[ "$QUIET" == "0" ]]; then
    echo
    echo "=========================================================="
    echo "[$n_steps] $label"
    echo "=========================================================="
  fi
  if "$@"; then
    [[ "$QUIET" == "0" ]] && echo "✓ $label"
  else
    echo "✗ $label (exit $?)" >&2
    n_failed=$((n_failed + 1))
  fi
}

run_step "workspace consistency (incl. egress baseline)" \
  "$PY" tools/check_workspace.py

run_step "egress inventory" \
  "$PY" tools/inventory_egress.py

run_step "Python doctor --offline" \
  "$PY" -m crucible doctor --offline

if [[ "$SKIP_JULIA" == "1" ]]; then
  [[ "$QUIET" == "0" ]] && echo
  [[ "$QUIET" == "0" ]] && echo "(Julia doctor skipped via --skip-julia)"
elif command -v julia >/dev/null 2>&1; then
  # Julia doctor exits with the air-gap error count. We invoke the CLI
  # directly so the existing shebang script handles arg dispatch.
  if [[ -x "bin/crucible" ]]; then
    run_step "Julia crucible doctor --offline" \
      ./bin/crucible doctor --offline
  else
    run_step "Julia crucible doctor --offline" \
      julia --project -e 'include("src/cli/CLI.jl"); exit(Crucible.CLI.cmd_doctor(["--offline"]))'
  fi
else
  [[ "$QUIET" == "0" ]] && echo
  [[ "$QUIET" == "0" ]] && echo "(Julia doctor skipped — julia not on PATH)"
fi

echo
echo "=========================================================="
if [[ "$n_failed" == "0" ]]; then
  echo "✓ air-gap audit clean — $n_steps step(s) passed"
else
  echo "✗ air-gap audit failed — $n_failed of $n_steps step(s) failed"
fi
echo "=========================================================="
exit "$n_failed"
