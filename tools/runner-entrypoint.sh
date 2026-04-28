#!/usr/bin/env bash
# Entry script for the self-hosted GitHub Actions runner container.
# Registers + starts; on SIGTERM, gracefully deregisters before exit.

set -euo pipefail

REPO="${REPO:-j4qfrost/crucible}"
RUNNER_LABEL="${RUNNER_LABEL:-self-hosted-snowman}"
RUNNER_NAME="${RUNNER_NAME:-crucible-runner-$(hostname)}"

if [[ -z "${GHA_RUNNER_TOKEN:-}" ]]; then
    echo "ERROR: set GHA_RUNNER_TOKEN at container run time" >&2
    echo "   Get a fresh token at: https://github.com/${REPO}/settings/actions/runners/new" >&2
    exit 2
fi

cd /home/runner

# Configure (idempotent — --replace lets us re-register cleanly after a
# container restart without manual cleanup).
./config.sh \
    --url "https://github.com/${REPO}" \
    --token "${GHA_RUNNER_TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels "${RUNNER_LABEL}" \
    --unattended \
    --replace

# Graceful deregistration on SIGTERM. The token at this point is a
# *removal* token — the runner stores it locally in .runner.
cleanup() {
    echo "[runner] deregistering ${RUNNER_NAME}"
    ./config.sh remove --token "${GHA_RUNNER_TOKEN}" || true
}
trap cleanup SIGINT SIGTERM

# Run in the foreground so docker logs work.
./run.sh &
wait $!
