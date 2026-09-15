# AGENTS.md

Six Docker images for analytical developer work, published as `mikaeluman/<image>:latest`,
built from Ubuntu 24.04 for linux/amd64, running as user `ubuntu` (uid 1000, passwordless sudo).
This is the instruction file for coding agents; `CLAUDE.md` imports it and is never edited
(`git config core.hooksPath .githooks` activates the hook that rejects such a commit).

## Images

`ubuntu:24.04 → datascience → rust-datascience → net-datascience → quarto-datascience`, each
link pulling `mikaeluman/<base>:latest`. `latex` and `pico` build from `ubuntu:24.04` alone.

| Image | Adds |
|---|---|
| datascience | uv-managed Python 3.13 with JupyterLab and the `pyproject.toml` stack (synced at first use), DuckDB, Nushell, AWS CLI, kubectl, k9s, helm, bun with Playwright, Codex and dotenvx, Chrome, Claude Code, gh, glow, bubblewrap |
| rust-datascience | rustup toolchain, cargo tools, evcxr REPL and Jupyter kernel, libduckdb, `nu_plugin_polars` |
| net-datascience | .NET 8 and 10 SDKs from apt; fantomas, fsautocomplete, fsdocs, fsharplint |
| quarto-datascience | Quarto CLI, extended TeX Live, Quarto helper packages appended to `pyproject.toml` |
| latex | `texlive-full`, latexmk, biber |
| pico | Pico SDK at `/opt/pico-sdk`, Arm GCC, picotool and pioasm in `/usr/local`; Arm cores only |

`--build-arg USE_TORCH_GPU=true` on datascience swaps the CPU PyTorch index for CUDA. CI is a
manual dispatch of one image (`.github/workflows/datascience.yml`): build, smoke test, push
unless `push=false`.

## Routing

| Goal | Owner | Invocation |
|---|---|---|
| Build an image or the chain, only what a change touches, locally under a disk guard or on GitHub | `image-builds` skill | `/image-builds <image>... [--scope auto\|named\|downstream] [--test auto\|none\|smoke\|full] [--where local\|github\|auto]` |
| Test a built image | `image-builds` | `/image-builds <image> --test smoke [--expect TOOL=ver]` |
| Publish to Docker Hub | `image-builds` | `/image-builds <image> --where github --publish` |
| Diagnose a failed build or smoke run | `image-builds`, section Diagnose | the same call; the report quotes the log line and `file:line` |
| Check a docker start script against the images | `image-builds`, section Start script | `/image-builds <image> --start-script <path>` |
| Bump pins, check for stale pins, pin a floating install | `version-pinner` agent | Agent tool, `subagent_type: version-pinner`, prompt with `images=` and any of `packages`, `prefer`, `pin-floating`, `cluster-minor`, `start-script` |
| Choose or check one version | `lts-versions` skill | `/lts-versions <pkg> --current <ver> --install "<ARG at file:line>" [--peers a=v,...]` |
| Diagnose a failure after a version change | `lts-versions` | the same call with `--failure "<quoted log line>"` |
| End of life of a package | `lts-versions --eol` gathers; `version-pinner`, section End of life, decides | `/lts-versions <pkg> --current <ver> --install "<how>" --eol` |
| Release sources and LTS rule per ecosystem | `.claude/skills/lts-versions/references/ecosystems.md` | read |
| Build budgets, sizes, CI facts, `EXPECT_*` names | `.claude/skills/image-builds/references/images.md` | read |

## Pinning

Every toolchain and tool is an exact `ARG <NAME>_VERSION`, never `stable` or `latest`, asserted
at install (`<tool> --version | grep -F`) and echoed by `LABEL org.opencontainers.image.<tool>.version`.
Designed exceptions: Ubuntu apt (including `dotnet-sdk-*` and `texlive-*`), the vendor apt
repositories (Chrome, Charm, Claude Code, GitHub CLI), `uv python install 3.13` (minor pinned),
and `pyproject.toml` dependencies (declared, never pinned).

