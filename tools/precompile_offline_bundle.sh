#!/usr/bin/env bash
# tools/precompile_offline_bundle.sh — package everything needed to
# install + run Crucible behind an air-gap into one transportable
# tarball.
#
# Bundles (in order; each layer skippable):
#
#   1. Python wheels        — pip download python[corpus,llm-anthropic]
#   2. Julia depot          — Pkg.instantiate output, tarred
#   3. OpenMM environment   — pip download into a separate dir (no conda dep)
#   4. Ollama model weights — tar of ~/.ollama/models
#   5. Source tree + docs   — git archive of the repo
#   6. Manifest + SHA256s   — for verification on the target side
#
# Closes the doc-to-deployment gap. AIR_GAPPED.md describes the
# six-step manual install; this script makes it one command.
#
# Usage:
#
#   tools/precompile_offline_bundle.sh \
#       --out crucible-airgap-v1.86.tar.gz \
#       [--openmm]                          # include OpenMM wheels
#       [--ollama-model qwen2.5-coder:7b]   # bundle this model
#       [--ollama-model gemma3:4b]          # repeatable for multiple
#       [--skip-julia]                      # source-only bundle
#       [--skip-python]                     # rare; for julia-only deploys
#       [--keep-staging]                    # leave staging dir intact for inspection
#
# Verify the bundle on the target side with:
#
#   tools/verify_offline_bundle.sh crucible-airgap-v1.86.tar.gz

set -euo pipefail
cd "$(dirname "$0")/.."

# -----------------------------------------------------------------------------
# Defaults + arg parsing.

OUT=""
INCLUDE_OPENMM=0
SKIP_JULIA=0
SKIP_PYTHON=0
KEEP_STAGING=0
OLLAMA_MODELS=()

usage() {
  sed -n '2,30p' "$0" >&2
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)            OUT="$2"; shift 2 ;;
    --openmm)         INCLUDE_OPENMM=1; shift ;;
    --ollama-model)   OLLAMA_MODELS+=("$2"); shift 2 ;;
    --skip-julia)     SKIP_JULIA=1; shift ;;
    --skip-python)    SKIP_PYTHON=1; shift ;;
    --keep-staging)   KEEP_STAGING=1; shift ;;
    -h|--help)        usage ;;
    *)                echo "unknown flag: $1" >&2; usage ;;
  esac
done

if [[ -z "$OUT" ]]; then
  # Auto-name from the latest CHANGELOG version + date.
  ver=$(grep -m1 -oE 'v[0-9]+\.[0-9]+' CHANGELOG.md | head -1 || echo "vUNKNOWN")
  OUT="crucible-airgap-${ver}-$(date +%Y%m%d).tar.gz"
fi

