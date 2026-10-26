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

## "mise update failed" in the panel

The panel now carries the tool's own reason. The common one is mise's download
guard: since mise 2026.10 npm tools install through its embedded aube client,
which refuses packages with fewer than 1000 weekly downloads. A freshly
published dsh release reports 0, so the newest release candidate is blocked
until it accumulates downloads or you approve it explicitly.

Verify the version first, then approve it for this package only:

```sh
npm view @deepseek-ai/dsh@<version> version
```

```toml
# ~/.config/mise/config.toml
[tools]
"npm:@deepseek-ai/dsh" = { version = "<version>", allow_low_downloads = true }
```

`mise install npm:@deepseek-ai/dsh` (or **Update** in the panel) then proceeds.
The approval switches off a supply-chain check for that package, so pin an exact
version you checked and revoke the option if you change registry.

## Update checks fail

Update checks run `npm view @deepseek-ai/dsh dist-tags --json` with your
optional `proxy` setting and a private npm download cache under
`${XDG_CACHE_HOME:-~/.cache}/harnessbar/npm`. The private cache exists so an
unmounted drive or an unwritable global npm cache cannot break updates. If the
check still fails, verify the proxy URL and that `npm` itself works in your
terminal:

```sh
npm view @deepseek-ai/dsh dist-tags --json
npm view @deepseek-ai/dsh versions --json | tail -5
```

## No update is offered, or the update looks like a downgrade

dsh publishes release candidates: `latest` is the recommended build, `next`
carries newer candidates, `alpha` the pre-release line. `update --check`
therefore reports a `channel` next to `current` and `latest`:

- an installed **prerelease** (anything with `-rc`, `-alpha`, `-beta`) takes the
  newest of all published tags, so `0.2.1-rc.2` is offered `0.2.1-rc.3` even
  though the newer build sits on `next`;
- an installed **stable** release only follows `latest`, so a prerelease never
  replaces it;
- an installed version that is already newer than every tag is reported as up
  to date, and `update` refuses to install an older one
  (`refusing to downgrade`).

If `latest` points below what you have installed and you want the release
candidate anyway, install it explicitly:

```sh
mise use -g npm:@deepseek-ai/dsh@<version>
```

Restarting the service afterwards makes the panel show the new version.

The update action only supports mise- and npm-managed `dsh` installations; a
manually installed copy is reported as `manual` (no npm query is attempted) and
must be updated by hand. Proxy userinfo is stripped from the service log line,
and the panel's journal view redacts common token, Authorization, and Bearer
formats plus URL credentials.

## Open UI shows "This handoff page belongs to the user who opened it"

That is the login-page listener refusing a request it could not attribute to
your user (`403`). It resolves the peer socket with `ss -tnpe` and serves only a
same-uid caller, because the handoff URL is reachable through world-readable
launcher argv and fetching it yields the launch token. A refusal does not
consume the page, so the browser can still ask for it.

- If your browser or launcher reaches the page through another user or a
  sandbox that changes the peer uid, open the UI from the panel on the local
  session instead.
- `iproute2` (`ss`) must be installed; `Open UI` refuses to stage the page
  without it.
- Repeating the open is safe: each attempt stages a fresh page and port.

## Open UI shows "dsh web authentication required"

That text is `dsh web`'s own 401 page: the browser reached the UI without a
valid session cookie. `Open UI` serves a one-shot login page from
`127.0.0.1` so the cookie exchange stays same-site, then hands the launcher
only that URL; the page is gone once the browser has fetched it.

If the message persists:

- Open again. Each `Open UI` stages a fresh page and a fresh port; a stale
  window left from an earlier session is not reused, so a new window is
  expected to authenticate.
- Check that `systemd-socket-activate` exists (it ships with systemd) — the
  helper refuses to open the UI without it.
- Confirm the runtime directory is writable: `$XDG_RUNTIME_DIR/harnessbar`
  must be owned by you, mode 700. Staged pages are the `open-*.http` files
  there and are removed after serving or within about 20 seconds.
- If you pasted the token URL into a window opened from a local file, or the
  cookie was cleared, reload the page once (the cookie is already set) or run
  `"$HB" open` again.
- The cookie is minted for one `host:port`. After changing `port`, old windows
  are unauthenticated by design; reopen from the panel.

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
