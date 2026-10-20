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
Install it with mise or npm, or set the path explicitly:

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
- The proxy setting is malformed. Use a full URL (`http://127.0.0.1:7890`), not
  a bare `host:port`.

## The agent cannot reach the DeepSeek API

The systemd user manager does not inherit your graphical session's proxy
variables. Set the plugin's proxy and restart:

```sh
omarchy bar set io.github.fieldnote-ops.harnessbar proxy http://127.0.0.1:7890
"$HB" restart
```

`NO_PROXY` is set to `localhost,127.0.0.1,::1` automatically. Update checks use
the same proxy.

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
