# Running Tau in Docker (branch `tau-in-docker`)

This branch is dedicated to one task: **running Tau inside a Docker container**.
No Tau application code changes live here — only container assets, CI, and docs.

## What was added

- `Dockerfile` — single-stage image, `python:3.12.8-slim` base.
  - Installs Tau into a dedicated venv at `/opt/tau` with pip, pinned to
    `tau-ai==0.4.1` by default (`ARG TAU_VERSION`).
  - `ARG TAU_SOURCE=local` swaps the install to `pip install .` from the
    checkout, so the image can track this branch's source for testing.
- Non-root `tau` user (UID/GID 1000), `WORKDIR /workspace`, `gosu` for
  privilege dropping, and a build-time `tau --version` sanity check.
- `PATH` includes `/home/tau/.local/bin` (the `tau` user's `~/.local/bin`), so
  tools the agent installs via `uv tool install`, `pipx`, or `pip --user` are
  usable immediately without a shell reload, and persist in the `tau-home`
  volume.
- `docker/entrypoint.sh` — linuxserver-style user mapping: when the container
  starts as root, it remaps the `tau` user to `PUID`/`PGID` (default 1000),
  re-owns `/home/tau` and `/workspace`, then `exec gosu tau "$@"`. This keeps
  files the agent writes on a mounted workspace owned by the host user.
- `docker-compose.yml` — interactive service (`stdin_open`, `tty`, `init`),
  binds `.:/workspace`, persists `~/.tau` via the named `tau-home` volume,
  forwards provider credentials, and maps `PUID`/`PGID`/`TERM`.
- `docker/.env.example` — template for provider keys and user mapping.
- `.dockerignore` — keeps the `TAU_SOURCE=local` context (and cache) small.
- `.github/workflows/docker-ci.yml` — path-filtered validation of the image on
  PRs/pushes: builds the pypi and local-source images, smoke-tests
  `tau --version`, `tau sessions`, `tau -p "/system"` (headless, no API key or
  network needed), and verifies the entrypoint's user mapping.
- `.github/workflows/docker-publish.yml` — pushes `ghcr.io/<owner>/tau:<version>`
  + `:latest` on `v*` tags and `:latest` on the `tau-in-docker` branch
  (multi-arch amd64/arm64).
- `website/content/guides/docker.md` — the published "Run Tau with Docker"
  guide.

## Why pip and a venv, not `uv tool install`

Tau's host installers (`website/static/install.sh`, `install.ps1`) use
`uv tool install tau-ai` because they must manage an isolated tool environment
on a host: discover the bin dir via `uv tool dir --bin`, keep `tau update`
working through uv receipts, and never touch `sudo`.

None of that applies inside a container. A container is already isolated, updates
are delivered by rebuilding the image (`TAU_NO_UPDATE_CHECK=1` suppresses the
PyPI notice), and `uv tool` would only add a tool registry whose PATH must be
discovered. A fixed venv at `/opt/tau` with `/opt/tau/bin` on `PATH` is smaller,
simpler to debug, and equally deterministic for one pinned package — and it
trivially supports installing from the local checkout.

### Review of `install.sh` (no changes made)

`website/static/install.sh` was reviewed for this branch. Verdict: solid for its
purpose (`set -eu`, multi-location uv discovery, curl/wget fallback,
post-install binary verification, PATH warning). Deferred future improvements:

1. Verify what `tau` actually resolves to (`command -v tau`) and warn when a
   different `tau` is earlier in `PATH`, not just when the bin dir is missing.
2. Guard `$HOME` under `set -u` (`${HOME:-}`).
3. Print the immediate `export PATH="$tool_bin:$PATH"` command plus a
   shell-specific persistence line instead of only "restart your shell".
4. Optional `TAU_VERSION` pin support.
5. End with an "upgrade with `tau update`" hint.

## How to test

```bash
# pypi image
docker build -t tau .

# local-source image (tracks this checkout)
docker build --build-arg TAU_SOURCE=local -t tau-dev .

# smoke tests (headless, no provider needed)
docker run --rm tau --version
docker run --rm tau tau sessions
docker run --rm tau tau -p "/system"
docker run --rm -e PUID=$(id -u) -e PGID=$(id -g) tau id

# interactive TUI
docker compose run --rm tau

# one-shot print mode against the current directory
docker run --rm -it -v "$PWD:/workspace" -w /workspace -e OPENAI_API_KEY="$OPENAI_API_KEY" tau tau -p "explain this repo"
```

Entrypoint syntax: `sh -n docker/entrypoint.sh`. Docs build:
`hugo --source website --minify`.

## Limitations

- `tau update` is not meaningful in a container (ephemeral filesystem); rebuild
  or pull a newer image instead. The image sets `TAU_NO_UPDATE_CHECK=1`.
- The agent's `bash` tool runs *inside* the container, so it can only read/write
  what is mounted into `/workspace` (plus `/home/tau`). Mount extra paths if the
  agent must touch more than the project.
- The TUI needs an allocated TTY (`docker run -it` or `docker compose run`).
- OAuth-based providers (OpenAI Codex, Anthropic, Hugging Face) print a device
  URL inside the container; their tokens persist in the `tau-home` volume.
