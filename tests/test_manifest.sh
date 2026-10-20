#!/usr/bin/env bash
# Manifest contract tests.
set -u -o pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/.." && pwd)"
cd "$ROOT" || exit 1

total=0
failed=0
pass() { total=$((total + 1)); printf 'ok   - %s\n' "$1"; }
fail() { total=$((total + 1)); failed=$((failed + 1)); printf 'FAIL - %s\n' "$1" >&2; }
expect_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got '$2', want '$3')"; fi; }
expect_contains() { case "$2" in *"$3"*) pass "$1" ;; *) fail "$1 (expected '$3' in '$2')" ;; esac; }

bash tools/validate.sh >/dev/null 2>&1
expect_eq "repository validates" "$?" "0"

id="$(jq -r '.id' manifest.json)"
expect_eq "plugin id" "$id" "io.github.fieldnote-ops.harnessbar"

expect_eq "version" "$(jq -r '.version' manifest.json)" "0.2.0"
expect_eq "kinds" "$(jq -r '.kinds | join(",")' manifest.json)" "bar-widget"
expect_eq "bar entry point" "$(jq -r '.entryPoints.barWidget' manifest.json)" "BarWidget.qml"
expect_eq "bar entry point exists" "$([[ -f BarWidget.qml ]] && printf yes || printf no)" "yes"
expect_eq "panel file exists" "$([[ -f Panel.qml ]] && printf yes || printf no)" "yes"

for key in port proxy dshPath openMode startOnLogin refreshSec glyph; do
  got="$(jq -r --arg k "$key" '.barWidget.schema | map(select(.key == $k)) | length' manifest.json)"
  expect_eq "schema declares $key" "$got" "1"
done

expect_eq "port default" "$(jq -r '.barWidget.defaults.port' manifest.json)" "3080"
expect_eq "refresh default" "$(jq -r '.barWidget.defaults.refreshSec' manifest.json)" "5"
expect_eq "default section" "$(jq -r '.barWidget.defaultSection' manifest.json)" "right"
expect_eq "author" "$(jq -r '.author' manifest.json)" "FIELD NOTE"
expect_eq "license" "$(jq -r '.license' manifest.json)" "MIT"
expect_contains "description mentions dsh" "$(jq -r '.description' manifest.json)" "dsh"

printf '\n%s/%s manifest tests passed\n' "$((total - failed))" "$total"
(( failed == 0 ))
