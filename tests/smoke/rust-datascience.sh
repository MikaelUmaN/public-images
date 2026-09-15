#!/bin/bash
# Smoke test for mikaeluman/rust-datascience: toolchain, cargo tools, evcxr, nu polars, libduckdb.
#   docker run --rm -v "$PWD/tests:/tests:ro" mikaeluman/rust-datascience:latest bash /tests/smoke/rust-datascience.sh
SMOKE_NAME=rust-datascience
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

version_check rust rustc --version
version_check rustup rustup --version
check 'cargo new and build' bash -c 'cd "$1" && cargo new --quiet --vcs none hello && cargo build --quiet --manifest-path hello/Cargo.toml' _ "$WORK"

# XDG_CONFIG_HOME points away from ~/.config so init.evcxr's :dep lines stay out of the check.
evcxr_evaluates() {
  local out
  out=$(printf '1+1\n' | XDG_CONFIG_HOME="$WORK/xdg" evcxr 2>&1) || return
  printf '%s\n' "$out"
  grep -qx '2' <<<"$out"
}
check 'evcxr evaluates 1+1' evcxr_evaluates
check 'evcxr kernel spec installed' cat /usr/local/share/jupyter/kernels/rust/kernel.json

for tool in nextest deny outdated watch deps llvm-cov sweep cache set-version bloat machete generate audit flamegraph; do
  check "cargo $tool --version" cargo "$tool" --version
done
check 'flamegraph --version' flamegraph --version

nu_polars_roundtrips() {
  local out
  out=$(nu -c '[1 2 3] | polars into-df | polars into-nu | length' 2>&1) || return
  printf '%s\n' "$out"
  grep -qx '3' <<<"$out"
}
check 'nu polars roundtrip' nu_polars_roundtrips

libduckdb_matches_cli() {
  local cli lib
  cli=$(duckdb --version | awk '{print $1}')
  printf '#include <stdio.h>\n#include "duckdb.h"\nint main(void) { puts(duckdb_library_version()); return 0; }\n' > "$WORK/v.c"
  gcc "$WORK/v.c" -o "$WORK/v" -lduckdb || return
  lib=$("$WORK/v") || return
  printf 'cli %s  libduckdb %s\n' "$cli" "$lib"
  [[ "$cli" == "$lib" ]]
}
check 'libduckdb matches duckdb cli' libduckdb_matches_cli

finish
