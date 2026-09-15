#!/bin/bash
# Smoke test for mikaeluman/net-datascience: both .NET SDKs, an F# build and run, F# tools.
#   docker run --rm -v "$PWD/tests:/tests:ro" mikaeluman/net-datascience:latest bash /tests/smoke/net-datascience.sh
SMOKE_NAME=net-datascience
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

check 'dotnet sdk 8.0 present' bash -c 'dotnet --list-sdks | grep "^8\.0\."'
check 'dotnet sdk 10.0 present' bash -c 'dotnet --list-sdks | grep "^10\.0\."'
check 'F# console new, build, run' bash -c 'cd "$1" && dotnet new console -lang "F#" -o hello && dotnet run --project hello | grep -F "Hello from F#"' _ "$WORK"

version_check fantomas fantomas --version
version_check fsautocomplete fsautocomplete --version
# fsdocs exits 1 after printing its version, so the check reads the output rather than the exit code.
fsdocs_prints_version() {
  local out
  out=$(fsdocs --version 2>&1)
  printf '%s\n' "$out"
  grep -qE '^fsdocs [0-9]' <<<"$out" && grep -qF -- "${EXPECT_FSDOCS:-}" <<<"$out"
}
check 'fsdocs version' fsdocs_prints_version
version_check fsharplint dotnet fsharplint --version

finish
