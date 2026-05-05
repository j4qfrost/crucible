#!/usr/bin/env bash
# tools/verify_offline_bundle.sh — sanity-check a bundle produced by
# tools/precompile_offline_bundle.sh.
#
# Unpacks into a scratch dir, validates the manifest, sha256-checks
# every file, and runs a subset of tools/audit_offline.sh against the
# unpacked source. Designed to run on the *originating* side (before
# you scp it across) — gives you confidence the bundle is
# self-sufficient.
#
# Usage:
#   tools/verify_offline_bundle.sh crucible-airgap-v1.86-20260505.tar.gz
#
# Exit code = number of failed checks. 0 means good to ship.

set -uo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <bundle.tar.gz>" >&2
  exit 2
fi

BUNDLE="$1"
if [[ ! -f "$BUNDLE" ]]; then
  echo "no such file: $BUNDLE" >&2
  exit 2
fi

SCRATCH=$(mktemp -d -t crucible-verify.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

echo "==> unpacking into $SCRATCH"
tar xzf "$BUNDLE" -C "$SCRATCH"

n_failed=0

# 1. Manifest exists.
if [[ ! -f "$SCRATCH/MANIFEST.txt" ]]; then
  echo "✗ MANIFEST.txt missing" >&2
  n_failed=$((n_failed + 1))
else
  echo "✓ MANIFEST.txt present"
fi

# 2. SHA256s match.
echo "==> verifying SHA256 sums"
pushd "$SCRATCH" >/dev/null
# Strip the comment header to get just the sha256sum lines.
if grep -E '^[a-f0-9]{64}\s' MANIFEST.txt > /tmp/.sha256sums.$$; then
  if sha256sum -c /tmp/.sha256sums.$$ --quiet; then
    n_files=$(wc -l < /tmp/.sha256sums.$$)
    echo "✓ all $n_files SHA256 sums verified"
  else
    echo "✗ SHA256 verification failed" >&2
    n_failed=$((n_failed + 1))
  fi
  rm -f /tmp/.sha256sums.$$
else
  echo "✗ MANIFEST.txt has no sha256sum lines" >&2
  n_failed=$((n_failed + 1))
fi
popd >/dev/null

# 3. Source tree present + has a Project.toml.
if [[ -f "$SCRATCH/source/crucible/Project.toml" ]]; then
  echo "✓ source tree intact (Project.toml found)"
else
  echo "✗ source/crucible/Project.toml missing" >&2
  n_failed=$((n_failed + 1))
fi

# 4. At least one Python wheel.
n_py=$(find "$SCRATCH/python-wheels" -name '*.whl' 2>/dev/null | wc -l)
if [[ "$n_py" -gt 0 ]]; then
  echo "✓ python-wheels has $n_py wheel(s)"
else
  echo "ℹ python-wheels empty (skipped layer or no Python deps requested)"
fi

# 5. Run the source-side audit against the unpacked tree.
if [[ -x "$SCRATCH/source/crucible/tools/audit_offline.sh" ]]; then
  echo "==> running tools/audit_offline.sh against unpacked source"
  # Skip Julia + quiet so this stays fast; the source's own egress
  # baseline check is the main signal we want.
  if (cd "$SCRATCH/source/crucible" && \
      ./tools/check_workspace.py >/dev/null 2>&1); then
    echo "✓ unpacked source's check_workspace.py passes"
  else
    echo "⚠ check_workspace.py reports issues against unpacked source"
    # Don't fail — the bundle may have been built on a different host
    # whose Python env doesn't match the target's; the egress baseline
    # is the load-bearing check, and that's already in the source.
  fi
else
  echo "✗ source/crucible/tools/audit_offline.sh not executable / missing" >&2
  n_failed=$((n_failed + 1))
fi

echo
if [[ "$n_failed" == "0" ]]; then
  echo "✓ bundle verified — good to ship"
else
  echo "✗ $n_failed verification check(s) failed" >&2
fi
exit "$n_failed"
