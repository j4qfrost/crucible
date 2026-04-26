#!/usr/bin/env bash
# Regenerate test fixtures from live providers.
#
# Specifically: re-runs AnthropicProvider against
# test/fixtures/sample_md_methods.txt and writes the resulting MDSpec to
# test/fixtures/recorded_anthropic_spec.json. Also prints SHA256 hashes
# of the before/after files so callers can decide whether to commit the
# refresh.
#
# Requires: ANTHROPIC_API_KEY in env.
#
# Usage:
#   ./tools/regenerate_fixtures.sh        # write + diff
#   ./tools/regenerate_fixtures.sh check  # exit non-zero if drift detected (no write)

set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -z "${ANTHROPIC_API_KEY:-}" ]]; then
  echo "ERROR: ANTHROPIC_API_KEY is not set" >&2
  exit 2
fi

MODE="${1:-write}"
METHODS=test/fixtures/sample_md_methods.txt
FIXTURE=test/fixtures/recorded_anthropic_spec.json
TMP=$(mktemp --suffix=.json)
trap 'rm -f "$TMP"' EXIT

echo "[1/3] Calling AnthropicProvider against $METHODS..."
bin/crucible transpile notes "$(cat "$METHODS")" --provider anthropic --out "$TMP"

before_hash=$(sha256sum "$FIXTURE" | awk '{print $1}')
after_hash=$(sha256sum "$TMP" | awk '{print $1}')

echo "[2/3] Hash comparison:"
echo "  current  ($FIXTURE) = $before_hash"
echo "  new      ($TMP)     = $after_hash"

if [[ "$before_hash" == "$after_hash" ]]; then
  echo "[3/3] No drift detected."
  exit 0
fi

echo "[3/3] Drift detected. Markdown diff:"
echo
bin/crucible diff "$FIXTURE" "$TMP" || true   # exit 4 = differences found
echo

if [[ "$MODE" == "check" ]]; then
  echo "Run without 'check' to write the new fixture." >&2
  exit 4
fi

cp "$TMP" "$FIXTURE"
echo "Updated $FIXTURE. Review the diff before committing."
