#!/usr/bin/env bash
# Live integration smoke for the alanine-dipeptide fixture.
#
# Requires OpenMM 8.x (pip install openmm) and Julia 1.10+ with the
# crucible package instantiated.
#
# Usage:
#   ./examples/smoke_alanine_dipeptide.sh
#
# What it does:
#   1. Activates the crucible Project.toml
#   2. Sets CRUCIBLE_RUN_OPENMM=1 so the integration testset actually runs
#   3. Runs Pkg.test() — the live testset hits OpenMM end-to-end on the
#      alanine-dipeptide fixture, ~500 steps in vacuum, target <30 s on CPU.

set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v python >/dev/null 2>&1; then
  echo "python not found on PATH" >&2
  exit 2
fi
if ! python -c 'import openmm' 2>/dev/null; then
  echo "OpenMM not installed in current python; try: pip install openmm" >&2
  exit 2
fi

export CRUCIBLE_RUN_OPENMM=1
export CRUCIBLE_PLATFORM="${CRUCIBLE_PLATFORM:-CPU}"

julia --project -e 'using Pkg; Pkg.test()'
