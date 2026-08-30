# Tau — run the coding agent inside a Docker container.
#
# Default build installs the published `tau-ai` package from PyPI (pinned via
# TAU_VERSION). For development, build against this checkout instead:
#
#   docker build --build-arg TAU_SOURCE=local -t tau-dev .
#
# TAU_SOURCE=local copies the repository and runs `pip install .`, so the
# image tracks the current source tree.

FROM python:3.12.8-slim

ARG TAU_SOURCE=pypi
ARG TAU_VERSION=0.4.1

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends curl ca-certificates passwd \
    && rm -rf /var/lib/apt/lists/*

# gosu is a tiny setuid binary used by the entrypoint to drop from root to the
# tau user after matching PUID/PGID against the host.
ARG GOSU_VERSION=1.17
RUN set -eux; \
    dpkg_arch="$(dpkg --print-architecture)"; \
    curl -fsSL -o /usr/local/bin/gosu \
        "https://github.com/tianon/gosu/releases/download/${GOSU_VERSION}/gosu-${dpkg_arch}"; \
    chmod +x /usr/local/bin/gosu; \
    gosu --version

# Tau installs cleanly with the same venv-based flow on every platform; the
# container does not need the host-oriented `uv tool` installers.
RUN python -m venv /opt/tau \
    && /opt/tau/bin/pip install --no-cache-dir --upgrade pip \
    && /opt/tau/bin/pip install --no-cache-dir "tau-ai==${TAU_VERSION}"

# The full checkout is only installed when TAU_SOURCE=local; the COPY layer is
# discarded below so pypi images never carry repository sources.
COPY . /build
RUN if [ "$TAU_SOURCE" = "local" ]; then \
        /opt/tau/bin/pip install --no-cache-dir /build; \
    fi \
    && rm -rf /build

# /home/tau/.local/bin is the tau user's local tool directory (uv tool / pipx /
# pip --user installs land there); it is on PATH so tools the agent installs are
# usable immediately without a shell reload.
ENV PATH=/opt/tau/bin:/home/tau/.local/bin:$PATH \
    TAU_NO_UPDATE_CHECK=1 \
    PUID=1000 \
    PGID=1000

RUN groupadd --gid 1000 tau \
    && useradd --uid 1000 --gid 1000 --create-home --shell /usr/bin/sh tau \
    && mkdir -p /workspace /home/tau/.local/bin \
    && chown -R tau:tau /workspace /home/tau

COPY docker/entrypoint.sh /usr/local/bin/tau-entrypoint
RUN chmod +x /usr/local/bin/tau-entrypoint

WORKDIR /workspace

# The container starts as root so the entrypoint can remap the tau user to the
# host PUID/PGID; it then drops privileges with gosu before running Tau.
RUN tau --version

ENTRYPOINT ["tau-entrypoint"]
CMD ["tau"]
