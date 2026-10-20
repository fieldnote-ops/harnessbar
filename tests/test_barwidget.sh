#!/usr/bin/env bash
# QML checks: qmllint when available, plus repository-specific lint rules.
set -u -o pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/.." && pwd)"
cd "$ROOT" || exit 1

total=0
failed=0
pass() { total=$((total + 1)); printf 'ok   - %s\n' "$1"; }
fail() { total=$((total + 1)); failed=$((failed + 1)); printf 'FAIL - %s\n' "$1" >&2; }

shell_root=""
for candidate in "${OMARCHY_PATH:-}/shell" /usr/share/omarchy/shell; do
  [[ -n $candidate && -d $candidate ]] && shell_root="$candidate" && break
done

if command -v qmllint >/dev/null 2>&1; then
  args=()
  [[ -n $shell_root ]] && args=(-I "$shell_root")
  if qmllint "${args[@]}" BarWidget.qml Panel.qml >/tmp/harnessbar-qmllint.log 2>&1; then
    pass "qmllint BarWidget.qml Panel.qml"
  else
    cat /tmp/harnessbar-qmllint.log >&2
    fail "qmllint BarWidget.qml Panel.qml"
  fi
else
  printf 'skip - qmllint not installed; QML syntax not checked\n'
fi

if qmllint --version >/dev/null 2>&1; then
  pass "qmllint is available"
fi

# Qt 6.12 introduces its own Color type; Omarchy requires palette access through
# the aliased Commons import, so a bare `Color.` is a portability bug.
if grep -nE '(^|[^A-Za-z0-9_.])Color\.' BarWidget.qml Panel.qml > /tmp/harnessbar-color.log 2>&1; then
  cat /tmp/harnessbar-color.log >&2
  fail "QML must use Commons.Color, not a bare Color singleton"
else
  pass "QML uses Commons.Color"
fi

for symbol in 'Commons.Color' 'import Quickshell' 'PanelKeyCatcher' 'KeyboardPanel'; do
  if grep -q "$symbol" BarWidget.qml Panel.qml; then
    pass "QML references $symbol"
  else
    fail "QML missing $symbol"
  fi
done

# The helper must stay self-contained: no network download-and-execute patterns.
if grep -nE 'curl[^|]*\|[[:space:]]*(ba)?sh|wget[^|]*\|[[:space:]]*(ba)?sh' bin/harnessbar > /tmp/harnessbar-curl.log 2>&1; then
  cat /tmp/harnessbar-curl.log >&2
  fail "helper downloads and executes remote code"
else
  pass "helper contains no curl-pipe-shell"
fi

printf '\n%s/%s QML checks passed\n' "$((total - failed))" "$total"
(( failed == 0 ))
