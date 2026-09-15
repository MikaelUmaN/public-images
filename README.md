# public-images

Docker images for analytical developer work, published as `mikaeluman/<image>:latest`.

| Image | Builds on | Adds |
|---|---|---|
| `datascience` | `ubuntu:24.04` | uv-managed Python 3.13 and JupyterLab, DuckDB, Nushell, AWS and Kubernetes CLIs, bun with Playwright and Codex, Chrome, Claude Code |
| `rust-datascience` | `datascience` | Rust toolchain, cargo tools, evcxr REPL and Jupyter kernel, libduckdb, Nushell polars plugin |
| `net-datascience` | `rust-datascience` | .NET 8 and 10 SDKs, F# tools |
| `quarto-datascience` | `net-datascience` | Quarto CLI, extended TeX Live |
| `latex` | `ubuntu:24.04` | full TeX Live, latexmk, biber |
| `pico` | `ubuntu:24.04` | Raspberry Pi Pico SDK, Arm toolchain, picotool, pioasm |

Repository instructions for coding agents are in [AGENTS.md](AGENTS.md).
