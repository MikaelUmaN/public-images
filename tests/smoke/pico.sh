#!/bin/bash
# Smoke test for mikaeluman/pico: SDK and picotool versions, then the full toolchain test.
#   docker run --rm -v "$PWD/tests:/tests:ro" mikaeluman/pico:latest bash /tests/smoke/pico.sh
SMOKE_NAME=pico
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

pico_sdk_version() {
  local f="$PICO_SDK_PATH/pico_sdk_version.cmake" part parts=()
  for part in MAJOR MINOR REVISION; do
    parts+=("$(sed -n "s/^ *set(PICO_SDK_VERSION_${part} \([0-9]*\))/\1/p" "$f")")
  done
  local IFS=.
  printf '%s\n' "${parts[*]}"
}
version_check pico_sdk pico_sdk_version
version_check picotool picotool version
check 'pico toolchain (tests/test_pico.sh)' bash "$(dirname "${BASH_SOURCE[0]}")/../test_pico.sh"

finish
