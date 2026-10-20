#!/usr/bin/env bash
# Validate the plugin repository against the Omarchy shell plugin contract.
# Mirrors the checks `omarchy plugin validate` performs so CI can gate before
# the marketplace's own validation runs.
set -u -o pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

fail() {
  printf 'validate: %s\n' "$*" >&2
  exit 1
}

command -v jq >/dev/null 2>&1 || fail "jq is required"

manifest="manifest.json"
[[ -f $manifest ]] || fail "missing manifest.json"
jq -e . "$manifest" >/dev/null 2>&1 || fail "manifest.json is not valid JSON"

jq -e '.schemaVersion == 1' "$manifest" >/dev/null 2>&1 \
  || fail "schemaVersion must be the number 1"

for field in id name version kinds entryPoints; do
  jq -e --arg f "$field" 'has($f)' "$manifest" >/dev/null 2>&1 \
    || fail "manifest missing required field '$field'"
done

id="$(jq -r '.id // ""' "$manifest")"
[[ -n $id ]] || fail "manifest id is empty"
[[ $id =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || fail "invalid plugin id '$id'"
[[ $id != *".."* ]] || fail "invalid plugin id '$id'"
[[ $id != omarchy.* ]] || fail "plugin id uses the reserved omarchy.* namespace"

version="$(jq -r '.version // ""' "$manifest")"
[[ -n $version ]] || fail "manifest version is empty"
(( ${#version} <= 64 )) || fail "version must be 64 characters or fewer"

jq -e '(.kinds | type) == "array" and (.kinds | length) > 0' "$manifest" >/dev/null 2>&1 \
  || fail "'kinds' must be a non-empty array"

jq -e '(.entryPoints | type) == "object" and (.entryPoints | length) > 0' "$manifest" >/dev/null 2>&1 \
  || fail "'entryPoints' must be a non-empty object"

while IFS= read -r entry; do
  [[ -n $entry ]] || continue
  case "$entry" in
    /* | *..* | *\\*) fail "entry point is not a safe relative path: $entry" ;;
  esac
  [[ -f $entry ]] || fail "entry point does not exist: $entry"
done < <(jq -r '.entryPoints[]' "$manifest")

jq -e '(.kinds | index("bar-widget")) == null or (.entryPoints.barWidget != null)' "$manifest" >/dev/null 2>&1 \
  || fail "a bar-widget plugin must declare entryPoints.barWidget"

section="$(jq -r '.barWidget.defaultSection // ""' "$manifest")"
case "$section" in
  ""|left|centerBegin|center|centerEnd|tray|right) ;;
  *) fail "invalid barWidget.defaultSection: $section" ;;
esac

jq -e '(.barWidget.defaults // {}) as $d | (.barWidget.schema // []) as $s | [$s[].key] - [$d | keys[]] | length == 0' "$manifest" >/dev/null 2>&1 \
  || fail "every barWidget.defaults key must have a schema entry"

if find . -type l -not -path './.git/*' | grep -q .; then
  fail "symlinks are not allowed inside a plugin folder"
fi

[[ -f README.md ]] || fail "missing README.md"
[[ -f LICENSE ]] || fail "missing LICENSE"
[[ -x bin/harnessbar ]] || fail "bin/harnessbar must be executable"
[[ -f systemd/dsh-web.service.template ]] || fail "missing systemd unit template"

printf 'validate: OK (%s %s)\n' "$id" "$version"
