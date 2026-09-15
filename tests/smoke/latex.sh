#!/bin/bash
# Smoke test for mikaeluman/latex: a latexmk build using common packages, and biblatex present.
#   docker run --rm -v "$PWD/tests:/tests:ro" mikaeluman/latex:latest bash /tests/smoke/latex.sh
SMOKE_NAME=latex
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/doc.tex" <<'TEX'
\documentclass{article}
\usepackage{amsmath}
\usepackage{graphicx}
\usepackage{hyperref}
\begin{document}
\section{Smoke}
\begin{equation}
  e^{i\pi} + 1 = 0
\end{equation}
See \url{https://example.org}.
\end{document}
TEX
check 'latexmk -pdf' bash -c 'cd "$1" && latexmk -pdf -interaction=nonstopmode -halt-on-error -silent doc.tex && test -f doc.pdf' _ "$WORK"
check 'kpsewhich biblatex.sty' kpsewhich biblatex.sty
check 'biber --version' biber --version
check 'xelatex --version' xelatex --version

finish
