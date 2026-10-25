#!/usr/bin/env bash
set -euo pipefail

IMAGE="mikaeluman/rust-datascience:latest"
PROJECT_DIR=""
DATA_DIR=""
DATA_EXPLICIT=false
PRESET=""
NETWORK=""
NAME=""
ENABLE_GUI=""
ADD_PERF_MOUNT=false
DRY_RUN=false
EXTRA_ARGS=()
CAPABILITIES=()
STATE_DIRS=()
declare -A SHARING=()
HOST_USER="$(id --user --name)"
HOST_UID="$(id --user)"
HOST_GID="$(id --group)"

fail() { echo "Error: $*" >&2; exit 1; }
usage() {
  cat <<EOF
Usage: $0 [OPTIONS] [-- DOCKER_ARGS...]

  -i, --image IMAGE       Image (default: mikaeluman/rust-datascience:latest)
  -n, --name NAME         Keep a named container; otherwise remove it on exit
  -p, --project-dir DIR   Project mounted at its host path (default: current directory)
  -d, --data-dir DIR      Additional data directory (default: none)
      --no-data          Disable the preset data mount
      --preset defaults  Use ~/dev, optional ~/data, all sharing, host network and WSLg
      --share GROUP      Share ai, git, cloud, shell or caches (repeatable)
      --no-share GROUP   Disable a sharing group (repeatable)
      --network MODE     Docker network (default: bridge)
      --gui / --no-gui   Enable / disable WSLg forwarding (default: disabled)
  -v, --volume SPEC       Additional Docker volume (repeatable; bind sources must exist)
  -e, --env SPEC          Additional Docker environment variable (repeatable)
      --sys-admin        Add SYS_ADMIN
      --ptrace           Add SYS_PTRACE
      --perfmon          Add PERFMON
      --perf             Mount perf found on the host PATH
      --dry-run          Print the command without Docker calls or filesystem changes
  -h, --help              Show this help

Explicit options override the preset in any order; repeated explicit options use the last value.
Sharing grants container access to host settings and credentials; see README.md for the groups.
The defaults preset enables WSLg only when available; --gui requires WSLg.

The container runs as $HOST_USER ($HOST_UID:$HOST_GID), with HOME=$HOME.
Additional shells use: docker exec --user $HOST_USER -it NAME bash
EOF
}

while (( $# )); do
  case "$1" in
    -i|--image|-n|--name|-p|--project-dir|-d|--data-dir|-v|--volume|-e|--env|--preset|--network|--share|--no-share)
      (( $# >= 2 )) && [[ -n "$2" ]] || fail "Missing value for $1"
      case "$1" in
        -i|--image) IMAGE="$2" ;;
        -n|--name) NAME="$2" ;;
        -p|--project-dir) PROJECT_DIR="$2" ;;
        -d|--data-dir) DATA_DIR="$2"; DATA_EXPLICIT=true ;;
        --preset) [[ "$2" == defaults ]] || fail "Unknown preset: $2"; PRESET="$2" ;;
        --network) NETWORK="$2" ;;
        --share|--no-share)
          case "$2" in ai|git|cloud|shell|caches) ;; *) fail "Unknown sharing group: $2" ;; esac
          SHARING[$2]="$([[ "$1" == --share ]] && echo true || echo false)" ;;
        -v|--volume) EXTRA_ARGS+=(--volume "$2") ;;
        -e|--env) EXTRA_ARGS+=(--env "$2") ;;
      esac
      shift 2 ;;
    --sys-admin) CAPABILITIES+=(--cap-add SYS_ADMIN); shift ;;
    --ptrace) CAPABILITIES+=(--cap-add SYS_PTRACE); shift ;;
    --perfmon) CAPABILITIES+=(--cap-add PERFMON); shift ;;
    --perf) ADD_PERF_MOUNT=true; shift ;;
    --no-data) DATA_DIR=""; DATA_EXPLICIT=true; shift ;;
    --gui) ENABLE_GUI=true; shift ;;
    --no-gui) ENABLE_GUI=false; shift ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; EXTRA_ARGS+=("$@"); break ;;
    *) fail "Unknown option: $1" ;;
  esac
done

