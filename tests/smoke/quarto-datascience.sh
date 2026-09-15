#!/bin/bash
# Smoke test for mikaeluman/quarto-datascience: quarto check and renders.
#   docker run --rm -v "$PWD/tests:/tests:ro" mikaeluman/quarto-datascience:latest bash /tests/smoke/quarto-datascience.sh
# SMOKE_SLOW=1 adds a render with an executed Python cell (uv sync first) and a PDF render.
SMOKE_NAME=quarto-datascience
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

version_check quarto quarto --version
check 'quarto check' quarto check

printf -- '---\ntitle: Smoke\n---\n\nA paragraph with $e^{i\\pi} = -1$.\n' > "$WORK/doc.qmd"
check 'render qmd to html' bash -c 'cd "$1" && quarto render doc.qmd --to html && test -f doc.html' _ "$WORK"

if [[ "${SMOKE_SLOW:-0}" == 1 ]]; then
  printf -- '---\ntitle: Smoke\n---\n\n```{python}\nprint(1 + 1)\n```\n' > "$WORK/cell.qmd"
  check 'uv sync' bash -c 'cd "$HOME/jupyter" && uv sync --quiet'
  check 'render qmd with python cell' bash -c 'cd "$1" && uv run --directory "$HOME/jupyter" quarto render "$1/cell.qmd" --to html && grep -q ">2<" cell.html' _ "$WORK"
  check 'render qmd to pdf' bash -c 'cd "$1" && quarto render doc.qmd --to pdf && test -f doc.pdf' _ "$WORK"
fi

finish
