# Images

The six images, what each build and test costs, and the facts the skill reads per image. `FROM`
is the base the Dockerfile names; a chained image pulls `mikaeluman/<base>:latest`, which on
GitHub Actions means the base published to Docker Hub and locally means the local tag.

| Image | Dockerfile | FROM | Build cold / warm (min) | Published size | Smoke script | `EXPECT_*` honoured | `full` adds |
|---|---|---|---|---|---|---|---|
| datascience | `datascience.docker` | `ubuntu:24.04` | 15–25 / 2–5 | 5.7 GB | `tests/smoke/datascience.sh` | NUSHELL, DUCKDB (`v1.x.y`), AWS_CLI, KUBECTL (`v1.x.y`), K9S (`v0.x.y`), HELM (`v3.x.y`), UV, BUN, PLAYWRIGHT, CODEX, DOTENVX, RUFF, MYPY, JUPYTERLAB, PRE_COMMIT, PY_SPY | `--slow` (uv sync, core imports, Python Playwright), `--perf`, `--sandbox` |
| rust-datascience | `rust-datascience.docker` | `mikaeluman/datascience:latest` | 45–90 / 5–15 | 9.1 GB | `tests/smoke/rust-datascience.sh` | RUST, RUSTUP | — |
| net-datascience | `net-datascience.docker` | `mikaeluman/rust-datascience:latest` | 5–10 / 1–3 | 11.5 GB | `tests/smoke/net-datascience.sh` | FANTOMAS, FSAUTOCOMPLETE, FSDOCS, FSHARPLINT | — |
| quarto-datascience | `quarto-datascience.docker` | `mikaeluman/net-datascience:latest` | 10–20 / 2–5 | 16 GB | `tests/smoke/quarto-datascience.sh` | QUARTO | `--slow` (Python-cell render, PDF render) |
| latex | `latex.docker` | `ubuntu:24.04` | 15–30 / 2 | ~6 GB | `tests/smoke/latex.sh` | — | — |
| pico | `pico.docker` | `ubuntu:24.04` | 5–10 / 1 | 6 GB | `tests/smoke/pico.sh` | PICO_SDK, PICOTOOL | — |

The GPU variant (`--build-arg USE_TORCH_GPU=true` on datascience) is built only on request.

Build states: *cached*, no instruction or parent changed, under a minute; *warm*, the layers
after the first changed instruction rebuild while the BuildKit cache mounts on `/var/cache/apt`,
`/var/lib/apt/lists` and `~/.cargo/{registry,git}` serve the downloads; *cold*, every layer
rebuilds. A base whose id changed makes every downstream image cold apart from the cache
mounts: the chain after datascience costs 60–120 min locally and 55 min on GitHub.
`docker build --no-cache` and an unfiltered `docker builder prune` destroy the cache mounts.

## GitHub Actions

| Fact | Value |
|---|---|
| Workflow | `.github/workflows/datascience.yml`, `workflow_dispatch` only; run name `<image> push=<bool>` |
| Inputs | `image` (choice of the six), `push` (boolean, default `true`) |
| Steps | checkout, Docker Hub login, `docker build`, smoke test of the built image, push when `push` is true |
| Dispatch | `gh workflow run datascience.yml --ref <branch> -f image=<image> -f push=<true\|false>` |
| Runner | `ubuntu-latest`, no cache between runs, every build cold; observed: datascience 4 min, pico 5 min, rust-datascience 44 min, net-datascience 5 min, quarto-datascience 6 min |
| Chain on CI | serial: the base run must have pushed before the next link is dispatched |

## Test-time facts

- `tests/smoke/lib.sh` fails a check on a non-zero exit or on `warning|warn|error|fatal|panic|traceback|deprecate(d)` in its output; `allow` lines carry a reason.
- A plain smoke run costs 1–3 min per image; `--slow` runs the project's `uv sync` (torch included) on datascience and quarto-datascience.
- `--perf` needs the host's `/usr/local/bin/perf`; without it the smoke script prints `skip perf`.
- `--sandbox` adds `--security-opt seccomp=unconfined` and probes `bwrap --unshare-all` first; it matters after a Codex or bubblewrap change.
- Chrome inside the smoke run logs two container-only lines (`Failed to connect to the bus`, `/etc/machine-id contains 0 characters`), both allowlisted in `datascience.sh`.
