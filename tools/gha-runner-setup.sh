#!/usr/bin/env bash
# tools/gha-runner-setup.sh — register a self-hosted GitHub Actions
# runner on snowman so we don't burn private-repo billing minutes.
#
# Why this exists: the user ran into the GitHub Actions billing clamp
# on a private repo and had to remove .github/workflows/ once. Today's
# CI workflow assumes the cap is lifted; this script provides a
# self-hosted fallback so a hard clamp stops being a blocker.
#
# Usage (idempotent — re-runs are safe):
#   GHA_RUNNER_TOKEN=<token-from-repo-settings> ./tools/gha-runner-setup.sh
#
# To get the token: GitHub → repo → Settings → Actions → Runners →
# New self-hosted runner → expand Linux x64 → copy the `--token` value.
# Tokens expire in ~1 hour; re-run with a fresh one if it lapses.
#
# Side effects (all in $RUNNER_DIR, default ~/actions-runner):
#   1. Downloads the runner binary into a versioned subdirectory.
#   2. Registers the runner against j4qfrost/crucible.
#   3. Creates a systemd user unit so the runner survives reboots.
#
# To uninstall:
#   ~/actions-runner/config.sh remove --token <removal-token>
#   systemctl --user disable --now crucible-gha-runner.service

set -euo pipefail

REPO="${REPO:-j4qfrost/crucible}"
RUNNER_DIR="${RUNNER_DIR:-$HOME/actions-runner}"
RUNNER_LABEL="${RUNNER_LABEL:-self-hosted-snowman}"
RUNNER_VERSION="${RUNNER_VERSION:-2.319.1}"     # bump as needed

if [[ -z "${GHA_RUNNER_TOKEN:-}" ]]; then
  cat >&2 <<EOF
ERROR: set GHA_RUNNER_TOKEN=<token> before running.

Get a fresh token at:
  https://github.com/${REPO}/settings/actions/runners/new
(expires in ~1 hour)
EOF
  exit 2
fi

ARCH=$(uname -m)
case "$ARCH" in
  x86_64)  RUNNER_ARCH="x64" ;;
  aarch64) RUNNER_ARCH="arm64" ;;
  *)
    echo "ERROR: unsupported arch $ARCH; manual install required" >&2
    exit 3
    ;;
esac

RUNNER_TARBALL="actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz"
RUNNER_URL="https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${RUNNER_TARBALL}"

echo "[1/4] preparing $RUNNER_DIR"
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

if [[ ! -f config.sh ]]; then
  echo "[2/4] downloading $RUNNER_TARBALL"
  curl -fsSL --retry 3 -o "$RUNNER_TARBALL" "$RUNNER_URL"
  tar xzf "$RUNNER_TARBALL"
  rm "$RUNNER_TARBALL"
else
  echo "[2/4] runner binary already present, skipping download"
fi

if [[ ! -f .runner ]]; then
  echo "[3/4] registering runner with $REPO"
  ./config.sh \
    --url "https://github.com/${REPO}" \
    --token "$GHA_RUNNER_TOKEN" \
    --labels "$RUNNER_LABEL" \
    --unattended \
    --replace
else
  echo "[3/4] runner already configured, skipping"
fi

UNIT_DIR="$HOME/.config/systemd/user"
UNIT_FILE="$UNIT_DIR/crucible-gha-runner.service"
mkdir -p "$UNIT_DIR"
cat > "$UNIT_FILE" <<UNIT
[Unit]
Description=GitHub Actions self-hosted runner for crucible
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
WorkingDirectory=$RUNNER_DIR
ExecStart=$RUNNER_DIR/run.sh
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=default.target
UNIT

echo "[4/4] enabling systemd unit (run.sh as a user service)"
systemctl --user daemon-reload
systemctl --user enable --now crucible-gha-runner.service
echo
echo "Done. Verify the runner is online at:"
echo "  https://github.com/${REPO}/settings/actions/runners"
echo
echo "To target this runner from a workflow, set:"
echo "  runs-on: [self-hosted, $RUNNER_LABEL]"