- A broken build is fixed by the pinned combination that works, never by widening a pin,
  dropping `--locked` or adding `|| true`.
- `RUST_VERSION` satisfies the MSRV of every `--locked` crate; one ARG per crate.
- Couplings the Dockerfiles enforce: rust-datascience asserts the DuckDB CLI equals its
  `DUCKDB_VERSION` before installing libduckdb; `nu_plugin_polars` takes its version from
  `nu --version`; the Pico SDK's `find_package(picotool <version>)` and `PIOASM_VERSION_STRING`
  make `PICO_SDK_VERSION == PICOTOOL_VERSION`. The remaining groups are the version-pinner's
  Coupled groups table.
- Work on an image includes checking its pins and naming what moves with a bump.

## Installing

Root installs apt packages and `/usr/local` binaries; after `USER $USER` toolchains install into
the home directory: bun in `~/.bun` (`node` is a symlink to bun), uv tools in `~/.local`, rustup
and cargo in `~/.rustup` and `~/.cargo`, dotnet tools in `~/.dotnet/tools`, each bin dir on `PATH`.

Release downloads are verified where the vendor publishes a signature or checksum: GPG for the
AWS CLI (`awscliv2-public-key.asc`) and the Claude Code apt key fingerprint; SHA256 for kubectl,
k9s, helm, Nushell, rustup and Quarto. The DuckDB CLI, libduckdb, the uv and bun installers and
the Pico SDK and picotool clones are fetched at a versioned URL or tag with a version assertion
and no checksum.

## apt caching

Every apt layer mounts BuildKit caches on `/var/cache/apt` and `/var/lib/apt/lists`;
rust-datascience adds `~/.cargo/registry` and `~/.cargo/git`. Each standalone image deletes
`/etc/apt/apt.conf.d/docker-clean` once so downloaded `.deb` files stay. `apt-get clean` and
`rm -rf /var/lib/apt/lists/*` never return: those paths are mounts, and the cleanup only
empties the cache. `docker build --no-cache` and an unfiltered `docker builder prune` destroy
the mounts.

## Runtime requirements

| Tool | `docker run` needs | Reason |
|---|---|---|
| TUIs (ratatui, btop, vim) | `-t`; forward `TERM` and `COLORTERM` | no tty, no alternate screen or key events; the image's `xterm-256color` and `truecolor` are the fallback |
| Chrome, headless | `--no-sandbox` on every invocation | non-root uid without `SYS_ADMIN` |
| Chrome, headed | `--shm-size=1g` and a display forwarded by the host | tabs crash on Docker's 64 MB `/dev/shm` |
| Codex CLI | `--security-opt seccomp=unconfined` | its bubblewrap sandbox needs user namespaces, which the default profile blocks |
| perf | the host binary mounted over `/usr/local/bin/perf` and `/usr/bin/perf`, plus `--cap-add PERFMON` or `SYS_PTRACE` (`SYS_ADMIN` for everything) | the image ships only the libraries perf links against |
| Home mounts | caches and single config files beneath `~/.bun`, `~/.cargo`, `~/.dotnet`, `~/.jupyter`, `~/.config/nushell`, `~/.local/state/vim`, never the parent directory | the image owns binaries, tool installs, the Jupyter server config and the Nushell plugin registry there |

The image-builds start-script check reads this table. Playwright (bun and Python) selects the
system Chrome with `channel: 'chrome'`.

## Smoke tests

`tests/smoke/<image>.sh` runs inside the image. `lib.sh` provides `check`, `version_check`
(`EXPECT_<TOOL>=<ver>` turns it into an equality check) and `allow` (with a reason), and fails a
check on a non-zero exit or on `warning|warn|error|fatal|panic|traceback|deprecate(d)` in its
output; `SMOKE_SLOW=1` adds the checks that need the project's `uv sync`. A major addition to an
image gets a check in its script. CI runs the plain form before pushing:

```bash
docker run --rm -v "$PWD/tests:/tests:ro" mikaeluman/<image>:latest bash /tests/smoke/<image>.sh
```
