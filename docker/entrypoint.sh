#!/bin/sh

set -eu

# Match the container's tau user to the host user that owns the mounted
# workspace, so files the agent writes under /workspace keep host ownership.
# Override with PUID/PGID, e.g. `docker run -e PUID=$(id -u) -e PGID=$(id -g)`.

if [ "$(id -u)" -ne 0 ]; then
    # Not root: assume the caller already manages user mapping via --user.
    exec "$@"
fi

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"

# Explicitly asking for root means "don't remap, stay root".
if [ "$PUID" -eq 0 ] || [ "$PGID" -eq 0 ]; then
    exec "$@"
fi

if [ -n "$PUID" ] && [ "$PUID" -ne 0 ] && [ "$(id -u tau)" != "$PUID" ]; then
    usermod -o -u "$PUID" tau
fi

if [ -n "$PGID" ] && [ "$PGID" -ne 0 ] && [ "$(id -g tau)" != "$PGID" ]; then
    groupmod -o -g "$PGID" tau
fi

# Keep the durable home and the mounted workspace owned by the active uid/gid.
if [ -d /home/tau ]; then
    chown -R tau:tau /home/tau
fi
if [ -d /workspace ]; then
    chown -R tau:tau /workspace
fi

export TERM="${TERM:-xterm-256color}"

exec gosu tau "$@"
