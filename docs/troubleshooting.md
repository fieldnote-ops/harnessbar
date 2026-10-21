# Troubleshooting

The helper is the source of truth for every symptom. Run it from a terminal:

```sh
HB=~/.config/omarchy/plugins/io.github.fieldnote-ops.harnessbar/bin/harnessbar
"$HB" status | jq .
"$HB" logs 120
journalctl --user -u dsh-web.service -n 200 --no-pager
```

## The panel says "dsh not found"

The helper resolves `dsh` in this order: `dshPath` setting → `DSH_BIN` →
`~/.local/share/mise/shims/dsh` → `mise which dsh` → `PATH` → `~/.local/bin`.
Install it with mise or npm (the panel offers both commands with Copy buttons),
or set the path explicitly in the panel settings editor / CLI:

```sh
omarchy bar set io.github.fieldnote-ops.harnessbar dshPath /absolute/path/to/dsh
```

## The service is installed but fails to start

```sh
systemctl --user status dsh-web.service
journalctl --user -u dsh-web.service -n 100 --no-pager
```

Common causes:

- `dsh` is not executable from the service environment (fix `dshPath`).
- The port is already in use. Set another port and restart:
  ```sh
  omarchy bar set io.github.fieldnote-ops.harnessbar port 0 --json
  "$HB" restart
  ```
  `0` lets the OS pick a free port; the panel then shows the actual port.
- The proxy setting is malformed. Use a full URL (`http://127.0.0.1:8080`), not
  a bare `host:port`. The panel validates the scheme before saving; credentials
  in the URL are fine, since the panel passes them over stdin and they are
  stored plaintext in `shell.json`.

## The agent cannot reach the DeepSeek API

The systemd user manager does not inherit your graphical session's proxy
variables. Set the plugin's proxy (panel Settings → Edit, or CLI) and restart:

```sh
omarchy bar set io.github.fieldnote-ops.harnessbar proxy http://127.0.0.1:8080
"$HB" restart
```

`NO_PROXY` is set to `localhost,127.0.0.1,::1` automatically. Update checks use
the same proxy.

## Stop or remove is refused

`Stop` and `Remove service` only act on a unit carrying harnessbar's marker.
A legacy `~/.local/bin` unit must be repaired first (**Repair service** or
`setup-service --replace-legacy`). `remove-service` also refuses to delete the
unit if stopping it fails, so a running process is never left unsupervised.

## Changing startOnLogin has no effect

Saving settings from the panel applies start-on-login immediately. If you only
used `omarchy bar set`, re-apply the unit with panel → **Re-apply unit** (or
`"$HB" setup-service`). Port and proxy changes require a **Restart** afterwards.

## "Legacy service detected"

An older local setup shipped `~/.local/bin/dsh-web`, `dsh-web-run`, and a
`dsh-web.service` unit. harnessbar detects that unit and offers **Repair
service** in the panel. The terminal equivalent is:

```sh
"$HB" setup-service --replace-legacy
"$HB" restart
```

The old unit file is backed up next to the new one (`dsh-web.service.bak.*`).
The old helper scripts in `~/.local/bin` are left alone; delete them manually
once you are satisfied.

## Starting or stopping disconnects my browser session

Restarting the service terminates the `dsh web` process, so any open page loses
its connection and running agent tasks may be interrupted. That is why the
panel asks for confirmation. Session data lives in `~/.dsh` and survives; reopen
the UI afterwards.

## Update checks fail

Update checks run `npm view @deepseek-ai/dsh version` with your optional
`proxy` setting and a private npm download cache under
`${XDG_CACHE_HOME:-~/.cache}/harnessbar/npm`. The private cache exists so an
unmounted drive or an unwritable global npm cache cannot break updates. If the
check still fails, verify the proxy URL and that `npm` itself works in your
terminal:

```sh
npm view @deepseek-ai/dsh version
```

The update action only supports mise- and npm-managed `dsh` installations; a
manually installed copy is reported as `manual` (no npm query is attempted) and
must be updated by hand. Proxy userinfo is stripped from the service log line,
and the panel's journal view redacts common token, Authorization, and Bearer
formats plus URL credentials.

## Open UI opens a blank/local page

`Open UI` passes the browser a private `file://` redirect page instead of the
token URL, so the token never appears in process arguments. If that page stays
blank, the launcher or browser may have refused the local file; check the
browser console and confirm the runtime directory is `$XDG_RUNTIME_DIR/harnessbar`.
The page is deleted about 20 seconds after launch; opening again recreates it.

## An old browser process still shows the launch token in its argv

Versions before 0.2.2 passed the tokenized URL directly to the browser, so a
browser process launched by them keeps that token in `/proc/<pid>/cmdline`
until it exits. Close the DeepSeek Harness window (or the browser) and reopen
it from the panel; restarting `dsh-web.service` also invalidates the old token.
New opens never pass the token as an argument.

## Copy URL does nothing

Install `wl-clipboard` (for Wayland) or `xclip`/`xsel` (XWayland). The panel
reports a clear error when no clipboard tool is available. The copied URL is a
credential: avoid pasting it into public places, and remember that clipboard
managers and screenshots may retain it.

## Removing everything

1. Panel → **Remove service**, or `"$HB" remove-service`.
2. `omarchy plugin remove io.github.fieldnote-ops.harnessbar --yes`
3. Optionally delete leftover legacy helpers and backups:

```sh
rm -f ~/.local/bin/dsh-web ~/.local/bin/dsh-web-run
rm -f ~/.config/systemd/user/dsh-web.service.bak.*
```

`~/.dsh` (sessions, settings, credentials) is never modified by harnessbar and
must be removed separately if you really want a clean slate.

## Running without systemd

The plugin is designed around a systemd user service. If systemd is unavailable,
`start`/`stop` will report that the service cannot be supervised; you can still
run `dsh web --no-open` manually in a terminal. The repository's tests stub out
systemd entirely, which is a useful reference for the helper behavior.
