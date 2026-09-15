#!/bin/bash
# leftovers.sh begin|end <state-dir>
#
# begin records the containers and image tags that exist. end removes what a run created and
# did not promote: containers absent at begin, every mikaeluman/*:build-* tag, dangling layers.
# end prints one "LEFT-BEHIND <kind> <ref> <owner> '<removal command>'" line per object it
# could not remove, or "LEFT-BEHIND nothing". The lines are the verdict; the exit code is 0.
set -euo pipefail

mode="$1"
state="$2"
mkdir --parents "$state"

case "$mode" in
  begin)
    docker ps --all --quiet --no-trunc | sort > "$state/containers.begin"
    docker images --format '{{.ID}} {{.Repository}}:{{.Tag}}' | sort > "$state/images.begin"
    echo "leftovers: recorded $(wc --lines < "$state/containers.begin") containers, $(wc --lines < "$state/images.begin") image tags"
    ;;
  end)
    left=0
    docker ps --all --quiet --no-trunc | sort > "$state/containers.end"
    while read -r id; do
      [[ -n "$id" ]] || continue
      if docker rm --force "$id" > /dev/null 2>&1; then
        echo "removed container $id"
      else
        echo "LEFT-BEHIND container $id docker 'docker rm --force $id'"
        left=1
      fi
    done < <(comm -13 "$state/containers.begin" "$state/containers.end")
    while read -r ref; do
      [[ -n "$ref" ]] || continue
      if docker rmi "$ref" > /dev/null 2>&1; then
        echo "removed tag $ref"
      else
        echo "LEFT-BEHIND image $ref docker 'docker rmi $ref'"
        left=1
      fi
    done < <(docker images --format '{{.Repository}}:{{.Tag}}' | grep --extended-regexp '^mikaeluman/[a-z-]+:build-' || true)
    echo "prune: $(docker image prune --force | tail --lines=1)"
    (( left )) || echo "LEFT-BEHIND nothing"
    ;;
  *)
    echo "usage: leftovers.sh begin|end <state-dir>" >&2
    exit 2
    ;;
esac
