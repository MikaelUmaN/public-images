# public-images

Docker images for analytical developer work, published as `mikaeluman/<image>:latest`.

| Image | Builds on | Adds |
|---|---|---|
| `datascience` | `ubuntu:24.04` | uv-managed Python 3.13 and JupyterLab, DuckDB, Nushell, AWS and Kubernetes CLIs, bun with Playwright, Chrome, Claude Code, Codex, Copilot CLI |
| `rust-datascience` | `datascience` | Rust toolchain, cargo tools, evcxr REPL and Jupyter kernel, libduckdb, Nushell polars plugin |
| `net-datascience` | `rust-datascience` | .NET 8 and 10 SDKs, F# tools |
| `quarto-datascience` | `net-datascience` | Quarto CLI, extended TeX Live |
| `latex` | `ubuntu:24.04` | full TeX Live, latexmk, biber |
| `pico` | `ubuntu:24.04` | Raspberry Pi Pico SDK, Arm toolchain, picotool, pioasm |

Repository instructions for coding agents are in [AGENTS.md](AGENTS.md).

## Launcher

[`scripts/run-science.sh`](scripts/run-science.sh) starts an interactive shell with the host's
username, UID, GID and home. It requires Bash 4+, GNU coreutils, a non-root Linux or WSL account
with a canonical home beneath `/home`, and access to a local Docker daemon. The selected image
must already be pulled and carry runtime-account support version 1.

```bash
docker pull mikaeluman/rust-datascience:latest
./scripts/run-science.sh
./scripts/run-science.sh --share ai --project-dir /home/analyst/projects
./scripts/run-science.sh --preset defaults --no-share cloud --no-gui
./scripts/run-science.sh --image mikaeluman/latex:latest --dry-run
```

| Setting | Plain invocation | `--preset defaults` |
|---|---|---|
| Image | `mikaeluman/rust-datascience:latest` | same |
| Project and initial working directory | current directory | `$HOME/dev` |
| Data | none | `$HOME/data`, when present |
| Sharing | none | all five groups below |
| Network | Docker bridge | host |
| GUI | disabled | WSLg when available |

`--project-dir`, `--data-dir`, `--no-data`, `--network`, `--gui`, `--no-gui`, `--share` and
`--no-share` override preset choices regardless of argument order. Repeated explicit settings use
the last value. Explicit project/data directories must exist; nested project/data mounts collapse
to one mount. Each project keeps its absolute host path inside the container.

The shell uses a terminal and forwards `TERM` and `COLORTERM`. Codex's sandbox requires the
launcher's `seccomp=unconfined` setting. `--name NAME` retains the container after exit; otherwise
Docker removes it. An additional shell uses `docker exec --user "$(id --user --name)" -it NAME bash`.
`--gui` requires WSLg and `DISPLAY`. `--perf` mounts the host PATH's perf binary; profiling also
requires an appropriate capability (`--perfmon`, `--ptrace` or `--sys-admin`).

`--volume SPEC` and `--env SPEC` accept repeatable Docker values. Absolute bind sources must exist;
named volumes use `NAME:/container/path`. Arguments after `--` pass directly to `docker run`
before the image. This escape hatch follows Docker's semantics; callers own its mount and account
choices. `--dry-run` prints the quoted command without contacting Docker or creating directories.
`--help` lists all options. Launcher-managed mounts reject whole-home targets and comma-containing
bind paths.

### Sharing groups

`--share GROUP` enables one group; `--no-share GROUP` disables it, including in the preset.
Existing resources are shared read/write except the four read-only shell configuration files
listed below. These mounts grant the container access to host credentials and permit changes to
shared settings. Missing optional resources are skipped.

| Group | Host resources |
|---|---|
| `ai` | `~/.claude`, `~/.codex`, `~/.copilot`, including authentication, settings and sessions; `CLAUDE_CONFIG_DIR`, `CODEX_HOME` and `COPILOT_HOME` override these directories |
| `git` | `~/.gitconfig`, `~/.config/git`, `~/.config/gh`, `~/.ssh`, `~/.gnupg` |
| `cloud` | `~/.aws`, `~/.kube`, `~/.snowflake`, `~/.snowsql` |
| `shell` | `~/.ipython`, `~/.config/btop`, `~/.config/htop`, `~/.config/uv`, `~/.jupyter/lab`, `~/.local/state/vim`; Bash, DuckDB and Python history files; read-only `~/.vimrc`, `~/.sqliterc`, `~/.config/nushell/config.nu`, `~/.config/nushell/env.nu` |
| `caches` | `~/.cargo/registry`, `~/.cargo/git`, `~/.bun/install/cache`, `~/.nuget/packages` |

