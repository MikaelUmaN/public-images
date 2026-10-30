#!/usr/bin/env bash
# Copilot's Linux sandbox needs a private network namespace (slirp4netns, iptables, /dev/net/tun)
# that a container lacks; the container is the boundary. A shared settings.json that enables the
# sandbox would otherwise fail every shell command and hook. An explicit --sandbox or --no-sandbox
# passes through unchanged.
for argument in "$@"; do
  [[ "$argument" != --sandbox && "$argument" != --no-sandbox ]] || exec /opt/devtools/.bun/bin/copilot "$@"
done
exec /opt/devtools/.bun/bin/copilot --no-sandbox "$@"
