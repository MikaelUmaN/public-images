# public-images

Docker images for analytical developer work, published as `mikaeluman/<image>:latest`.

| Image | Builds on | Adds |
|---|---|---|
| `datascience` | `ubuntu:24.04` | uv-managed Python 3.13 and JupyterLab, DuckDB, Nushell, AWS and Kubernetes CLIs, bun with Playwright, Chrome, Claude Code, Codex |
| `rust-datascience` | `datascience` | Rust toolchain, cargo tools, evcxr REPL and Jupyter kernel, libduckdb, Nushell polars plugin |
| `net-datascience` | `rust-datascience` | .NET 8 and 10 SDKs, F# tools |
| `quarto-datascience` | `net-datascience` | Quarto CLI, extended TeX Live |
| `latex` | `ubuntu:24.04` | full TeX Live, latexmk, biber |
| `pico` | `ubuntu:24.04` | Raspberry Pi Pico SDK, Arm toolchain, picotool, pioasm |

Repository instructions for coding agents are in [AGENTS.md](AGENTS.md).

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
| Bun and global packages, including Codex | `/opt/devtools/.bun` |
| Cargo and rustup | `/opt/devtools/cargo`, `/opt/devtools/rustup` |
| Claude native versions | `/opt/devtools/claude` |
| .NET global tools | `/opt/devtools/dotnet` |

The entrypoint supplies the native installers' home-directory links to these locations.
`claude update`, `codex update`, `bun upgrade`, `rustup update`, and
`dotnet tool update --global` retain their normal installation interfaces. Updates persist
for the lifetime of the container; a newly created container starts from the image's pins.
For a uv tool, `uv tool install TOOL@latest` replaces the image's exact version pin;
subsequent updates use `uv tool upgrade TOOL`.

Bind mounts select configuration directories, projects and caches individually. Mounting an
entire runtime home is rejected during account setup. Existing paths that shadow the native
installation links are rejected rather than overwritten. Rust cache mounts target
`/opt/devtools/cargo/registry` and `/opt/devtools/cargo/git`; Bun's cache mount targets
`/opt/devtools/.bun/install/cache`.

Cross-environment configuration sharing requires matching absolute project and configuration
paths. Tool packages, daemon sockets and temporary process state need independent storage in
each environment. Those mount choices belong to the caller.