AI configuration directories must be canonical absolute paths. Existing directories are mounted
at the same paths inside the container. Codex packages, sockets and temporary state, Claude
IDE/session environment state and Copilot IDE state use container-local tmpfs mounts. The
launcher creates missing mountpoint directories within shared AI directories with host ownership
and mode 0700 after validating the image. Installed tool binaries remain supplied by the image.
Copilot's cache, including its auto-update downloads, stays outside `~/.copilot` and remains
container-local. Without a credential store in the container, `/login` there saves its token in
plain text in `~/.copilot/config.json`; sharing the `git` group lets Copilot use the `gh` login.

Claude's legacy `~/.claude.json` requires a one-time migration before AI sharing: close host
Claude sessions, move that file to `$HOME/.claude/.claude.json` after confirming the destination
does not already exist, and persist `CLAUDE_CONFIG_DIR=$HOME/.claude` in the host shell environment.
Existing destination state requires manual reconciliation. The launcher diagnoses the legacy
layout without changing host configuration. New shells then use the shared directory in both
environments. AI directories absent on the host remain container-local until created on the host.

## Runtime account

Images run as `ubuntu` (uid/gid 1000) by default. The shared entrypoint accepts an optional
runtime identity. The image label `org.opencontainers.image.runtime-user.version=1` identifies
this interface.

| Variable | Default |
|---|---|
| `CONTAINER_USER` | `ubuntu` |
| `CONTAINER_UID` | `1000` |
| `CONTAINER_GID` | `1000` |
| `CONTAINER_HOME` | `/home/<CONTAINER_USER>` |

Account setup requires `--user root`. The entrypoint initializes the account and home, then
executes the command as that non-root account. Names and numeric IDs must be available;
the home must be a canonical directory beneath `/home`. Mounted files retain their ownership.

```bash
docker run --rm --interactive --tty --user root \
  --env CONTAINER_USER=analyst --env CONTAINER_UID=1001 --env CONTAINER_GID=1001 \
  --env CONTAINER_HOME=/home/analyst \
  --env HOME=/home/analyst --env USER=analyst --env LOGNAME=analyst \
  mikaeluman/rust-datascience:latest
```

Passing `HOME`, `USER` and `LOGNAME` to Docker also supplies those values to later
`docker exec` calls. Additional shells explicitly select the account:
`docker exec --user analyst --interactive --tty CONTAINER bash`.

## Tool installations and home mounts

User-managed tools live in writable directories beneath `/opt/devtools`. Runtime account
setup assigns those image-owned files to the selected UID/GID. Apt-managed software and
system binaries retain their system locations and use `sudo` for updates.

| Installation | Location |
|---|---|
| uv tools and native CLI launchers | `/opt/devtools/bin` |
| uv Python and tool environments | `/opt/devtools/python`, `/opt/devtools/uv` |
| Bun and global packages, including Codex and Copilot CLI | `/opt/devtools/.bun` |
| Cargo and rustup | `/opt/devtools/cargo`, `/opt/devtools/rustup` |
| Claude native versions | `/opt/devtools/claude` |
| .NET global tools | `/opt/devtools/dotnet` |

The entrypoint supplies the native installers' home-directory links to these locations.
`claude update`, `codex update`, `copilot update`, `bun upgrade`, `rustup update`, and
`dotnet tool update --global` retain their normal installation interfaces. Updates persist
for the lifetime of the container; a newly created container starts from the image's pins.
For a uv tool, `uv tool install TOOL@latest` replaces the image's exact version pin;
subsequent updates use `uv tool upgrade TOOL`.

Bind mounts select configuration directories, projects and caches individually. Mounting an
entire runtime home or one of its parents is rejected during account setup. Existing paths
that shadow the native installation links are rejected rather than overwritten. Rust cache mounts target
`/opt/devtools/cargo/registry` and `/opt/devtools/cargo/git`; Bun's cache mount targets
`/opt/devtools/.bun/install/cache`.

Cross-environment configuration sharing requires matching absolute project and configuration
paths. Tool packages, daemon sockets and temporary process state need independent storage in
each environment. Those mount choices belong to the caller.
