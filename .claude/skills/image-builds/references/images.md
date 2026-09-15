# Images

The six images this repository builds, their dependency chain and what it costs to build and
test each. `FROM` is the base the Dockerfile names; a chained image pulls `mikaeluman/<base>:latest`,
which on GitHub Actions means the base published to Docker Hub, and locally means the local tag.

| Image | Dockerfile | FROM | Build cold / warm (min) | Published size | Smoke script | `EXPECT_*` honoured | Test flags |
|---|---|---|---|---|---|---|---|
| datascience | `datascience.docker` | `ubuntu:24.04` | 15–25 / 2–5 | 5.7 GB | `tests/smoke/datascience.sh` | NUSHELL, DUCKDB (`v1.x.y`), AWS_CLI, KUBECTL (`v1.x.y`), K9S (`v0.x.y`), HELM (`v3.x.y`), UV, BUN, PLAYWRIGHT, CODEX, DOTENVX, RUFF, MYPY, JUPYTERLAB, PRE_COMMIT, PY_SPY | `--slow` (uv sync, core imports, Python Playwright), `--perf`, `--sandbox` |
| rust-datascience | `rust-datascience.docker` | `mikaeluman/datascience:latest` | 45–90 / 5–15 | 9.1 GB | `tests/smoke/rust-datascience.sh` | RUST, RUSTUP | — |
| net-datascience | `net-datascience.docker` | `mikaeluman/rust-datascience:latest` | 5–10 / 1–3 | 11.5 GB | `tests/smoke/net-datascience.sh` | FANTOMAS, FSAUTOCOMPLETE, FSDOCS, FSHARPLINT | — |
| quarto-datascience | `quarto-datascience.docker` | `mikaeluman/net-datascience:latest` | 10–20 / 2–5 | 16 GB | `tests/smoke/quarto-datascience.sh` | QUARTO | `--slow` (Python-cell render, PDF render) |
| latex | `latex.docker` | `ubuntu:24.04` | 15–30 / 2 | ~6 GB | `tests/smoke/latex.sh` | — | — |
| pico | `pico.docker` | `ubuntu:24.04` | 5–10 / 1 | 6 GB | `tests/smoke/pico.sh` | PICO_SDK, PICOTOOL | — |

Chain order: `datascience → rust-datascience → net-datascience → quarto-datascience`. A change
to a chain member rebuilds everything after it. `latex` and `pico` stand alone. The GPU variant
(`--build-arg USE_TORCH_GPU=true` on datascience) is built only on request.

Warm budgets assume the BuildKit cache mounts on `/var/cache/apt` and `/var/lib/apt/lists`
are intact; `docker build --no-cache` and `docker builder prune` without a filter destroy them.

## GitHub Actions

| Fact | Value |
|---|---|
| Workflow | `.github/workflows/datascience.yml`, `workflow_dispatch` only |
| Inputs | `image` (choice of the six), `push` (boolean, default `true`) |
| Steps | checkout, Docker Hub login, `docker build`, smoke test of the built image, push when `push` is true |
| Dispatch | `gh workflow run datascience.yml --ref <branch> -f image=<image> -f push=<true\|false>` |
| Runner | `ubuntu-latest`, no cache between runs, every build cold; observed: datascience 4 min, pico 5 min, rust-datascience 44 min, net-datascience 5 min, quarto-datascience 6 min |
| Chain on CI | serial: a downstream image pulls its base `:latest` from Docker Hub, so the base run must have pushed before the next is dispatched |
| Identifying a run's image | the run log's `docker build . --file <image>.docker` line, available once the run completes |

## Test-time facts

- `tests/smoke/lib.sh` fails a check on a non-zero exit or on `warning|warn|error|fatal|panic|traceback|deprecated` in its output; `allow` lines carry a reason.
- `--perf` needs the host's `/usr/local/bin/perf` (built by `~/scripts/install-wsl2-perf.sh`); without it the smoke script prints `skip perf`.
- `--sandbox` matters for Codex: bubblewrap needs user namespaces, which Docker's default seccomp profile blocks; the probe proves `--security-opt seccomp=unconfined` restores them.
- Chrome inside the smoke run logs two container-only lines (`Failed to connect to the bus`, `/etc/machine-id contains 0 characters`), both allowlisted in `datascience.sh`.
