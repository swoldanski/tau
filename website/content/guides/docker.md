---
title: Run Tau with Docker
description: Run Tau inside a Docker container — interactive TUI or headless print mode — with persisted sessions and host-friendly file ownership.
---

Tau ships a `Dockerfile` so you can run the agent in a container: the host only
needs Docker, the container carries Python and Tau. This is a good fit when you
want an isolated runtime, a reproducible environment for scripts and CI, or you
prefer not to install Python tooling on the host.

The image installs the published `tau-ai` package into a virtual environment and
runs as a non-root user. Your project is mounted into `/workspace`, and Tau's
durable data (sessions, provider config, credentials, model catalog) is kept in
a named volume at `/home/tau`.

## Build the image

```bash
git clone https://github.com/huggingface/tau.git
cd tau
docker build -t tau .
```

The build verifies Tau with `tau --version` before finishing. To pin a specific
Tau release at build time:

```bash
docker build --build-arg TAU_VERSION=0.4.1 -t tau .
```

### Build from a local checkout

To test an unreleased version, build from the repository source instead of
PyPI:

```bash
docker build --build-arg TAU_SOURCE=local -t tau-dev .
```

## Interactive TUI

Run the full Textual TUI against the current directory:

```bash
docker run -it --rm \
  -v "$(pwd):/workspace" \
  -v tau-home:/home/tau \
  -e OPENAI_API_KEY="$OPENAI_API_KEY" \
  -e PUID="$(id -u)" -e PGID="$(id -g)" \
  tau
```

Notes:

- `-it` allocates a TTY, which the TUI requires.
- `-v tau-home:/home/tau` persists sessions, provider configuration, stored
  credentials, and the model catalog between runs.
- `PUID`/`PGID` map the container's `tau` user to your host user, so files the
  agent writes in `/workspace` keep host ownership. Omit them if you do not
  mount a host project.
- Set a matching `TERM` (`-e TERM="$TERM"`) for terminals that report an unusual
  terminfo entry.

With Docker Compose:

```bash
cp docker/.env.example docker/.env   # add provider keys and PUID/PGID
docker compose run --rm tau
```

## Headless print mode

One-shot prompts work without a TTY, which is ideal for scripts and CI:

```bash
docker run --rm \
  -v "$(pwd):/workspace" \
  -e OPENAI_API_KEY="$OPENAI_API_KEY" \
  tau tau -p "explain this repo"
```

Add `-e PUID="$(id -u)" -e PGID="$(id -g)"` if the agent should edit the mounted
workspace. Output formats (`--mode json|transcript|rpc`) and all other flags
work as documented in the [CLI reference](../reference/cli/).

## Provider credentials

Pass keys through the environment, matching each provider's expected variable
(`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `OPENROUTER_API_KEY`, `HF_TOKEN`, …). See
the [providers and models guide](./providers-and-models/). OAuth-based providers
(OpenAI Codex, Anthropic, Hugging Face) print a device URL inside the container;
their tokens persist in the `tau-home` volume.

## Persisting your skills and config

Your personal resources live in `/home/tau/.tau` and `/home/tau/.agents`. The
named volume persists them automatically. To reuse resources you already have on
the host, mount them explicitly:

```bash
docker run -it --rm \
  -v "$(pwd):/workspace" \
  -v "$HOME/.tau:/home/tau/.tau" \
  -v "$HOME/.agents:/home/tau/.agents" \
  -e OPENAI_API_KEY="$OPENAI_API_KEY" \
  tau
```

## What the agent can touch

Tau's `bash` tool runs inside the container. It can read and write everything
mounted under `/workspace` and `/home/tau`, and nothing else on the host. That
is a useful safety boundary — the agent cannot reach your home directory unless
you mount it — but it also means any path the agent must modify has to be
mounted. Mount additional directories with extra `-v` flags if needed.

## Installing extra tools

`/home/tau/.local/bin` (the `tau` user's `~/.local/bin`) is already on `PATH`,
so tools the agent installs — for example with `uv tool install`, `pipx
install`, or `pip install --user` — are usable immediately, without a shell
reload. Tools land under `/home/tau`, so they persist in the `tau-home` volume.

## Updating

Tau inside the container is pinned to the version baked into the image.
`tau update` is disabled (`TAU_NO_UPDATE_CHECK=1`); to upgrade, rebuild the
image with a newer `TAU_VERSION` or pull a newer published image.

## Running Tau from a published image

Images are published to the GitHub Container Registry under the repository
owner's namespace: tagged releases as `ghcr.io/<owner>/tau:<version>` and the
latest build as `ghcr.io/<owner>/tau:latest`. For the upstream Tau repository:

```bash
docker pull ghcr.io/huggingface/tau:latest
```

For a fork, substitute the fork's owner, for example
`ghcr.io/<your-name>/tau`.

## Caveats

- The TUI needs a TTY (`-it`); headless runs use print mode (`tau -p`).
- The `bash` tool is confined to mounted volumes, so it cannot edit arbitrary
  host paths unless you mount them.
- PUID/PGID mapping requires the container to start as root (the default);
  when you override with `--user`, pass the mapping yourself.
