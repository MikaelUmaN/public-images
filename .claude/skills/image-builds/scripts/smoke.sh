#!/bin/bash
# smoke.sh <image> [--expect TOOL=version]... [--slow] [--perf] [--sandbox] [--tag <tag>]
#
# Runs tests/smoke/<image>.sh inside mikaeluman/<image>:<tag> (default latest), printing the
# docker command first.
#   --expect TOOL=version  sets EXPECT_<TOOL>, turning that version check into an equality check
#   --slow                 sets SMOKE_SLOW=1
#   --perf                 mounts the host's /usr/local/bin/perf read-only when it exists
#   --sandbox              adds --security-opt seccomp=unconfined and probes bwrap before the script
set -euo pipefail

image="$1"
shift

repo="$(git rev-parse --show-toplevel)"
tag=latest
sandbox=0
args=(--rm --volume "$repo/tests:/tests:ro")

while (( $# )); do
  case "$1" in
    --expect)
      tool="${2%%=*}"
      tool="${tool^^}"
      tool="${tool//-/_}"
      args+=(--env "EXPECT_${tool}=${2#*=}")
      shift 2 ;;
    --slow) args+=(--env SMOKE_SLOW=1); shift ;;
    --perf)
      if [[ -x /usr/local/bin/perf ]]; then
        args+=(--volume /usr/local/bin/perf:/usr/local/bin/perf:ro)
      else
        echo "perf: no host binary at /usr/local/bin/perf, not mounted"
      fi
      shift ;;
    --sandbox) args+=(--security-opt seccomp=unconfined); sandbox=1; shift ;;
    --tag) tag="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

ref="mikaeluman/$image:$tag"
if (( sandbox )); then
  echo "+ docker run ${args[*]} $ref bwrap --ro-bind / / --dev /dev --unshare-all echo SANDBOX-OK"
  docker run "${args[@]}" "$ref" bwrap --ro-bind / / --dev /dev --unshare-all echo SANDBOX-OK
fi
echo "+ docker run ${args[*]} $ref bash /tests/smoke/$image.sh"
docker run "${args[@]}" "$ref" bash "/tests/smoke/$image.sh"
