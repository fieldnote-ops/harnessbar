#!/usr/bin/env bash
# Local preflight: the same gates a push should pass.
set -u -o pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

step() { printf '\n▶ %s\n' "$*"; }
ok() { printf '✅ %s\n' "$*"; }
warn() { printf '⚠️  %s\n' "$*"; }
die() { printf '❌ %s\n' "$*" >&2; exit 1; }

step "1/3 Manifest and repository layout"
bash tools/validate.sh || die "manifest validation failed"
ok "manifest validation passed"

step "2/3 Shell helper syntax"
bash -n bin/harnessbar || die "bin/harnessbar has a syntax error"
ok "bash syntax passed"

step "3/3 Tests"
bash tests/run_tests.sh || die "test suite failed"
ok "tests passed"


if command -v omarchy >/dev/null 2>&1; then
  step "Omarchy plugin validate (local CLI)"
  omarchy plugin validate "$ROOT" || die "omarchy plugin validate failed"
  ok "omarchy plugin validate passed"
else
  warn "omarchy CLI not installed here; marketplace validation will cover compatibility"
fi

printf '\n✅ Preflight complete\n'
