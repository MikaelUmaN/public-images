#!/bin/bash
# dry-run.sh <start-script> [-- <script args>]
#
# Checks a docker start script without letting dockerd create anything. Stage one runs the
# script from $HOME with a docker shim first on PATH, so the script's own `docker run` argv is
# captured; every bind-mount source is printed as "MOUNT <src> -> <dst> exists owner=<user>"
# or "MOUNT <src> -> <dst> missing", and a missing source ends the check with exit 2. Stage two
# runs the real command with `--rm --entrypoint /bin/true` under a pseudo-tty (the script has
# to pass arguments after `--` through to docker run), then re-checks every source's owner and
# any container left; each finding is a "LEFT-BEHIND <kind> <ref> <owner> '<removal>'" line.
set -euo pipefail

script_path="$(readlink --canonicalize "$1")"
shift
[[ "${1:-}" == "--" ]] && shift

work="$(mktemp --directory)"
trap 'rm --recursive --force "$work"' EXIT
printf '#!/bin/sh\nfor a in "$@"; do printf "ARGV\\t%%s\\n" "$a"; done\n' > "$work/docker"
chmod 0755 "$work/docker"

cd "$HOME"
if ! PATH="$work:$PATH" "$script_path" "$@" > "$work/argv" 2> "$work/stderr"; then
  echo "script refused before docker: $(tail --lines=1 "$work/stderr")"
  exit 2
fi
mapfile -t argv < <(grep --text '^ARGV' "$work/argv" | cut --fields=2-)
echo "captured docker argv: ${#argv[@]} words, image ${argv[-1]:-?}"

declare -A owner_before=()
missing=0
for ((i = 0; i < ${#argv[@]}; i++)); do
  spec=""
  case "${argv[$i]}" in
    -v|--volume) spec="${argv[$((i + 1))]}" ;;
    --volume=*) spec="${argv[$i]#--volume=}" ;;
    --mount) [[ "${argv[$((i + 1))]}" == *type=bind* ]] && spec="$(sed --regexp-extended 's/.*(source|src)=([^,]*).*/\2/' <<< "${argv[$((i + 1))]}"):" ;;
  esac
  [[ -n "$spec" && "$spec" == /* ]] || continue
  src="${spec%%:*}"
  rest="${spec#*:}"
  dst="${rest%%:*}"
  if [[ -e "$src" ]]; then
    owner_before["$src"]="$(stat --format=%U "$src")"
    echo "MOUNT $src -> $dst exists owner=${owner_before[$src]}"
  else
    echo "MOUNT $src -> $dst missing"
    missing=1
  fi
done
if (( missing )); then
  echo "dry run skipped: a missing bind source would be created root-owned by docker"
  exit 2
fi

containers_before="$(docker ps --all --quiet --no-trunc | sort)"
rc=0
script -qec "$(printf '%q ' "$script_path" "$@") -- --rm --entrypoint /bin/true" /dev/null > "$work/run.out" 2>&1 || rc=$?
tr --delete '\r\000' < "$work/run.out" | tail --lines=3
echo "dry run: rc=$rc"

left=0
for src in "${!owner_before[@]}"; do
  now="$(stat --format=%U "$src" 2>/dev/null || echo gone)"
  if [[ "$now" != "${owner_before[$src]}" ]]; then
    echo "LEFT-BEHIND path $src $now 'sudo chown --recursive $USER: $src'"
    left=1
  fi
done
while read -r id; do
  [[ -n "$id" ]] || continue
  if docker rm --force "$id" > /dev/null 2>&1; then
    echo "removed container $id"
  else
    echo "LEFT-BEHIND container $id docker 'docker rm --force $id'"
    left=1
  fi
done < <(comm -13 <(printf '%s\n' "$containers_before") <(docker ps --all --quiet --no-trunc | sort))
(( left )) || echo "LEFT-BEHIND nothing"
exit "$rc"
