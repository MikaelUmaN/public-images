#!/bin/bash
# guarded-build.sh <image> <n> [docker build args...]
#
# Builds mikaeluman/<image>:latest from <image>.docker at the repository root while sampling
# free disk every 30 s. Kills the build and exits 3 when free space drops under MIN_FREE_GB
# (default 100). Writes build-<image>-<n>.log and disk-<image>-<n>.log to IMAGE_BUILDS_LOG_DIR
# (default: a fresh mktemp directory, printed first). The last log line reads
# "BUILD <image> rc=<n> elapsed=<m>min final_avail=<g>G".
set -euo pipefail

image="$1"
n="$2"
shift 2

repo="$(git rev-parse --show-toplevel)"
log_dir="${IMAGE_BUILDS_LOG_DIR:-$(mktemp --directory)}"
mkdir --parents "$log_dir"
min_free_gb="${MIN_FREE_GB:-100}"
log="$log_dir/build-$image-$n.log"
disk_log="$log_dir/disk-$image-$n.log"
echo "logs: $log $disk_log"

free_gb() { df --output=avail --block-size=G / | tail --lines=1 | tr --delete --complement '0-9'; }

start=$(date +%s)
docker build --progress=plain --file "$repo/$image.docker" --tag "mikaeluman/$image:latest" "$@" "$repo" > "$log" 2>&1 &
build_pid=$!

while kill -0 "$build_pid" 2>/dev/null; do
  avail=$(free_gb)
  echo "$(date +%H:%M:%S) avail=${avail}G" >> "$disk_log"
  if (( avail < min_free_gb )); then
    echo "DISK GUARD: ${avail}G free < ${min_free_gb}G, killing build $image" | tee --append "$log" "$disk_log"
    kill "$build_pid"
    exit 3
  fi
  sleep 30
done

rc=0
wait "$build_pid" || rc=$?
echo "BUILD $image rc=$rc elapsed=$(( ($(date +%s) - start) / 60 ))min final_avail=$(free_gb)G" | tee --append "$log"
exit "$rc"