# Resolve to absolute path so cd's later don't break the target.
case "$OUT" in
  /*) ;;
  *)  OUT="$PWD/$OUT" ;;
esac

# -----------------------------------------------------------------------------
# Staging.

STAGING=$(mktemp -d -t crucible-bundle.XXXXXX)
echo "==> staging dir: $STAGING"

cleanup() {
  if [[ "$KEEP_STAGING" == "0" ]]; then
    rm -rf "$STAGING"
  else
    echo "==> staging kept: $STAGING"
  fi
}
trap cleanup EXIT

mkdir -p \
  "$STAGING/python-wheels" \
  "$STAGING/openmm-wheels" \
  "$STAGING/julia-depot" \
  "$STAGING/ollama-models" \
  "$STAGING/source"

# -----------------------------------------------------------------------------
# 1. Python wheels.

if [[ "$SKIP_PYTHON" == "0" ]]; then
  PIP=""
  if [[ -x "python/.venv/bin/pip" ]]; then
    PIP="python/.venv/bin/pip"
  elif command -v pip3 >/dev/null 2>&1; then
    PIP="pip3"
  elif command -v pip >/dev/null 2>&1; then
    PIP="pip"
  fi
  if [[ -n "$PIP" ]]; then
    echo "==> [1/6] downloading Python wheels (corpus + llm-anthropic)"
    # Download the package and every transitive runtime dep into the
    # wheels dir. -e is for editable installs only; we want the
    # resolved wheel set so the target can install offline.
    "$PIP" download \
      --dest "$STAGING/python-wheels" \
      --no-cache-dir \
      "./python[corpus,llm-anthropic]" 2>&1 | tail -20
    n_wheels=$(find "$STAGING/python-wheels" -name '*.whl' -o -name '*.tar.gz' | wc -l)
    echo "    bundled $n_wheels Python artifact(s)"
  else
    echo "==> [1/6] skipped — no pip on PATH"
  fi
else
  echo "==> [1/6] skipped (--skip-python)"
fi

# -----------------------------------------------------------------------------
# 2. Julia depot.

if [[ "$SKIP_JULIA" == "0" ]]; then
  if command -v julia >/dev/null 2>&1; then
    echo "==> [2/6] resolving Julia deps + tarring depot"
    # Use a *throwaway* depot rooted in staging so we capture *only*
    # the project's transitive deps — the user's full ~/.julia is way
    # too large and would include unrelated packages.
    SUBDEPOT="$STAGING/julia-depot/depot"
    mkdir -p "$SUBDEPOT"
    JULIA_DEPOT_PATH="$SUBDEPOT" julia --project -e \
      'using Pkg; Pkg.instantiate(); Pkg.precompile()' 2>&1 | tail -10
    depot_size=$(du -sh "$SUBDEPOT" | cut -f1)
    echo "    depot size: $depot_size"
  else
    echo "==> [2/6] skipped — julia not on PATH"
  fi
else
  echo "==> [2/6] skipped (--skip-julia)"
fi

# -----------------------------------------------------------------------------
# 3. OpenMM wheels (optional).

if [[ "$INCLUDE_OPENMM" == "1" ]]; then
  if [[ -n "${PIP:-}" ]]; then
    echo "==> [3/6] downloading OpenMM + scientific Python stack"
    "$PIP" download \
      --dest "$STAGING/openmm-wheels" \
      --no-cache-dir \
      openmm pdbfixer mdtraj openmmtools openff-toolkit 2>&1 | tail -10 || \
      echo "    (some openff-stack wheels may not be available; that's OK)"
    n_wheels=$(find "$STAGING/openmm-wheels" -name '*.whl' -o -name '*.tar.gz' | wc -l)
    echo "    bundled $n_wheels OpenMM artifact(s)"
  else
    echo "==> [3/6] --openmm requested but no pip available; skipped"
  fi
else
  echo "==> [3/6] skipped (--openmm not set)"
fi

# -----------------------------------------------------------------------------
# 4. Ollama models (optional, repeatable).

if [[ "${#OLLAMA_MODELS[@]}" -gt 0 ]]; then
  if command -v ollama >/dev/null 2>&1; then
    echo "==> [4/6] bundling Ollama models: ${OLLAMA_MODELS[*]}"
    # Pull each model first (no-op if already cached).
    for model in "${OLLAMA_MODELS[@]}"; do
      ollama pull "$model" 2>&1 | tail -3 || true
    done
    # Tar the entire local Ollama store. The target side restores via
    # `tar -xzf ollama-models.tar.gz -C ~/.ollama && ollama serve`.
    if [[ -d "$HOME/.ollama" ]]; then
      tar czf "$STAGING/ollama-models/ollama-store.tar.gz" \
        -C "$HOME" .ollama
      ollama_size=$(du -sh "$STAGING/ollama-models/ollama-store.tar.gz" | cut -f1)
      echo "    ollama tarball: $ollama_size"
    else
      echo "    ~/.ollama not found; skipping"
    fi
  else
    echo "==> [4/6] --ollama-model set but ollama not on PATH; skipped"
  fi
else
  echo "==> [4/6] skipped (no --ollama-model passed)"
fi

# -----------------------------------------------------------------------------
# 5. Source tree (via git archive — clean, no .git/, no untracked).

echo "==> [5/6] git archive of source tree"
git archive --format=tar --prefix=crucible/ HEAD | \
  tar -x -C "$STAGING/source"
echo "    HEAD = $(git rev-parse HEAD)"
echo "    branch = $(git rev-parse --abbrev-ref HEAD)"

# -----------------------------------------------------------------------------
# 6. Manifest.

echo "==> [6/6] writing manifest"
HEAD_SHA=$(git rev-parse HEAD)
HEAD_BRANCH=$(git rev-parse --abbrev-ref HEAD)
# Subshell so the cd stays scoped — otherwise the parent shell's PWD
# leaks and breaks the final `git rev-parse --short` in the summary.
(
  echo "# Crucible offline bundle manifest"
  echo "# Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "# Host: $(hostname)"
  echo "# Source HEAD: $HEAD_SHA"
  echo "# Source branch: $HEAD_BRANCH"
  echo "# Python wheels: $(find "$STAGING/python-wheels" -type f | wc -l) file(s)"
  echo "# OpenMM wheels: $(find "$STAGING/openmm-wheels" -type f | wc -l) file(s)"
  echo "# Julia depot:   $(du -sb "$STAGING/julia-depot" 2>/dev/null | cut -f1) bytes"
  echo "# Ollama tar:    $(find "$STAGING/ollama-models" -type f | wc -l) file(s)"
  echo "# Source files:  $(find "$STAGING/source" -type f | wc -l) file(s)"
  echo
  echo "# SHA256 sums of every bundled artifact:"
  cd "$STAGING"
  find . -type f ! -name MANIFEST.txt -print0 | \
    sort -z | xargs -0 sha256sum
) > "$STAGING/MANIFEST.txt"

# -----------------------------------------------------------------------------
# Pack.

echo "==> packing bundle → $OUT"
tar czf "$OUT" -C "$STAGING" .
bundle_size=$(du -sh "$OUT" | cut -f1)
echo
echo "=========================================================="
echo "✓ bundle ready: $OUT  ($bundle_size)"
echo "  HEAD: $(git rev-parse --short HEAD)"
echo "  manifest: tar tzf $OUT | head, then ./MANIFEST.txt for SHA256 sums"
echo "  verify:   tools/verify_offline_bundle.sh $OUT"
echo "=========================================================="
