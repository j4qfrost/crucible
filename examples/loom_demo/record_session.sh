#!/usr/bin/env bash
# Loom demo — exact commands for the 60-second record session.
# Cross-reference: docs/LOOM_DEMO_SCRIPT.md scene-by-scene script.
#
# Pre-flight (NOT part of the record): `crucible doctor && crucible templates list`
# to warm the Julia JIT so the recorded session looks instant.
#
# Run from the Crucible repo root after pre-flight:
#     bash examples/loom_demo/record_session.sh

set -e

cd "$(dirname "$0")/../.."

# Scene 0:18 — transpile.
echo '$ crucible transpile --paper examples/loom_demo/methods.txt --provider local'
crucible transpile --paper examples/loom_demo/methods.txt --provider local --out /tmp/spec.json
echo
head -12 /tmp/spec.json
echo "..."
echo

# Scene 0:32 — health gates.
echo '$ crucible health /tmp/spec.json'
crucible health /tmp/spec.json
echo

# Scene 0:42 — render.
echo '$ crucible render /tmp/spec.json --backend openmm | head -15'
crucible render /tmp/spec.json --backend openmm | head -15
echo "..."
