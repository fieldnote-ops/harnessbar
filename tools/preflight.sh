#!/usr/bin/env bash
# Local preflight: the same gates a push should pass.
set -u -o pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

step() { printf '\n▶ %s\n' "$*"; }
ok() { printf '✅ %s\n' "$*"; }
warn() { printf '⚠️  %s\n' "$*"; }
die() { printf '❌ %s\n' "$*" >&2; exit 1; }

step "1/4 Manifest and repository layout"
bash tools/validate.sh || die "manifest validation failed"
ok "manifest validation passed"

step "2/4 Shell helper syntax"
bash -n bin/harnessbar || die "bin/harnessbar has a syntax error"
ok "bash syntax passed"

step "3/4 Tests"
bash tests/run_tests.sh || die "test suite failed"
ok "tests passed"

step "4/4 QML checks"
bash tests/test_barwidget.sh || die "QML checks failed"
ok "QML checks passed"

if command -v omarchy >/dev/null 2>&1; then
  step "Omarchy plugin validate (local CLI)"
  omarchy plugin validate "$ROOT" || die "omarchy plugin validate failed"
  ok "omarchy plugin validate passed"
else
  warn "omarchy CLI not installed here; marketplace validation will cover compatibility"
fi

printf '\n✅ Preflight complete\n'
