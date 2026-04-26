#!/usr/bin/env bash
# tools/sync_remotes.sh — re-enable the Forgejo half of the synthetic 'all'
# remote after a token refresh.
#
# Why this exists: the Forgejo token rotates periodically, so the
# canonical 'all' remote in this repo is GitHub-only. When the user
# provides a fresh token, run this script to wire Forgejo back in.
#
# Usage:
#   FORGEJO_TOKEN=<new-token> ./tools/sync_remotes.sh
#
# What it does:
#   1. Writes the token to ~/.git-credentials-snowman (chmod 600)
#   2. Configures git's credential helper for both URL forms
#   3. Adds Forgejo as a fetch/push URL on the synthetic 'all' remote

set -euo pipefail

if [[ -z "${FORGEJO_TOKEN:-}" ]]; then
  echo "ERROR: set FORGEJO_TOKEN=<new-token> before running" >&2
  echo "       generate at: http://snowman:3000/-/user/settings/applications" >&2
  exit 2
fi

USER="${FORGEJO_USER:-j4qfrost}"
HOST_INTERNAL="snowman:3000"
HOST_FUNNEL="snowman.tailddc637.ts.net:8443"

CREDS=~/.git-credentials-snowman
echo "[1/3] writing $CREDS"
umask 077
cat > "$CREDS" <<EOF
http://$USER:$FORGEJO_TOKEN@$HOST_INTERNAL
https://$USER:$FORGEJO_TOKEN@$HOST_FUNNEL
EOF
chmod 600 "$CREDS"

echo "[2/3] configuring git credential helper"
git config --global "credential.http://$HOST_INTERNAL.helper" \
  "store --file=$CREDS"
git config --global "credential.http://$HOST_INTERNAL.username" "$USER"
git config --global "credential.https://$HOST_FUNNEL.helper" \
  "store --file=$CREDS"
git config --global "credential.https://$HOST_FUNNEL.username" "$USER"

echo "[3/3] wiring Forgejo into the synthetic 'all' remote"
cd "$(dirname "$0")/.."
# Recreate 'all' from scratch to avoid duplicate URLs
git remote remove all 2>/dev/null || true
git remote add all "git@github.com:$USER/crucible.git"
git remote set-url --add --push all "git@github.com:$USER/crucible.git"
git remote set-url --add --push all "https://$HOST_FUNNEL/$USER/crucible.git"

# Smoke test
echo
echo "smoke test (fetch from Forgejo):"
git fetch forgejo 2>&1 | tail -3 || echo "(forgejo fetch failed — token may be wrong)"

echo
echo "remotes:"
git remote -v
