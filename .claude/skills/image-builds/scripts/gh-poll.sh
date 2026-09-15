#!/bin/bash
# gh-poll.sh <run-id> [interval-seconds]
#
# Polls a GitHub Actions run of this repository until it completes, then prints
# "RUN <id> <conclusion> image=<image>", the image taken from the build step's
# "--file <image>.docker" argument in the run log. Exits 0 on success, 1 otherwise.
set -euo pipefail

run_id="$1"
interval="${2:-60}"
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"

while :; do
  state="$(gh run view "$run_id" --repo "$repo" --json status,conclusion --jq '"\(.status) \(.conclusion)"' 2>/dev/null || echo "poll-error")"
  echo "$(date +%H:%M:%S) $state"
  case "$state" in completed*) break ;; esac
  sleep "$interval"
done

image="$(gh run view "$run_id" --repo "$repo" --log 2>/dev/null \
  | grep --only-matching --max-count=1 --extended-regexp 'docker build \. --file [a-z-]+\.docker' \
  | awk '{print $NF}' || true)"
echo "RUN $run_id ${state#completed } image=${image:-unknown}"
[[ "$state" == "completed success" ]]
