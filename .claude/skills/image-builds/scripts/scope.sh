#!/bin/bash
# scope.sh [--since <ref>] [--build-arg K=V]... [image...]
#
# Classifies each image (default: all six) from the change set of its inputs: <image>.docker,
# the files its COPY lines name, tests/smoke/lib.sh, tests/smoke/<image>.sh and the tests/
# paths that script names. The reference is --since, or per image the newest commit not after
# the local mikaeluman/<image>:latest was created; the working tree and untracked inputs count
# as changed. One line per image:
#   <image> <state> kind=<kind> base=<base|none> files=<a,b> args=<ARG,...>
# state: unbuilt | unchanged | tests-only | changed | downstream-of:<base>
# kind:  none | tests | comment | pins | install | python-deps | runtime (highest wins)
set -euo pipefail

repo="$(git rev-parse --show-toplevel)"
cd "$repo"
since=""
build_args=()
images=()
while (( $# )); do
  case "$1" in
    --since) since="$2"; shift 2 ;;
    --build-arg) build_args+=("${2%%=*}"); shift 2 ;;
    *) images+=("$1"); shift ;;
  esac
done
all=(datascience rust-datascience net-datascience quarto-datascience latex pico)
(( ${#images[@]} )) || images=("${all[@]}")

base_of() { sed --quiet --regexp-extended 's#^FROM mikaeluman/([a-z-]+):.*#\1#p' "$1.docker" | head --lines=1; }

inputs_of() {
  local img="$1"
  printf '%s\n' "$img.docker" tests/smoke/lib.sh "tests/smoke/$img.sh"
  grep --extended-regexp '^COPY ' "$img.docker" | sed --regexp-extended 's/^COPY( --[a-z]+=[^ ]+)* //' | awk '{ NF--; print }' | tr ' ' '\n'
  grep --only-matching --extended-regexp 'tests/[A-Za-z0-9_./-]+' "tests/smoke/$img.sh" 2>/dev/null || true
}

ref_for() {
  local img="$1" created
  if [[ -n "$since" ]]; then echo "$since"; return; fi
  created="$(docker image inspect --format '{{.Created}}' "mikaeluman/$img:latest" 2>/dev/null)" || { echo ""; return; }
  git rev-list --max-count=1 --before="$created" HEAD
}

rank() { case "$1" in none) echo 0 ;; tests) echo 1 ;; comment) echo 2 ;; pins) echo 3 ;; install) echo 4 ;; python-deps) echo 5 ;; runtime) echo 6 ;; esac; }

declare -A state kind files argsof
for img in "${all[@]}"; do
  ref="$(ref_for "$img")"
  mapfile -t inputs < <(inputs_of "$img" | sort --unique)
  changed=()
  if [[ -z "$ref" ]]; then
    changed=("${inputs[@]}")
  else
    mapfile -t changed < <({ git diff --name-only "$ref" -- "${inputs[@]}"; git ls-files --others --exclude-standard -- "${inputs[@]}"; } | sort --unique)
  fi
  k=none
  args=()
  for f in "${changed[@]}"; do
    case "$f" in
      tests/*) fk=tests ;;
      pyproject.toml|pytorch*.toml) fk=python-deps ;;
      *.docker)
        fk=comment
        while IFS= read -r line; do
          body="${line:1}"
          body="${body#"${body%%[![:space:]]*}"}"
          case "$body" in
            \#*|'') lk=comment ;;
            "ARG "*_VERSION=*) lk=pins; [[ "$line" == +* ]] && args+=("$(sed --regexp-extended 's/^ARG ([A-Z0-9_]+)=.*/\1/' <<< "$body")") ;;
            *"LABEL "*version*|*".version="*) lk=pins ;;
            *"uv python install"*) lk=python-deps ;;
            FROM*|ENV*|USER*|WORKDIR*|ENTRYPOINT*|CMD*|"ARG "*) lk=runtime ;;
            *) lk=install ;;
          esac
          (( $(rank "$lk") > $(rank "$fk") )) && fk="$lk"
        done < <(if [[ -n "$ref" ]]; then git diff --unified=0 "$ref" -- "$f" | grep --extended-regexp '^[+-][^+-]' || true; else sed 's/^/+/' "$f"; fi)
        ;;
      *) fk=install ;;
    esac
    (( $(rank "$fk") > $(rank "$k") )) && k="$fk"
  done
  for a in "${build_args[@]}"; do
    grep --quiet --extended-regexp "^ARG $a=" "$img.docker" || continue
    (( $(rank pins) > $(rank "$k") )) && k=pins
    args+=("$a")
  done
  if [[ -z "$ref" ]]; then st=unbuilt
  elif [[ "$k" == none ]]; then st=unchanged
  elif [[ "$k" == tests ]]; then st=tests-only
  else st=changed
  fi
  state["$img"]="$st"
  kind["$img"]="$k"
  files["$img"]="$(IFS=,; echo "${changed[*]:-}")"
  argsof["$img"]="$(IFS=,; echo "${args[*]:-}")"
done

for img in "${images[@]}"; do
  st="${state[$img]}"
  base="$(base_of "$img")"
  if [[ "$st" == unchanged && -n "$base" && "${state[$base]}" =~ ^(changed|unbuilt|downstream-of) ]]; then
    st="downstream-of:$base"
  fi
  echo "$img $st kind=${kind[$img]} base=${base:-none} files=${files[$img]} args=${argsof[$img]}"
done
