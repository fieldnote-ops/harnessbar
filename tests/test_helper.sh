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

# Run `open` against the real `ss`: the peer-uid gate asks ss who owns the
# other end of the connection, which the status stub cannot answer. Only the
# web-app launcher needs stubbing, so it is copied into the per-test bin dir.
open_env() {
  cp -- "$STUBS/omarchy-launch-or-focus-webapp" "$TESTROOT/bin/" 2>/dev/null || true
  PATH="$TESTROOT/bin:/usr/local/bin:/usr/bin:/bin" "$HELPER" open "$@"
}

# Minimal HTTP client for the staging-listener assertions: path, host, port.
http_get() {
  local path="$1" host="$2" port="$3"
  exec 3<>"/dev/tcp/$host/$port" 2>/dev/null || return 1
  printf 'GET %s HTTP/1.1\r\nHost: %s:%s\r\nConnection: close\r\n\r\n' "$path" "$host" "$port" >&3
  cat <&3
  exec 3<&- 3>&-
  return 0
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
assert_not_contains "logs redact JSON tokens" "$out" "abcdef1234567890"
assert_not_contains "logs redact authorization headers" "$out" "abcdefghijklmnop"
assert_not_contains "logs redact proxy passwords" "$out" "user:password"

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

# 11b. legacy runtime URL keeps the widget "running" before the restart
cat > "$HOME/.config/systemd/user/dsh-web.service" <<'EOF'
[Unit]
Description=DeepSeek Harness web UI
[Service]
ExecStart=%h/.local/bin/dsh-web-run
[Install]
WantedBy=default.target
EOF
printf 'active\n' > "$STUB_STATE_FILE"
mkdir -p "$XDG_RUNTIME_DIR/dsh-web"
printf 'http://127.0.0.1:7331/?token=legacy-secret\n' > "$XDG_RUNTIME_DIR/dsh-web/url"
chmod 600 "$XDG_RUNTIME_DIR/dsh-web/url"
: > "$STUB_SS_OPEN_FILE"
out="$("$HELPER" status 2>/dev/null)"
assert_eq "legacy runtime URL reports running" "$(printf '%s' "$out" | jq -r '.running')" "true"
assert_eq "legacy runtime URL reports port" "$(printf '%s' "$out" | jq -r '.port')" "7331"
assert_eq "legacy unit still flagged" "$(printf '%s' "$out" | jq -r '.legacy')" "true"
rm -f "$XDG_RUNTIME_DIR/dsh-web/url"

# 11c. stop refuses a unit it does not manage
setup_env
cat > "$HOME/.config/systemd/user/dsh-web.service" <<'EOF'
[Service]
ExecStart=/bin/true
EOF
printf 'active\n' > "$STUB_STATE_FILE"
out="$("$HELPER" stop 2>/dev/null)"
assert_eq "stop refuses unmanaged unit" "$?" "1"
assert_contains "stop refusal explains ownership" "$out" "not managed by harnessbar"
assert_eq "stop did not stop the unmanaged unit" "$(cat "$STUB_STATE_FILE")" "active"

# 11d. legacy detection accepts the older dsh-web helper too
cat > "$HOME/.config/systemd/user/dsh-web.service" <<'EOF'
[Service]
ExecStart=%h/.local/bin/dsh-web
EOF
out="$("$HELPER" status 2>/dev/null)"
assert_eq "dsh-web helper is detected as legacy" "$(printf '%s' "$out" | jq -r '.legacy')" "true"
out="$("$HELPER" setup-service --replace-legacy 2>/dev/null)"
assert_exit "dsh-web legacy repair" 0 $?

# 11e. remove-service aborts when stop fails and keeps the unit
setup_env
"$HELPER" setup-service >/dev/null 2>&1
printf 'active\n' > "$STUB_STATE_FILE"
: > "$STUB_SS_OPEN_FILE"
out="$(STUB_FAIL_STOP=1 "$HELPER" remove-service 2>/dev/null)"
assert_eq "remove-service fails when stop fails" "$?" "1"
assert_contains "remove failure message" "$out" "Could not stop the service"
assert_file_exists "unit kept after failed remove" "$HOME/.config/systemd/user/dsh-web.service"

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

# 15. open hands the browser a same-site login page, never the token URL
setup_env
REAL_JQ="$(command -v jq)"
cat > "$TESTROOT/bin/jq" <<EOF
#!/usr/bin/env bash
printf 'jq' >> "$TESTROOT/jq-args.log"
printf ' %q' "\$@" >> "$TESTROOT/jq-args.log"
printf '\n' >> "$TESTROOT/jq-args.log"
exec "$REAL_JQ" "\$@"
EOF
chmod +x "$TESTROOT/bin/jq"
: > "$TESTROOT/jq-args.log"
write_shell_config "12345" "$STUB_DSH_PATH"
printf 'active\n' > "$STUB_STATE_FILE"
printf 'http://127.0.0.1:12345/?token=stub-secret\n' > "$STUB_URL_FILE"
chmod 600 "$STUB_URL_FILE"
: > "$STUB_SS_OPEN_FILE"
out="$(open_env 2>/dev/null)"
assert_exit "open" 0 $?
# `open` launches the web-app window detached; wait for the stub to record it.
for _ in $(seq 1 50); do
  [[ -s "$STUB_OPEN_LOG" ]] && break
  sleep 0.05
done
open_log="$(cat "$STUB_OPEN_LOG" 2>/dev/null || true)"
assert_contains "open used the web-app launcher" "$open_log" "DeepSeek Harness http://127.0.0.1:"
assert_not_contains "launcher argv must not contain the launch token" "$open_log" "stub-secret"
assert_not_contains "launcher argv must not contain the token URL" "$open_log" "token="
stage_url="${open_log##* }"
stage_hostport="${stage_url#http://}"
stage_host="${stage_hostport%%:*}"
stage_port="${stage_hostport%%/*}"
stage_port="${stage_port##*:}"
stage_path="/${stage_hostport#*/}"
stage_file="$(find "$XDG_RUNTIME_DIR/harnessbar" -maxdepth 1 -name 'open-*.http' 2>/dev/null | head -n 1)"
assert_file_exists "open staged a private login page" "$stage_file"
assert_eq "login page is owner-only" "$(stat -c %a "$stage_file" 2>/dev/null)" "600"
assert_eq "login page pins the exact request path" "$(head -n 1 "$stage_file" 2>/dev/null)" \
  "GET $stage_path HTTP/1.1"
page_content="$(cat "$stage_file" 2>/dev/null || true)"
assert_contains "login page carries the launch URL" "$page_content" "token=stub-secret"
assert_contains "login page is the DSH launch page" "$page_content" "DeepSeek Harness"
assert_contains "login page uses a meta refresh" "$page_content" "http-equiv=\"refresh\""
assert_contains "meta refresh carries the URL unquoted" "$page_content" "content=\"0;url=http"
assert_contains "login page uses a JS redirect" "$page_content" "location.replace("
declared="$(printf '%s' "$page_content" | sed -n 's/^Content-Length: \([0-9]*\).*/\1/p' | head -n 1)"
staged_body_bytes="$(tail -n +2 -- "$stage_file" | awk 'p { printf "%s\n", $0 } /^\r$/ { p = 1 }' | wc -c)"
assert_eq "Content-Length counts bytes, not characters" "$declared" "$staged_body_bytes"
jq_args="$(cat "$TESTROOT/jq-args.log" 2>/dev/null || true)"
assert_contains "escaping helper was invoked" "$jq_args" "jq"
assert_not_contains "escaping subprocess argv must not contain the token" "$jq_args" "stub-secret"
# The listener must refuse the path a port scanner would guess ...
wrong_status="$(http_get "/open-$(date +%s).html" "$stage_host" "$stage_port" 2>/dev/null | head -n 1)"
assert_contains "staged listener refuses a wrong path" "$wrong_status" "404"
assert_file_exists "unserved login page survives a wrong-path request" "$stage_file"
# A different local user must not be able to cash in the handed-out URL: the
# URL is in launcher argv, so the listener attributes the caller instead.
if command -v curl >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  foreign_code="$(sudo -n -u nobody curl -sS -o /dev/null -w '%{http_code}' --max-time 5 "$stage_url" 2>/dev/null || true)"
  assert_eq "another uid is refused the handoff page" "$foreign_code" "403"
  assert_file_exists "a refused foreign request does not consume the page" "$stage_file"
else
  printf 'skip - cross-uid client needs passwordless sudo\n'
fi
# ... and serve the page to the browser, then take itself down.
response="$(http_get "$stage_path" "$stage_host" "$stage_port" 2>/dev/null)"
assert_contains "staged listener answers the browser" "$response" "HTTP/1.1 200 OK"
assert_contains "served page carries the launch URL" "$response" "token=stub-secret"
assert_contains "served page redirects in HTML" "$response" 'http-equiv="refresh"'
assert_contains "served page redirects in JS" "$response" "location.replace("
for _ in $(seq 1 40); do
  [[ -e $stage_file ]] || break
  sleep 0.1
done
if [[ -e $stage_file ]]; then
  fail "served login page was not removed"
else
  pass "served login page is removed"
fi
if http_get "$stage_path" "$stage_host" "$stage_port" >/dev/null 2>&1; then
  fail "staged listener kept running after serving the page"
else
  pass "staged listener stops after serving the page"
fi

# 15b. An unserved login page and its listener are removed after the TTL
setup_env
write_shell_config "12345" "$STUB_DSH_PATH"
printf 'active\n' > "$STUB_STATE_FILE"
printf 'http://127.0.0.1:12345/?token=stub-secret\n' > "$STUB_URL_FILE"
chmod 600 "$STUB_URL_FILE"
: > "$STUB_SS_OPEN_FILE"
export HARNESSBAR_OPEN_PAGE_TTL=1
out="$(open_env 2>/dev/null)"
assert_exit "open for TTL" 0 $?
for _ in $(seq 1 50); do
  [[ -s "$STUB_OPEN_LOG" ]] && break
  sleep 0.05
done
stage_url="$(cat "$STUB_OPEN_LOG")"; stage_url="${stage_url##* }"
stage_hostport="${stage_url#http://}"
stage_host="${stage_hostport%%:*}"
stage_port="${stage_hostport%%/*}"
stage_port="${stage_port##*:}"
stage_path="/${stage_hostport#*/}"
stage_file="$(find "$XDG_RUNTIME_DIR/harnessbar" -maxdepth 1 -name 'open-*.http' 2>/dev/null | head -n 1)"
for _ in $(seq 1 40); do
  [[ -e $stage_file ]] || break
  sleep 0.1
done
if [[ -e $stage_file ]]; then
  fail "unserved login page was not removed after its TTL"
else
  pass "unserved login page is removed after its TTL"
fi
if http_get "$stage_path" "$stage_host" "$stage_port" >/dev/null 2>&1; then
  fail "staged listener outlived the TTL"
else
  pass "staged listener is stopped after the TTL"
fi
unset HARNESSBAR_OPEN_PAGE_TTL

# 15bc. The listener refuses a caller whose socket belongs to another uid
setup_env
write_shell_config "12345" "$STUB_DSH_PATH"
printf 'active\n' > "$STUB_STATE_FILE"
printf 'http://127.0.0.1:12345/?token=stub-secret\n' > "$STUB_URL_FILE"
chmod 600 "$STUB_URL_FILE"
mkdir -p "$TESTROOT/fakebin"
cat > "$TESTROOT/fakebin/ss" <<'SSEOF'
#!/usr/bin/env bash
# Claim the client end of the staging connection belongs to another uid.
expr="${*: -1}"
port="${expr##*:}"
inode="$(readlink /proc/self/fd/0 2>/dev/null || true)"
inode="${inode#socket:[}"; inode="${inode%]}"
if [[ $port == 45123 ]]; then
  printf 'ESTAB 0 0 127.0.0.1:45123 127.0.0.1:%s uid:65534 ino:999999 sk:2 <->\n' "$port"
else
  printf 'ESTAB 0 0 127.0.0.1:%s 127.0.0.1:45123 users:(("bash",pid=1,fd=0)) uid:%s ino:%s sk:1 <->\n' "$port" "$(id -u)" "$inode"
fi
SSEOF
chmod +x "$TESTROOT/fakebin/ss"
cp -- "$STUBS/omarchy-launch-or-focus-webapp" "$TESTROOT/bin/"
export HARNESSBAR_OPEN_PAGE_TTL=2
out="$(PATH="$TESTROOT/fakebin:$TESTROOT/bin:/usr/local/bin:/usr/bin:/bin" "$HELPER" open 2>/dev/null)"
assert_exit "open with a foreign-uid caller" 0 $?
for _ in $(seq 1 50); do
  [[ -s "$STUB_OPEN_LOG" ]] && break
  sleep 0.05
done
stage_url="${open_log:-}"
stage_url="$(tail -n 1 "$STUB_OPEN_LOG" 2>/dev/null || true)"
stage_url="${stage_url##* }"
stage_hostport="${stage_url#http://}"
stage_host="${stage_hostport%%:*}"
stage_port="${stage_hostport%%/*}"
stage_port="${stage_port##*:}"
stage_path="/${stage_hostport#*/}"
stage_file="$(find "$XDG_RUNTIME_DIR/harnessbar" -maxdepth 1 -name 'open-*.http' 2>/dev/null | head -n 1)"
response="$(http_get "$stage_path" "$stage_host" "$stage_port" 2>/dev/null)"
assert_contains "a foreign uid is refused" "$response" "403 Forbidden"
assert_not_contains "a foreign uid gets no launch token" "$response" "stub-secret"
assert_file_exists "a refused request does not consume the page" "$stage_file"
unset HARNESSBAR_OPEN_PAGE_TTL

# 15bb. URLs with reserved characters are safely embedded in the page
setup_env
write_shell_config "12345" "$STUB_DSH_PATH"
printf 'active\n' > "$STUB_STATE_FILE"
printf 'http://127.0.0.1:12345/?token=stub-secret&scope=x%%22y\n' > "$STUB_URL_FILE"
chmod 600 "$STUB_URL_FILE"
: > "$STUB_SS_OPEN_FILE"
out="$(open_env 2>/dev/null)"
assert_exit "open with reserved characters" 0 $?
for _ in $(seq 1 50); do
  [[ -s "$STUB_OPEN_LOG" ]] && break
  sleep 0.05
done
open_log="$(cat "$STUB_OPEN_LOG" 2>/dev/null || true)"
assert_not_contains "reserved-character launch keeps token out of argv" "$open_log" "stub-secret"
stage_url="${open_log##* }"
stage_hostport="${stage_url#http://}"
stage_host="${stage_hostport%%:*}"
stage_port="${stage_hostport%%/*}"
stage_port="${stage_port##*:}"
stage_path="/${stage_hostport#*/}"
response="$(http_get "$stage_path" "$stage_host" "$stage_port" 2>/dev/null)"
assert_contains "meta refresh escapes ampersands" "$response" "&amp;scope=x"
assert_contains "JS redirect keeps a valid quoted string" "$response" "location.replace(\""


# 15c. copy-install-command copies the two supported install commands
setup_env
: > "$STUB_CLIPBOARD_FILE"
out="$("$HELPER" copy-install-command mise 2>/dev/null)"
assert_exit "copy-install-command mise" 0 $?
assert_contains "mise command copied" "$(cat "$STUB_CLIPBOARD_FILE")" "mise use -g npm:@deepseek-ai/dsh@latest"
: > "$STUB_CLIPBOARD_FILE"
out="$("$HELPER" copy-install-command npm 2>/dev/null)"
assert_exit "copy-install-command npm" 0 $?
assert_contains "npm command copied" "$(cat "$STUB_CLIPBOARD_FILE")" "npm install -g @deepseek-ai/dsh@latest"
out="$("$HELPER" copy-install-command pnpm 2>/dev/null)"
assert_eq "copy-install-command rejects unknown manager" "$?" "1"

# 15d. save-settings writes the proxy via stdin and the rest via the CLI
setup_env
"$HELPER" setup-service >/dev/null 2>&1
: > "$STUB_LOG"
cat > "$TESTROOT/bin/jq" <<'JQEOF'
#!/usr/bin/env bash
printf 'jq' >> "${JQ_LOG:-/dev/null}"
printf ' %q' "$@" >> "${JQ_LOG:-/dev/null}"
printf '\n' >> "${JQ_LOG:-/dev/null}"
exec /usr/bin/jq "$@"
JQEOF
chmod +x "$TESTROOT/bin/jq"
export JQ_LOG="$TESTROOT/jq.log"
: > "$JQ_LOG"
out="$(printf '%s' 'http://user:secret@127.0.0.1:8080' | "$HELPER" save-settings --proxy-stdin --port 7331 --dsh-path "$STUB_DSH_PATH" --start-on-login On 2>/dev/null)"
assert_exit "save-settings" 0 $?
omarchy_log="$(cat "$STUB_LOG")"
assert_contains "save-settings saves port" "$omarchy_log" "omarchy bar set io.github.fieldnote-ops.harnessbar port 7331 --json"
assert_contains "save-settings saves dshPath" "$omarchy_log" "omarchy bar set io.github.fieldnote-ops.harnessbar dshPath $STUB_DSH_PATH"
assert_contains "save-settings saves startOnLogin" "$omarchy_log" "omarchy bar set io.github.fieldnote-ops.harnessbar startOnLogin On"
assert_contains "save-settings enables the unit" "$omarchy_log" "systemctl --user enable"
assert_not_contains "proxy is not in the CLI argv" "$omarchy_log" "user:secret"
assert_not_contains "proxy is not in jq argv" "$(cat "$JQ_LOG")" "user:secret"
assert_eq "proxy is written to shell.json" \
  "$(jq -r --arg id "$PLUGIN_ID" '.. | objects | select(.id? == $id) | .proxy' "$HOME/.config/omarchy/shell.json")" \
  "http://user:secret@127.0.0.1:8080"
# clearing the proxy is allowed and writes an empty string
out="$(printf '\n' | "$HELPER" save-settings --proxy-stdin --port 7331 --dsh-path "" --start-on-login Off 2>/dev/null)"
assert_exit "save-settings clears the proxy" 0 $?
assert_eq "empty proxy written to shell.json" \
  "$(jq -r --arg id "$PLUGIN_ID" '.. | objects | select(.id? == $id) | .proxy' "$HOME/.config/omarchy/shell.json")" ""
# zero-byte stdin must not silently clear the configured proxy
write_shell_config "12345" "$STUB_DSH_PATH" ', "proxy": "http://keep-me.invalid:8080"'
out="$("$HELPER" save-settings --proxy-stdin --port 7331 --dsh-path "" --start-on-login Off < /dev/null 2>/dev/null)"
assert_eq "save-settings rejects empty stdin" "$?" "1"
assert_contains "empty stdin error message" "$out" "No proxy received"
assert_eq "failed save keeps the configured proxy" \
  "$(jq -r --arg id "$PLUGIN_ID" '.. | objects | select(.id? == $id) | .proxy' "$HOME/.config/omarchy/shell.json")" \
  "http://keep-me.invalid:8080"
rm -f "$TESTROOT/bin/jq"
hash -r

# 15e. save-settings validation rejects bad input
out="$("$HELPER" save-settings --port 70000 2>/dev/null)"
assert_eq "save-settings rejects an out-of-range port" "$?" "1"
assert_contains "port error message" "$out" "Invalid port"
out="$(printf '%s' 'ftp://example' | "$HELPER" save-settings --proxy-stdin --port 7331 --dsh-path "" --start-on-login Off 2>/dev/null)"
assert_eq "save-settings rejects a non-http proxy" "$?" "1"
assert_contains "proxy error message" "$out" "Invalid proxy URL"
out="$("$HELPER" save-settings --dsh-path relative/path 2>/dev/null)"
assert_eq "save-settings rejects a relative dshPath" "$?" "1"
assert_contains "dshPath error message" "$out" "absolute path"

# 8b. proxy credentials never enter update-command argv
setup_env
write_shell_config "12345" "$STUB_DSH_PATH" ', "proxy": "http://user:secret@127.0.0.1:7080"'
: > "$STUB_LOG"
out="$("$HELPER" update --check 2>/dev/null)"
assert_exit "proxy update check (exit)" 0 $?
out="$("$HELPER" update 2>/dev/null)"
assert_exit "proxy update apply (exit)" 0 $?
update_log="$(cat "$STUB_LOG")"
assert_not_contains "proxy is not in npm check argv" "$update_log" "user:secret"
assert_not_contains "proxy is not in npm install argv" "$update_log" "user:secret"
assert_contains "update still uses npm" "$update_log" "npm install -g @deepseek-ai/dsh@9.9.10"


# 16. startOnLogin is applied when setup-service is re-run on a managed unit
setup_env
"$HELPER" setup-service >/dev/null 2>&1
write_shell_config "12345" "$STUB_DSH_PATH" ', "startOnLogin": "On"'
out="$("$HELPER" setup-service 2>/dev/null)"
assert_exit "managed setup re-apply" 0 $?
assert_contains "startOnLogin On re-enables unit" "$(cat "$STUB_LOG")" "systemctl --user enable"

# 17. the unit template renders paths containing spaces and ampersands
setup_env
copy_root="$TESTROOT/root & dir"
mkdir -p "$copy_root"
cp -r "$ROOT/bin" "$copy_root/bin"
cp -r "$ROOT/systemd" "$copy_root/systemd"
out="$("$copy_root/bin/harnessbar" setup-service 2>/dev/null)"
assert_exit "setup-service from a path with & and spaces" 0 $?
assert_contains "ExecStart keeps the literal & path" "$(cat "$HOME/.config/systemd/user/dsh-web.service")" "$copy_root/bin/harnessbar"

# 18a. release candidates come from the newest published tag
setup_env
export STUB_DSH_VERSION=9.9.10-rc.2
export STUB_NPM_LATEST=9.9.10-rc.2
export STUB_NPM_NEXT=9.9.10-rc.3
out="$("$HELPER" update --check 2>/dev/null)"
assert_eq "prerelease follows the newest tag" "$(printf '%s' "$out" | jq -r '.latest')" "9.9.10-rc.3"
assert_eq "prerelease update reports its channel" "$(printf '%s' "$out" | jq -r '.channel')" "next"
assert_eq "prerelease update offered" "$(printf '%s' "$out" | jq -r '.updatable')" "true"
: > "$STUB_LOG"
out="$("$HELPER" update 2>/dev/null)"
assert_exit "prerelease update applies" 0 $?
assert_contains "prerelease update installs the newest tag" "$(cat "$STUB_LOG")" \
  "npm install -g @deepseek-ai/dsh@9.9.10-rc.3"

# 18b. an installed version above every tag is never downgraded
setup_env
export STUB_DSH_VERSION=9.9.10-rc.9
export STUB_NPM_LATEST=9.9.10-rc.2
export STUB_NPM_NEXT=9.9.10-rc.8
out="$("$HELPER" update --check 2>/dev/null)"
assert_eq "newer-than-tags is not an update" "$(printf '%s' "$out" | jq -r '.updatable')" "false"
assert_eq "newer-than-tags still reports the tag target" "$(printf '%s' "$out" | jq -r '.latest')" "9.9.10-rc.8"
: > "$STUB_LOG"
out="$("$HELPER" update 2>/dev/null)"
assert_eq "apply refuses to downgrade" "$?" "1"
assert_contains "downgrade refusal is explained" "$out" "refusing to downgrade"
assert_not_contains "no install runs on a downgrade" "$(cat "$STUB_LOG")" "install -g"

# 18c. prerelease identifiers compare numerically, not as strings
setup_env
export STUB_DSH_VERSION=9.9.10-rc.9
export STUB_NPM_LATEST=9.9.10-rc.9
export STUB_NPM_NEXT=9.9.10-rc.10
out="$("$HELPER" update --check 2>/dev/null)"
assert_eq "rc.10 is newer than rc.9" "$(printf '%s' "$out" | jq -r '.updatable')" "true"
assert_eq "rc.10 is the update target" "$(printf '%s' "$out" | jq -r '.latest')" "9.9.10-rc.10"

# 18d. a stable install only follows the latest tag
setup_env
export STUB_DSH_VERSION=9.9.9
export STUB_NPM_LATEST=9.9.9
export STUB_NPM_NEXT=10.0.0-rc.1
out="$("$HELPER" update --check 2>/dev/null)"
assert_eq "stable install tracks latest only" "$(printf '%s' "$out" | jq -r '.latest')" "9.9.9"
assert_eq "stable install ignores next" "$(printf '%s' "$out" | jq -r '.updatable')" "false"
: > "$STUB_LOG"
out="$("$HELPER" update 2>/dev/null)"
assert_exit "apply when already up to date" 0 $?
assert_contains "up-to-date apply says so" "$out" "already up to date"
assert_not_contains "up-to-date apply installs nothing" "$(cat "$STUB_LOG")" "install -g"
unset STUB_DSH_VERSION STUB_NPM_LATEST STUB_NPM_NEXT

# 18e. npm's array-shaped dist-tags output (cold cache) is parsed the same way
setup_env
export STUB_NPM_TAGS_SHAPE=array
out="$("$HELPER" update --check 2>/dev/null)"
assert_exit "update check with array-shaped tags" 0 $?
assert_eq "array-shaped tags still yield the latest version" "$(printf '%s' "$out" | jq -r '.latest')" "9.9.10"
assert_eq "array-shaped tags still report updatable" "$(printf '%s' "$out" | jq -r '.updatable')" "true"

# 18f. non-version dist-tag values fail closed instead of becoming a target
setup_env
export STUB_NPM_TAGS_SHAPE=garbage
out="$("$HELPER" update --check 2>/dev/null)"
assert_eq "garbage tags fail the check" "$?" "1"
assert_contains "garbage tags are explained" "$out" "Could not resolve"
unset STUB_NPM_TAGS_SHAPE

printf '\n%s/%s helper tests passed\n' "$((total - failed))" "$total"
(( failed == 0 ))
