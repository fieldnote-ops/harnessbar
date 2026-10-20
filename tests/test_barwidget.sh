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
  if [[ ${HARNESSBAR_REQUIRE_QML:-0} == "1" ]]; then
    fail "qmllint is required (HARNESSBAR_REQUIRE_QML=1) but was not found"
  else
    printf 'skip - qmllint not installed; QML syntax not checked\n'
  fi
fi

# Qt 6.12 introduces its own Color type; Omarchy requires palette access through
# the aliased Commons import, so a bare `Color.` is a portability bug.
if grep -nE '(^|[^A-Za-z0-9_.])Color\.' BarWidget.qml Panel.qml > /tmp/harnessbar-color.log 2>&1; then
  cat /tmp/harnessbar-color.log >&2
  fail "QML must use Commons.Color, not a bare Color singleton"
else
  pass "QML uses Commons.Color"
fi

if grep -q 'textFormat: TextEdit.PlainText' Panel.qml; then
  pass "journal text is plain text"
else
  fail "journal TextEdit must set TextEdit.PlainText"
fi

if grep -q 'readonly property bool unitActive' Panel.qml; then
  pass "panel derives unit-active state for start/stop"
else
  fail "panel does not derive the unit-active state"
fi

for symbol in 'Commons.Color' 'import Quickshell' 'PanelKeyCatcher' 'KeyboardPanel'; do
  if grep -q "$symbol" BarWidget.qml Panel.qml; then
    pass "QML references $symbol"
  else
    fail "QML missing $symbol"
  fi
done

# The bar host sizes widget slots from implicitWidth/implicitHeight on the
# BarWidget root; a missing pair yields an invisible, zero-size widget.
if grep -q 'implicitWidth: button.implicitWidth' BarWidget.qml \
   && grep -q 'implicitHeight: button.implicitHeight' BarWidget.qml; then
  pass "BarWidget declares implicit slot size"
else
  fail "BarWidget is missing implicitWidth/implicitHeight"
fi

# QtQuick.Item already owns `state`; plugin code must not shadow it.
if grep -nE 'property (string|bool) state[[:space:]]*:' BarWidget.qml Panel.qml > /tmp/harnessbar-state.log 2>&1; then
  cat /tmp/harnessbar-state.log >&2
  fail "QML shadows Item.state with a property named state"
else
  pass "QML does not shadow Item.state"
fi

if grep -q 'owner: root.hostWidget || root' Panel.qml; then
  pass "KeyboardPanel uses the bar widget as its popout owner"
else
  fail "KeyboardPanel owner is not the bar widget identity"
fi

# The helper must stay self-contained: no network download-and-execute patterns.
if grep -nE 'curl[^|]*\|[[:space:]]*(ba)?sh|wget[^|]*\|[[:space:]]*(ba)?sh' bin/harnessbar > /tmp/harnessbar-curl.log 2>&1; then
  cat /tmp/harnessbar-curl.log >&2
  fail "helper downloads and executes remote code"
else
  pass "helper contains no curl-pipe-shell"
fi

printf '\n%s/%s QML checks passed\n' "$((total - failed))" "$total"
(( failed == 0 ))
