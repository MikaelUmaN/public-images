#!/usr/bin/env bash
set -e
# Create a compatibility symlink so absolute host paths (e.g. nushell's polars
# plugin registry at /home/<host-user>/...) resolve inside the container.
# Container runs as uid 1000 (ubuntu); /home is root-owned, so use sudo.
if [ -n "${SYMLINK_HOME:-}" ] && [ ! -e "${SYMLINK_HOME}" ]; then
  sudo ln -sfn "${HOME}" "${SYMLINK_HOME}"
fi
exec "$@"
