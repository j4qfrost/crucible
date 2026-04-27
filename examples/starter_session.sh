#!/usr/bin/env bash
# starter_session.sh — full Crucible UX flow without an LLM.
#
# What it does:
#   1. Probes the environment (`crucible doctor`).
#   2. Picks the `vanilla` template + writes a fresh spec.
#   3. Pretty-prints + lints + checks coverage.
#   4. Validates against gates 1-3.
#   5. Renders an OpenMM script (verifying compilation only).
#   6. Asks the cloud advisor for a sizing recommendation.
#   7. Generates a natural-language summary + provenance breakdown.
#
# Run from the repo root:
#   ./examples/starter_session.sh
#
# Output is a workdir at /tmp/crucible-starter-<unix-ts>/ containing:
#   - spec.json               the seeded MDSpec
#   - run_openmm.py           the rendered OpenMM script
#   - explain.md              the natural-language summary
#   - cite.txt                the provenance breakdown
#   - lint.json               the lint report
#
# This is the "happy path" a first-time user follows. No Python, no
# LLM, no GPU — just the IR + render pipeline.

set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
CRUCIBLE="$REPO_ROOT/bin/crucible"
WORKDIR="${WORKDIR:-/tmp/crucible-starter-$(date +%s)}"
mkdir -p "$WORKDIR"

echo "=== 1. crucible doctor ==="
"$CRUCIBLE" doctor || true
echo

echo "=== 2. crucible templates list ==="
"$CRUCIBLE" templates list
echo

echo "=== 3. seed a vanilla spec ==="
"$CRUCIBLE" templates init vanilla --out "$WORKDIR/spec.json"
echo "wrote: $WORKDIR/spec.json"
echo

echo "=== 4. pretty-print in place ==="
"$CRUCIBLE" fmt "$WORKDIR/spec.json" --in-place
echo "fmt OK"
echo

echo "=== 5. lint ==="
"$CRUCIBLE" lint "$WORKDIR/spec.json" --format json > "$WORKDIR/lint.json"
"$CRUCIBLE" lint "$WORKDIR/spec.json"
echo

echo "=== 6. coverage ==="
"$CRUCIBLE" coverage "$WORKDIR/spec.json"
echo

echo "=== 7. validate (gates 1-3) ==="
"$CRUCIBLE" validate "$WORKDIR/spec.json" --backend openmm
echo

echo "=== 8. render OpenMM script ==="
"$CRUCIBLE" render "$WORKDIR/spec.json" --backend openmm --out "$WORKDIR/run_openmm.py"
echo "wrote: $WORKDIR/run_openmm.py ($(wc -c < "$WORKDIR/run_openmm.py") bytes)"
echo

echo "=== 9. cloud sizing ==="
"$CRUCIBLE" advise "$WORKDIR/spec.json" --budget-hours 6
echo

echo "=== 10. explain ==="
"$CRUCIBLE" explain "$WORKDIR/spec.json" | tee "$WORKDIR/explain.md"
echo

echo "=== 11. cite (provenance) ==="
"$CRUCIBLE" cite "$WORKDIR/spec.json" | tee "$WORKDIR/cite.txt"
echo

echo "=== 12. trajstat (workdir is empty until you run; this is a smoke check) ==="
"$CRUCIBLE" trajstat "$WORKDIR" || true
echo

echo "Done. Workdir: $WORKDIR"
echo
echo "Next steps:"
echo "  1. To execute the script: pip install openmm && python $WORKDIR/run_openmm.py"
echo "  2. To analyze outputs: $CRUCIBLE analyze $WORKDIR --format markdown"
echo "  3. To package + share:  $CRUCIBLE snapshot $WORKDIR --out session.tar.gz"
