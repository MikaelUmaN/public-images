#!/bin/bash
# Smoke test for mikaeluman/datascience: the base image's major additions.
#   docker run --rm -v "$PWD/tests:/tests:ro" mikaeluman/datascience:latest bash /tests/smoke/datascience.sh
# SMOKE_SLOW=1 adds the uv sync and core Python imports.
SMOKE_NAME=datascience
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

version_check nushell nu --version
version_check duckdb duckdb --version
version_check aws_cli aws --version
version_check kubectl kubectl version --client
version_check k9s k9s version
version_check helm helm version --short
check 'duckdb select 42' duckdb -c 'select 42'

version_check uv uv --version
check 'uv python 3.13 installed' bash -c 'uv python list --only-installed | grep -F cpython-3.13'
version_check bun bun --version
check 'node resolves to bun' node -e 'console.log(process.version, process.versions.bun)'
version_check playwright playwright --version
version_check codex codex --version
version_check dotenvx dotenvx --version

version_check ruff ruff --version
version_check mypy mypy --version
version_check jupyterlab jupyter-lab --version
version_check pre_commit pre-commit --version
version_check py_spy py-spy --version

allow 'Failed to connect to the bus|dbus' 'no session bus in a container'
allow '/etc/machine-id contains 0 characters' 'no machine-id in a container'
check 'chrome headless screenshot' google-chrome-stable --headless=new --no-sandbox --screenshot="$WORK/s.png" about:blank

check 'bwrap --version' bwrap --version
check 'claude --version' claude --version
check 'gh --version' gh --version
check 'glow --version' glow --version

if [[ "${SMOKE_SLOW:-0}" == 1 ]]; then
  check 'uv sync and core imports' bash -c 'cd "$HOME/jupyter" && uv sync --quiet && uv run python -c "import pandas, polars, numpy, torch, duckdb, sklearn; print(torch.__version__)"'
fi

finish