[[ "$HOST_UID" != 0 ]] || fail 'Run this launcher as a non-root Linux user'
[[ "$HOST_USER" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || fail "Unsupported Linux account name: $HOST_USER"
[[ "$HOME" == /home/* && "$(realpath --canonicalize-missing "$HOME")" == "$HOME" ]] ||
  fail 'The host home must be a canonical directory beneath /home'

if [[ "$PRESET" == defaults ]]; then
  PROJECT_DIR="${PROJECT_DIR:-$HOME/dev}"
  NETWORK="${NETWORK:-host}"
  ENABLE_GUI="${ENABLE_GUI:-auto}"
  if [[ "$DATA_EXPLICIT" == false && -e "$HOME/data" ]]; then DATA_DIR="$HOME/data"; fi
fi
PROJECT_DIR="${PROJECT_DIR:-$PWD}"
NETWORK="${NETWORK:-bridge}"
ENABLE_GUI="${ENABLE_GUI:-false}"
for group in ai git cloud shell caches; do
  SHARING[$group]="${SHARING[$group]:-$([[ "$PRESET" == defaults ]] && echo true || echo false)}"
done
[[ -d "$PROJECT_DIR" ]] || fail "Project directory does not exist: $PROJECT_DIR"
PROJECT_DIR="$(realpath "$PROJECT_DIR")"
if [[ -n "$DATA_DIR" ]]; then
  [[ -d "$DATA_DIR" ]] || fail "Data directory does not exist: $DATA_DIR"
  DATA_DIR="$(realpath "$DATA_DIR")"
fi
DOCKER_OPTS=(
  --interactive --tty --init --network "$NETWORK" --security-opt seccomp=unconfined
  --user root
  --env "CONTAINER_USER=$HOST_USER" --env "CONTAINER_UID=$HOST_UID"
  --env "CONTAINER_GID=$HOST_GID" --env "CONTAINER_HOME=$HOME"
  --env "HOME=$HOME" --env "USER=$HOST_USER" --env "LOGNAME=$HOST_USER"
  --workdir "$PROJECT_DIR"
)

for variable in TERM COLORTERM; do
  [[ -z "${!variable:-}" ]] || DOCKER_OPTS+=(--env "$variable")
done

declare -A MOUNT_TARGETS=()
validate_target() {
  local target="$1"
  [[ "$target" == /* && "$(realpath --canonicalize-missing --no-symlinks "$target")" == "$target" ]] ||
    fail "Mount target must be canonical and absolute: $target"
  [[ "$target" != "$HOME" && "$HOME/" != "${target%/}/"* ]] ||
    fail "Mount individual directories instead of the home or its parents: $target"
  [[ -z "${MOUNT_TARGETS[$target]+x}" ]] || fail "Duplicate mount target: $target"
  MOUNT_TARGETS[$target]=1
}
bind() {
  local source="$1" target="${2:-$1}" mode="${3:-rw}"
  [[ -e "$source" ]] || fail "Missing bind source: $source"
  [[ "$source$target" != *,* ]] || fail "Comma in bind path is unsupported: $source -> $target"
  validate_target "$target"
  local spec="type=bind,source=$source,target=$target"
  [[ "$mode" != ro ]] || spec+=",readonly"
  DOCKER_OPTS+=(--mount "$spec")
}
optional_dir() {
  [[ ! -e "$1" ]] || { [[ -d "$1" ]] || fail "Expected a directory: $1"; bind "$@"; }
}
optional_file() {
  [[ ! -e "$1" ]] || { [[ -f "$1" ]] || fail "Expected a file: $1"; bind "$@"; }
}
local_state() {
  local path
  for path in "$@"; do
    [[ -d "${path%/*}" ]] || continue
    [[ ! -e "$path" || -d "$path" ]] || fail "Expected a runtime directory: $path"
    [[ ! -L "$path" ]] || fail "Runtime directory must not be a symlink: $path"
    validate_target "$path"
    STATE_DIRS+=("$path")
    DOCKER_OPTS+=(--tmpfs "$path:rw,exec,uid=$HOST_UID,gid=$HOST_GID,mode=0700")
  done
}

if [[ -n "$DATA_DIR" && "$PROJECT_DIR" == "$DATA_DIR/"* ]]; then
  bind "$DATA_DIR"
else
  bind "$PROJECT_DIR"
  if [[ -n "$DATA_DIR" && "$DATA_DIR" != "$PROJECT_DIR" && "$DATA_DIR" != "$PROJECT_DIR/"* ]]; then bind "$DATA_DIR"; fi
fi

if [[ "${SHARING[git]}" == true ]]; then
  for directory in .ssh .gnupg .config/git .config/gh; do optional_dir "$HOME/$directory"; done
  optional_file "$HOME/.gitconfig"
fi
if [[ "${SHARING[cloud]}" == true ]]; then
  for directory in .aws .kube .snowflake .snowsql; do optional_dir "$HOME/$directory"; done
fi
if [[ "${SHARING[shell]}" == true ]]; then
  for directory in .ipython .config/btop .config/htop .config/uv .jupyter/lab .local/state/vim; do
    optional_dir "$HOME/$directory"
  done
  for file in .bash_history .duckdb_history .python_history; do optional_file "$HOME/$file"; done
  for file in .vimrc .sqliterc .config/nushell/config.nu .config/nushell/env.nu; do
    optional_file "$HOME/$file" "$HOME/$file" ro
  done
fi
if [[ "${SHARING[caches]}" == true ]]; then
  optional_dir "$HOME/.nuget/packages"
  optional_dir "$HOME/.cargo/registry" /opt/devtools/cargo/registry
  optional_dir "$HOME/.cargo/git" /opt/devtools/cargo/git
  optional_dir "$HOME/.bun/install/cache" /opt/devtools/.bun/install/cache
fi
if [[ "${SHARING[ai]}" == true ]]; then
  claude_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  codex_dir="${CODEX_HOME:-$HOME/.codex}"
  copilot_dir="${COPILOT_HOME:-$HOME/.copilot}"
  for directory in "$claude_dir" "$codex_dir" "$copilot_dir"; do
    [[ "$directory" == /* && "$(realpath --canonicalize-missing "$directory")" == "$directory" ]] ||
      fail "AI configuration directory must be canonical and absolute: $directory"
  done
  if [[ -z "${CLAUDE_CONFIG_DIR:-}" && -f "$HOME/.claude.json" ]]; then
    fail 'Claude uses ~/.claude.json; configure CLAUDE_CONFIG_DIR and migrate its state before sharing (see README.md)'
  fi
  DOCKER_OPTS+=(--env "CLAUDE_CONFIG_DIR=$claude_dir" --env "CODEX_HOME=$codex_dir"
    --env "COPILOT_HOME=$copilot_dir")
  optional_dir "$claude_dir"
  optional_dir "$codex_dir"
  optional_dir "$copilot_dir"
  # Packages and process-local state belong to each container; settings and sessions are shared.
  for directory in packages app-server-control app-server-daemon ipc tmp .tmp shell_snapshots; do
    local_state "$codex_dir/$directory"
  done
  for directory in ide session-env shell-snapshots; do local_state "$claude_dir/$directory"; done
  local_state "$copilot_dir/ide"
fi

if [[ "$ENABLE_GUI" == true && ( -z "${DISPLAY:-}" || ! -d /mnt/wslg ) ]]; then
  fail '--gui requires WSLg and DISPLAY'
fi
if [[ "$ENABLE_GUI" != false && -n "${DISPLAY:-}" && -d /mnt/wslg ]]; then
  DOCKER_OPTS+=(--shm-size=1g --env DISPLAY --env WAYLAND_DISPLAY
    --env XDG_RUNTIME_DIR=/mnt/wslg/runtime-dir --env PULSE_SERVER)
  bind /tmp/.X11-unix
  bind /mnt/wslg
  if [[ -e /dev/dxg && -d /usr/lib/wsl/lib ]]; then
    DOCKER_OPTS+=(--device /dev/dxg --env LD_LIBRARY_PATH=/usr/lib/wsl/lib --env GALLIUM_DRIVER=d3d12)
    bind /usr/lib/wsl /usr/lib/wsl ro
  fi
fi

if [[ "$ADD_PERF_MOUNT" == true ]]; then
  perf_binary="$(type -P perf)" || fail 'Host perf is missing; install a perf binary matching the host kernel'
  bind "$perf_binary" /usr/local/bin/perf ro
  bind "$perf_binary" /usr/bin/perf ro
fi
if [[ -n "$NAME" ]]; then
  DOCKER_OPTS+=(--name "$NAME")
else
  DOCKER_OPTS+=(--rm)
fi
for (( index=0; index<${#EXTRA_ARGS[@]}; index++ )); do
  case "${EXTRA_ARGS[index]}" in
    -v|--volume)
      (( index + 1 < ${#EXTRA_ARGS[@]} )) || fail 'Missing volume specification'
      specification="${EXTRA_ARGS[index+1]}"
      source="${specification%%:*}"
      target="${specification#*:}"
      validate_target "${target%%:*}"
      [[ "$source" != /* || -e "$source" ]] || fail "Missing bind source: $source"
      ;;
  esac
done
DOCKER_OPTS+=("${CAPABILITIES[@]}" "${EXTRA_ARGS[@]}")
if [[ "$DRY_RUN" == true ]]; then
  printf '%q ' docker run "${DOCKER_OPTS[@]}" "$IMAGE"
  printf '\n'
else
  runtime_version="$(docker image inspect --format '{{index .Config.Labels "org.opencontainers.image.runtime-user.version"}}' "$IMAGE")"
  [[ "$runtime_version" == 1 ]] || fail "Image lacks runtime account support; rebuild or pull an updated $IMAGE"
  for directory in "${STATE_DIRS[@]}"; do
    [[ -d "$directory" ]] || mkdir --mode=0700 "$directory"
  done
  exec docker run "${DOCKER_OPTS[@]}" "$IMAGE"
fi
