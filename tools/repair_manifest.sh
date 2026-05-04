#!/usr/bin/env bash
# tools/repair_manifest.sh — make Manifest.toml match the local Julia.
#
# Why this exists:
#   Manifest.toml in the workspace ended up root-owned and pinned to
#   julia_version = "1.10.11" while the local interpreter on this
#   machine is 1.12.x. The full Julia test suite refuses to run until
#   the two agree. This is a one-shot repair, idempotent, but
#   destructive (regenerates Manifest.toml from Project.toml).
#
# What it does:
#   1. If Manifest.toml is owned by someone other than the current
#      user, chown it (requires sudo). Skipped if already user-owned.
#   2. Removes Manifest.toml.
#   3. Runs Pkg.instantiate() to regenerate against local Julia.
#   4. Prints the resulting julia_version line so you can confirm.
#
# Usage:
#   bash tools/repair_manifest.sh
#
# Cross-reference: docs/PLAN.md "v0.3 task #14" (Manifest policy).

set -euo pipefail

cd "$(dirname "$0")/.."

MANIFEST="Manifest.toml"

if [[ ! -f "$MANIFEST" ]]; then
    echo "[repair-manifest] no $MANIFEST present — will let Pkg create one fresh."
else
    OWNER="$(stat -c '%U' "$MANIFEST")"
    ME="$(id -un)"
    if [[ "$OWNER" != "$ME" ]]; then
        echo "[repair-manifest] $MANIFEST is owned by $OWNER, not $ME — sudo chown."
        sudo chown "$ME" "$MANIFEST"
    else
        echo "[repair-manifest] $MANIFEST already owned by $ME."
    fi
    PINNED="$(grep -E '^julia_version' "$MANIFEST" | head -1 || true)"
    echo "[repair-manifest] current pin: $PINNED"
    rm -f "$MANIFEST"
fi

if ! command -v julia >/dev/null 2>&1; then
    echo "[repair-manifest] julia not on PATH; install Julia 1.10+ and re-run." >&2
    exit 1
fi

echo "[repair-manifest] running Pkg.instantiate() against $(julia --version)..."
julia --project=. -e 'using Pkg; Pkg.instantiate()'

if [[ -f "$MANIFEST" ]]; then
    NEW_PIN="$(grep -E '^julia_version' "$MANIFEST" | head -1 || true)"
    echo "[repair-manifest] new pin: $NEW_PIN"
    echo "[repair-manifest] done. Run \`julia --project -e 'using Pkg; Pkg.test()'\` to verify."
else
    echo "[repair-manifest] WARNING: Pkg.instantiate did not produce $MANIFEST." >&2
    exit 1
fi
