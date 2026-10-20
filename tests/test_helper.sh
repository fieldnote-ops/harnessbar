#!/usr/bin/env bash
# Helper test suite. Exercises bin/harnessbar with stubbed systemctl/dsh/npm.
set -u -o pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/.." && pwd)"
STUBS="$HERE/stubs"
HELPER="$ROOT/bin/harnessbar"
PLUGIN_ID="io.github.fieldnote-ops.harnessbar"

total=0
failed=0
pass() { total=$((total + 1)); printf 'ok   - %s\n' "$1"; }
fail() { total=$((total + 1)); failed=$((failed + 1)); printf 'FAIL - %s\n' "$1" >&2; }

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got '$2', want '$3')"; fi
}
assert_contains() {
  case "$2" in *"$3"*) pass "$1" ;; *) fail "$1 (expected '$3' in '$2')" ;; esac
}
assert_not_contains() {
  case "$2" in *"$3"*) fail "$1 (unexpected '$3' in '$2')" ;; *) pass "$1" ;; esac
}
assert_file_exists() {
  if [[ -e "$2" ]]; then pass "$1"; else fail "$1 (missing $2)"; fi
}
assert_exit() {
  local label="$1" want="$2" got="$3"
  assert_eq "$label (exit)" "$got" "$want"
}

setup_env() {
  TESTROOT="$(mktemp -d /tmp/harnessbar-helper-test.XXXXXX)"
  export TESTROOT
  unset RUNTIME_DIRECTORY 2>/dev/null || true
  export HOME="$TESTROOT/home"
  export XDG_RUNTIME_DIR="$TESTROOT/runtime"
  export XDG_STATE_HOME="$TESTROOT/state"
  export XDG_CACHE_HOME="$TESTROOT/cache"
  mkdir -p "$HOME/.config/omarchy" "$HOME/.config/systemd/user" "$HOME/.local/bin" \
    "$XDG_RUNTIME_DIR/harnessbar" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" "$TESTROOT/bin"
  chmod 700 "$XDG_RUNTIME_DIR/harnessbar" 2>/dev/null || true

  export STUB_LOG="$TESTROOT/systemctl.log"
  export STUB_STATE_FILE="$TESTROOT/unit-state"
  export STUB_URL_FILE="$XDG_RUNTIME_DIR/harnessbar/url"
  export STUB_SS_OPEN_FILE="$TESTROOT/ss-open"
  export STUB_SS_PORT=12345
  export STUB_URL_PORT=12345
  export STUB_OPEN_LOG="$TESTROOT/open.log"
  export STUB_CLIPBOARD_FILE="$TESTROOT/clipboard.txt"
  printf 'inactive\n' > "$STUB_STATE_FILE"
  : > "$STUB_LOG"

  export STUB_DSH_PATH="$TESTROOT/bin/dsh"
  cp "$STUBS/dsh" "$STUB_DSH_PATH"
  chmod +x "$STUB_DSH_PATH"
  export PATH="$STUBS:$TESTROOT/bin:/usr/local/bin:/usr/bin:/bin"
  unset DSH_BIN 2>/dev/null || true

  write_shell_config "12345" "$STUB_DSH_PATH"
}

write_shell_config() {
  local port="$1" dsh_path="$2" extra="${3:-}"
  mkdir -p "$HOME/.config/omarchy"
  {
    printf '{\n  "version": 1,\n  "bar": { "layout": { "right": [ { "id": "%s", "port": %s, "dshPath": "%s", "startOnLogin": "On"%s } ] } }\n}\n' \
      "$PLUGIN_ID" "$port" "$dsh_path" "$extra"
  } > "$HOME/.config/omarchy/shell.json"
}

teardown_env() {
  [[ -n ${TESTROOT:-} ]] && rm -rf "$TESTROOT"
  unset TESTROOT HOME 2>/dev/null || true
}

# --- tests -----------------------------------------------------------------

setup_env
trap teardown_env EXIT

