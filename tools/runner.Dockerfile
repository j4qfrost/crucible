# tools/runner.Dockerfile — self-hosted GitHub Actions runner for
# crucible. Lets you run the GPU-smoke workflow without installing the
# runner binary on the host (so you can rebuild it cleanly without
# touching snowman's package state).
#
# Build:
#   docker build -t crucible-runner -f tools/runner.Dockerfile tools/
#
# Run (idempotent across restarts):
#   docker run -d --restart=unless-stopped \
#     --name crucible-runner \
#     --gpus all \
#     -e GHA_RUNNER_TOKEN=<fresh-token> \
#     -e RUNNER_LABEL=self-hosted-snowman \
#     -e REPO=j4qfrost/crucible \
#     crucible-runner
#
# Notes:
# - --gpus all assumes nvidia-container-toolkit. For ROCm: add
#   `--device=/dev/kfd --device=/dev/dri --group-add video` and adjust
#   the base image to one that ships ROCm runtimes (rocm/dev-ubuntu-22.04).
# - Token is single-use and short-lived (~1 hour). Get a fresh one at
#   https://github.com/<repo>/settings/actions/runners/new.
# - The runner registers on startup and unregisters cleanly on
#   container stop, so removing the container removes the runner.

FROM ubuntu:22.04

ARG RUNNER_VERSION=2.319.1
ARG RUNNER_ARCH=x64

RUN apt-get update && apt-get install -y --no-install-recommends \
        ca-certificates curl tar git build-essential \
        libicu-dev libkrb5-3 zlib1g \
        python3 python3-venv python3-pip \
        poppler-utils \
    && rm -rf /var/lib/apt/lists/*

# Julia 1.10. We pin a version so docker build is reproducible.
ARG JULIA_VERSION=1.10.5
RUN curl -fsSL https://julialang-s3.julialang.org/bin/linux/x64/${JULIA_VERSION%.*}/julia-${JULIA_VERSION}-linux-x86_64.tar.gz \
        | tar -C /opt -xz \
    && ln -s /opt/julia-${JULIA_VERSION}/bin/julia /usr/local/bin/julia

RUN useradd --create-home --shell /bin/bash runner
USER runner
WORKDIR /home/runner

# Pull the runner. We don't bake the token into the image — it's
# supplied at container start via $GHA_RUNNER_TOKEN.
RUN curl -fsSL -o actions-runner.tar.gz \
      https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${RUNNER_ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf actions-runner.tar.gz \
    && rm actions-runner.tar.gz

USER root
RUN /home/runner/bin/installdependencies.sh
USER runner

ENV REPO=j4qfrost/crucible
ENV RUNNER_LABEL=self-hosted-snowman

# Entry: register, start, and on graceful stop, deregister. The
# `replace` flag means re-registering with the same label/name doesn't
# fail if a stale entry exists from a previous run.
COPY --chmod=755 runner-entrypoint.sh /home/runner/entrypoint.sh
ENTRYPOINT ["/home/runner/entrypoint.sh"]
