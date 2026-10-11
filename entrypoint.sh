#!/usr/bin/env bash
set -euo pipefail

fail() { echo "entrypoint: $*" >&2; exit 1; }

# Bind mounts can share the root filesystem's device number; -xdev alone is insufficient.
own_image_files() {
  local root="$1" target options
  local -a prune=()
  while read -r _ _ _ _ target options; do
    printf -v target '%b' "$target"
    if [[ "$target" == "$root" || "$target" == "$root/"* ]]; then
      target="${target//\\/\\\\}"
      target="${target//\*/\\*}"
      target="${target//\?/\\?}"
      target="${target//\[/\\[}"
      prune+=(-path "$target" -prune -o)
    fi
  done < /proc/self/mountinfo
  find "$root" "${prune[@]}" \( -uid 0 -o -uid "$previous_uid" \) \
    -exec chown --no-dereference "$runtime_uid:$runtime_gid" {} +
}

seed_home() {
  local source="$1" destination="$2" item
  mountpoint --quiet "$destination" && return 0
  [[ -L "$destination" ]] && return 0
  mkdir --parents "$destination"
  for item in "$source"/* "$source"/.[!.]* "$source"/..?*; do
    [[ -e "$item" || -L "$item" ]] || continue
    if [[ -d "$item" && ! -L "$item" && ! -e "$destination/${item##*/}" ]]; then
      mkdir "$destination/${item##*/}"
    fi
    if [[ -d "$item" && ! -L "$item" && -d "$destination/${item##*/}" ]]; then
      seed_home "$item" "$destination/${item##*/}"
    elif [[ ! -e "$destination/${item##*/}" && ! -L "$destination/${item##*/}" ]]; then
      cp --archive --no-preserve=ownership "$item" "$destination/"
    fi
  done
}

link_installation() {
  local source="$1" destination="$2"
  [[ -e "$source" ]] || return 0
  if [[ -e "$destination" || -L "$destination" ]]; then
    [[ "$(readlink --canonicalize "$destination")" == "$source" ]] || \
      fail "$destination shadows the image installation at $source"
  else
    mkdir --parents "${destination%/*}"
    ln --symbolic "$source" "$destination"
  fi
}

requested="${CONTAINER_USER+x}${CONTAINER_UID+x}${CONTAINER_GID+x}${CONTAINER_HOME+x}"
runtime_user="${CONTAINER_USER:-ubuntu}"
runtime_uid="${CONTAINER_UID:-1000}"
runtime_gid="${CONTAINER_GID:-1000}"
runtime_home="${CONTAINER_HOME:-/home/$runtime_user}"

if [[ -n "$requested" ]]; then
  [[ "$runtime_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ && "$runtime_user" != root ]] || fail 'invalid CONTAINER_USER'
  for identity in "$runtime_uid" "$runtime_gid"; do
    [[ "$identity" =~ ^[1-9][0-9]{0,9}$ && "$identity" -lt 4294967295 ]] || fail 'UID/GID must be positive numeric IDs'
  done
  [[ "$runtime_home" == /home/* && "$runtime_home" != /home/ && \
     "$(realpath --canonicalize-missing "$runtime_home")" == "$runtime_home" ]] || fail 'CONTAINER_HOME must be a canonical path beneath /home'

  if [[ "$(id --user)" == 0 ]]; then
    previous_user=ubuntu
    [[ ! -f /var/lib/container-user ]] || read -r previous_user < /var/lib/container-user
    previous_uid="$(id --user "$previous_user")"
    previous_group="$(id --group --name "$previous_user")"
    for account in "$runtime_user" "$runtime_uid"; do
      record="$(getent passwd "$account" || :)"
      [[ -z "$record" || "${record%%:*}" == "$previous_user" ]] || fail "account conflict: $account"
    done
    for group in "$runtime_user" "$runtime_gid"; do
      record="$(getent group "$group" || :)"
      [[ -z "$record" || "${record%%:*}" == "$previous_group" ]] || fail "group conflict: $group"
    done
    [[ ! -L "$runtime_home" ]] || fail 'the runtime home must be a real directory'
    mountpoint --quiet "$runtime_home" && fail 'mount individual home subdirectories instead of the entire home'

    # An empty temporary home prevents usermod from recursively changing mounted files.
    temporary_home="$(mktemp --directory /run/container-user.XXXXXX)"
    usermod --home "$temporary_home" "$previous_user"
    groupmod --new-name "$runtime_user" --gid "$runtime_gid" "$previous_group"
    usermod --login "$runtime_user" --uid "$runtime_uid" --gid "$runtime_gid" \
      --home "$runtime_home" "$previous_user"
    rmdir "$temporary_home"
    printf '%s\n' "$runtime_user" > /var/lib/container-user
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$runtime_user" > /etc/sudoers.d/container-user
    chmod 0440 /etc/sudoers.d/container-user
    if [[ -f /etc/sudoers.d/ubuntu && "$(cat /etc/sudoers.d/ubuntu)" == 'ubuntu ALL=(ALL) NOPASSWD:ALL' ]]; then
      rm /etc/sudoers.d/ubuntu
    fi
    mkdir --parents "$runtime_home"
    own_image_files "$runtime_home"
    if [[ -d /opt/devtools && "$(stat --format '%u:%g' /opt/devtools)" != "$runtime_uid:$runtime_gid" ]]; then
      own_image_files /opt/devtools
    fi
    exec setpriv --reuid "$runtime_uid" --regid "$runtime_gid" --init-groups \
      env HOME="$runtime_home" USER="$runtime_user" LOGNAME="$runtime_user" "$0" "$@"
  fi
  [[ "$(id --user)" == "$runtime_uid" && "$(id --group)" == "$runtime_gid" && \
     "$(id --user --name)" == "$runtime_user" && "$HOME" == "$runtime_home" ]] || \
    fail 'runtime account setup requires --user root'
fi

if [[ "$(id --user)" != 0 ]]; then
  seed_home /etc/skel "$HOME"
  link_installation /opt/devtools/bin "$HOME/.local/bin"
  link_installation /opt/devtools/.bun "$HOME/.bun"
  link_installation /opt/devtools/cargo "$HOME/.cargo"
  link_installation /opt/devtools/rustup "$HOME/.rustup"
  link_installation /opt/devtools/claude "$HOME/.local/share/claude"
  link_installation /opt/devtools/dotnet "$HOME/.dotnet/tools"
  export PATH="$HOME/.local/bin:$PATH"
  if [[ "$PWD" == /home/ubuntu || "$PWD" == /home/ubuntu/* ]]; then
    cd "$HOME${PWD#/home/ubuntu}"
  fi
fi
exec "$@"