# 1. status: no service installed yet
out="$("$HELPER" status 2>/dev/null)"
assert_exit "status without service" 0 $?
assert_eq "state is no-service" "$(printf '%s' "$out" | jq -r '.state')" "no-service"
assert_eq "not running" "$(printf '%s' "$out" | jq -r '.running')" "false"
assert_eq "unit not installed" "$(printf '%s' "$out" | jq -r '.unit_installed')" "false"
assert_eq "dsh resolved from settings" "$(printf '%s' "$out" | jq -r '.dsh_source')" "settings"

# 2. setup-service writes a managed unit and enables login start
out="$("$HELPER" setup-service 2>/dev/null)"
assert_exit "setup-service" 0 $?
assert_contains "setup message" "$out" "Service installed"
assert_file_exists "unit written" "$HOME/.config/systemd/user/dsh-web.service"
unit_content="$(cat "$HOME/.config/systemd/user/dsh-web.service")"
assert_contains "unit is marked managed" "$unit_content" "Managed by harnessbar"
assert_contains "unit runs plugin helper" "$unit_content" "ExecStart=\"$ROOT/bin/harnessbar\" run"
assert_contains "startOnLogin enables unit" "$(cat "$STUB_LOG")" "systemctl --user enable"

# 3. status: managed but stopped
out="$("$HELPER" status 2>/dev/null)"
assert_eq "managed detected" "$(printf '%s' "$out" | jq -r '.managed')" "true"
assert_eq "stopped state" "$(printf '%s' "$out" | jq -r '.state')" "stopped"

# 4. start -> running
out="$("$HELPER" start 2>/dev/null)"
assert_exit "start" 0 $?
assert_contains "start message" "$out" "started"
out="$("$HELPER" status 2>/dev/null)"
assert_eq "running after start" "$(printf '%s' "$out" | jq -r '.running')" "true"
assert_eq "pid from listener" "$(printf '%s' "$out" | jq -r '.pid')" "4242"
assert_eq "supervised" "$(printf '%s' "$out" | jq -r '.supervised')" "true"

# 5. copy-url uses the clipboard and returns the launch URL
: > "$STUB_CLIPBOARD_FILE"
out="$("$HELPER" copy-url 2>/dev/null)"
assert_exit "copy-url" 0 $?
assert_contains "clipboard has token URL" "$(cat "$STUB_CLIPBOARD_FILE")" "token=stub-secret"

# 6. logs are redacted
out="$("$HELPER" logs 2>/dev/null)"
assert_contains "logs keep the host line" "$out" "dsh web:"
assert_not_contains "logs redact tokens" "$out" "super-secret-token"
assert_contains "logs show redaction marker" "$out" "token=***"

# 7. update check
out="$("$HELPER" update --check 2>/dev/null)"
assert_exit "update check" 0 $?
assert_eq "update current" "$(printf '%s' "$out" | jq -r '.current')" "9.9.9"
assert_eq "update latest" "$(printf '%s' "$out" | jq -r '.latest')" "9.9.10"
assert_eq "update manager" "$(printf '%s' "$out" | jq -r '.manager')" "npm"
assert_eq "update available" "$(printf '%s' "$out" | jq -r '.updatable')" "true"

# 8. update applies through npm
out="$("$HELPER" update 2>/dev/null)"
assert_exit "update apply" 0 $?
assert_contains "update message" "$out" "9.9.10"
assert_contains "npm install invoked" "$(cat "$STUB_LOG")" "npm install -g @deepseek-ai/dsh@9.9.10"

# 9. stop -> stopped
out="$("$HELPER" stop 2>/dev/null)"
assert_exit "stop" 0 $?
out="$("$HELPER" status 2>/dev/null)"
assert_eq "stopped state after stop" "$(printf '%s' "$out" | jq -r '.state')" "stopped"

# 10. remove-service on a managed unit
out="$("$HELPER" remove-service 2>/dev/null)"
assert_exit "remove-service" 0 $?
assert_contains "remove message" "$out" "Service removed"
if [[ -e "$HOME/.config/systemd/user/dsh-web.service" ]]; then
  fail "remove-service deleted the unit"
else
  pass "remove-service deleted the unit"
fi

