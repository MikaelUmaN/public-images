#!/bin/bash
# Smoke-test harness, sourced by tests/smoke/<image>.sh inside the image under test.
#
#   check <name> <cmd...>          runs the command; fails on a non-zero exit or a scan hit
#   version_check <tool> <cmd...>  as check; when EXPECT_<TOOL> is set (uppercased, '-' as '_')
#                                  the output must also contain that string
#   allow <regex> <reason>         drops matching output lines from the scan for the rest of
#                                  the script; the reason is printed so it lands in the log
#   finish                         prints the summary and exits 1 when any check failed
#
# The scan flags warning|warn|error|fatal|panic|traceback|deprecate(d), case-insensitively,
# anywhere in a check's combined stdout and stderr.
set -uo pipefail

export DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 PYTHONWARNINGS=default

SCAN='(?i)\b(warning|warn|error|fatal|panic|traceback|deprecated?)\b'
ALLOW=()
PASSED=0
FAILED=0

allow() {
  ALLOW+=("$1")
  printf 'allow  %s  (%s)\n' "$1" "$2"
}

scan_hits() {
  local text="$1" re
  for re in "${ALLOW[@]}"; do
    text=$(grep -vP -- "$re" <<<"$text" || true)
  done
  grep -P -- "$SCAN" <<<"$text" || true
}

check() {
  local name="$1"
  shift
  local out rc hits
  out=$("$@" 2>&1)
  rc=$?
  hits=$(scan_hits "$out")
  if (( rc == 0 )) && [[ -z "$hits" ]]; then
    printf 'ok     %s\n' "$name"
    PASSED=$((PASSED + 1))
    return 0
  fi
  if (( rc != 0 )); then
    printf 'FAIL   %s (rc=%d)\n' "$name" "$rc"
    tail -n 30 <<<"$out" | sed 's/^/       | /'
  else
    printf 'FAIL   %s (scan)\n' "$name"
    sed 's/^/       | /' <<<"$hits"
  fi
  FAILED=$((FAILED + 1))
  return 1
}

contains_version() {
  local want="$1"
  shift
  local out rc
  out=$("$@" 2>&1)
  rc=$?
  printf '%s\n' "$out"
  (( rc == 0 )) && grep -qF -- "$want" <<<"$out"
}

version_check() {
  local tool="$1"
  shift
  local var="EXPECT_${tool^^}"
  var=${var//-/_}
  local want="${!var:-}"
  if [[ -z "$want" ]]; then
    check "$tool version" "$@"
  else
    check "$tool == $want" contains_version "$want" "$@"
  fi
}

finish() {
  printf '\n%s: %d ok, %d failed\n' "${SMOKE_NAME:-smoke}" "$PASSED" "$FAILED"
  if (( FAILED == 0 )); then exit 0; else exit 1; fi
}
