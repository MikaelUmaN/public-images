#!/usr/bin/env bash
# Copilot's Linux sandbox runs each command in a private network namespace through slirp4netns and
# iptables, which needs a read/write /dev/net/tun and unprivileged user and network namespaces. A
# container started without them would fail every shell command and hook under a shared
# settings.json that enables the sandbox, so the launcher adds --no-sandbox there. An explicit
# --sandbox or --no-sandbox passes through unchanged.
for argument in "$@"; do
  [[ "$argument" != --sandbox && "$argument" != --no-sandbox ]] || exec /opt/devtools/.bun/bin/copilot "$@"
done
if [[ -c /dev/net/tun && -r /dev/net/tun && -w /dev/net/tun ]] &&
  unshare --user --map-current-user --net true 2>/dev/null; then
  exec /opt/devtools/.bun/bin/copilot "$@"
fi
exec /opt/devtools/.bun/bin/copilot --no-sandbox "$@"