# 11. legacy unit detection and repair
cat > "$HOME/.config/systemd/user/dsh-web.service" <<'EOF'
[Unit]
Description=DeepSeek Harness web UI
[Service]
ExecStart=%h/.local/bin/dsh-web-run
[Install]
WantedBy=default.target
EOF
out="$("$HELPER" status 2>/dev/null)"
assert_eq "legacy detected" "$(printf '%s' "$out" | jq -r '.legacy')" "true"
out="$("$HELPER" setup-service 2>/dev/null)"
assert_eq "unmanaged setup refuses" "$?" "1"
assert_contains "refusal explains repair" "$out" "--replace-legacy"
out="$("$HELPER" setup-service --replace-legacy 2>/dev/null)"
assert_exit "legacy repair" 0 $?
assert_contains "repaired unit is managed" "$(cat "$HOME/.config/systemd/user/dsh-web.service")" "Managed by harnessbar"
backup_count="$(find "$HOME/.config/systemd/user" -name 'dsh-web.service.bak.*' | wc -l | tr -d ' ')"
assert_eq "legacy unit backed up" "$backup_count" "1"

# 12. remove-service refuses an unmanaged unit
printf '[Service]\nExecStart=/bin/true\n' > "$HOME/.config/systemd/user/dsh-web.service"
out="$("$HELPER" remove-service 2>/dev/null)"
assert_eq "unmanaged remove refuses" "$?" "1"
assert_contains "unmanaged remove message" "$out" "Refusing"

# 13. status reports missing dsh clearly
write_shell_config "12345" ""
mkdir -p "$TESTROOT/no-dsh-bin"
cp "$STUBS/systemctl" "$STUBS/ss" "$STUBS/mise" "$TESTROOT/no-dsh-bin/"
export PATH="$TESTROOT/no-dsh-bin:/usr/bin:/bin"
unset STUB_DSH_PATH DSH_BIN 2>/dev/null || true
rm -f "$HOME/.local/share/mise/shims/dsh" 2>/dev/null || true
out="$("$HELPER" status 2>/dev/null)"
assert_eq "no-dsh state" "$(printf '%s' "$out" | jq -r '.state')" "no-dsh"

# 14. run mode: captures the URL privately and redacts the token from output
setup_env
export STUB_DSH_SLEEP=2
write_shell_config "12345" "$STUB_DSH_PATH"
run_out="$TESTROOT/run.out"
"$HELPER" run > "$run_out" 2>&1 &
run_pid=$!
url=""
for _ in $(seq 1 50); do
  if [[ -s "$XDG_RUNTIME_DIR/harnessbar/url" ]]; then
    url="$(cat "$XDG_RUNTIME_DIR/harnessbar/url")"
    break
  fi
  sleep 0.1
done
assert_contains "run publishes a token URL" "$url" "token=stub-secret"
assert_eq "URL file is owner-only" "$(stat -c %a "$XDG_RUNTIME_DIR/harnessbar/url" 2>/dev/null)" "600"
sleep 0.3
kill "$run_pid" 2>/dev/null || true
wait "$run_pid" 2>/dev/null || true
run_log="$(cat "$run_out")"
assert_contains "run announces the listener" "$run_log" "launch token captured and hidden"
assert_not_contains "run keeps the token out of the log" "$run_log" "stub-secret"

# 15. open launches the Omarchy web app with the token URL
setup_env
write_shell_config "12345" "$STUB_DSH_PATH"
printf 'active\n' > "$STUB_STATE_FILE"
printf 'http://127.0.0.1:12345/?token=stub-secret\n' > "$STUB_URL_FILE"
chmod 600 "$STUB_URL_FILE"
: > "$STUB_SS_OPEN_FILE"
out="$("$HELPER" open 2>/dev/null)"
assert_exit "open" 0 $?
assert_contains "open used the web-app launcher" "$(cat "$STUB_OPEN_LOG")" "DeepSeek Harness http://127.0.0.1:12345/?token=stub-secret"

printf '\n%s/%s helper tests passed\n' "$((total - failed))" "$total"
(( failed == 0 ))
