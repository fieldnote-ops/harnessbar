#!/usr/bin/env bash
# Master test runner for harnessbar.
set -u -o pipefail

dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
total=0
failed=0

run() {
  local name="$1"
  shift
  total=$((total + 1))
  printf '\n▶ %s\n' "$name"
  if "$@"; then
    printf '✔ %s passed\n' "$name"
  else
    printf '✖ %s failed\n' "$name" >&2
    failed=$((failed + 1))
  fi
}

run "Manifest" bash "$dir/test_manifest.sh"
run "QML" bash "$dir/test_barwidget.sh"
run "Helper" bash "$dir/test_helper.sh"

printf '\n'
if (( failed == 0 )); then
  printf 'All %d suites passed\n' "$total"
  exit 0
fi
printf '%d/%d suites failed\n' "$failed" "$total" >&2
exit 1
