# DeepSeek Harness for Omarchy

[![validate](https://github.com/fieldnote-ops/harnessbar/actions/workflows/validate.yml/badge.svg?branch=main)](https://github.com/fieldnote-ops/harnessbar/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Omarchy](https://img.shields.io/badge/Omarchy-4%20Quattro-blue.svg)](https://omarchy.org/)

**harnessbar** is a service-grade Omarchy bar widget for the local
[DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) web UI
(`dsh web`). It runs the web UI as a systemd **user** service, shows health and
version at a glance, surfaces the journal, checks for updates, and passes your
proxy through — without keeping a terminal open.

![harnessbar panel](preview.png)

> Independent community project by **FIELD NOTE**. Not affiliated with,
> sponsored by, or endorsed by DeepSeek or Omarchy. DeepSeek Harness is named
> only to describe compatibility; DeepSeek and Omarchy are trademarks of their
> respective owners.

## Why another dsh widget?

A plain toggle starts a process and hopes for the best. harnessbar treats
`dsh web` as a service:

- **Supervised**: a systemd user unit with `Restart=on-failure`; the service
  survives `omarchy restart shell`, and the bar reconnects to it.
- **Start on login**: opt-in `systemctl --user enable`, no terminal needed.
- **Observable**: version, host:port, health, and a redacted journal tail in
  the panel.
- **Updatable**: detects mise vs npm installations; the panel quietly checks
  for a newer dsh when opened, shows the installed → latest versions, and
  updates on request with a confirm (then restarts the service). Updates follow
  the published tags: an installed prerelease takes the newest of `latest` and
  `next` (dsh publishes release candidates under `next`), a stable install only
  follows `latest`, and a version that is already newer than every tag is never
  replaced by an older one.
- **Proxy-aware**: the optional `proxy` setting is applied to the service and
  to update commands — important on networks where the DeepSeek API needs a
  local proxy.
- **Migratable**: finds the older `~/.local/bin/dsh-web*` unit and repairs it
  in place.

## Requirements

| Dependency | Why | Notes |
|---|---|---|
| Omarchy 4 (Quattro) | Hosts the shell and the bar widget | Developed and tested on Omarchy 4.0.6 |
| `dsh` | The web UI this widget manages | Tested with `@deepseek-ai/dsh` 0.2.1-rc.3; install with mise or npm |
| systemd user manager | Runs the background service | Standard on Omarchy |
| `systemd-socket-activate` | Serves the one-shot login page **Open UI** hands the browser | Ships with systemd; `Open UI` reports a clear error when it is missing |
| `iproute2` (`ss`) | Attributes the login-page request to your user before serving it | Standard on Omarchy; `Open UI` refuses to stage a page without it |
| `jq` | Reads inline settings and formats the status JSON | Present on Omarchy by default |
| `wl-clipboard` | Optional, for **Copy URL** | The button reports a clear error when absent |

`dsh` is not a system package. Install it however you manage tools:

```sh
mise use -g npm:@deepseek-ai/dsh@latest
# or
npm install -g @deepseek-ai/dsh@latest
```

## Install

```sh
omarchy plugin add https://github.com/fieldnote-ops/harnessbar.git --enable --yes
```

The plugin lands in `~/.config/omarchy/plugins/io.github.fieldnote-ops.harnessbar/`
and appears in the right section of the bar. Move it elsewhere with:

```sh
omarchy bar move io.github.fieldnote-ops.harnessbar --after omarchy.agents
```

> Plugins run as unsandboxed code inside `omarchy-shell`. Read the source
> before enabling; adding a plugin never executes an install hook.

## First run

Click the bar glyph. The panel starts in **service not installed** state:

1. **Install service** — writes `~/.config/systemd/user/dsh-web.service` from
   the shipped template and runs `systemctl --user daemon-reload` (no sudo).
   After changing `startOnLogin`, use **Re-apply unit** on the same row.
2. **Start** — starts `dsh web`, captures its tokenized URL into a private
   runtime file, and reports the health.
3. **Open UI** — opens the web UI in an Omarchy web-app window (or the default
   browser, per the `openMode` setting).

Equivalent from a terminal:

```sh
HB=~/.config/omarchy/plugins/io.github.fieldnote-ops.harnessbar/bin/harnessbar
"$HB" setup-service
"$HB" start
"$HB" status
```

## Settings

Settings live inline in `~/.config/omarchy/shell.json`, in this widget's entry.
The panel's **Settings → Edit** form writes non-secret values through
`omarchy bar set` and writes the proxy into `shell.json` through an
owner-only staging file (`jq --rawfile`), so a proxy containing
`user:password` never appears in a process argument. The CLI remains the
source of truth and works the same way. Port and proxy
changes need a **Restart**; `startOnLogin` is applied when the settings are
saved (or with **Re-apply unit**).

The proxy is **direct by default** (empty). Set it only when your network needs
a local proxy; the example below uses a generic port. A proxy URL containing
credentials is stored in plaintext in `shell.json` (and therefore readable by
your user account and local tools) — avoid it on shared machines. The panel
passes it over stdin and the helper stages it in a 0600 file before writing;
dsh update commands receive it through environment variables, not argv.

| Key | Type | Default | Meaning |
|---|---|---|---|
| `port` | integer | `3080` | `dsh web` listener port; `0` lets the OS pick one |
| `proxy` | string | `""` | Optional HTTP(S) proxy for the service and update checks, e.g. `http://127.0.0.1:8080` |
| `dshPath` | path | `""` | Optional absolute path to `dsh`; empty auto-detects mise, `PATH`, and `~/.local/bin` |
| `openMode` | enum | `Webapp` | `Webapp` uses `omarchy-launch-or-focus-webapp`; `Browser` uses `xdg-open` |
| `startOnLogin` | enum | `Off` | Saved from the panel or CLI; applied immediately when saved (`On` runs `systemctl --user enable`), or by **Re-apply unit** |
| `refreshSec` | integer | `5` | Status polling interval |
| `glyph` | string | *(logo)* | Optional text label override for the bar; empty shows the DeepSeek logo, `DS` gives a plain label |

```sh
omarchy bar set io.github.fieldnote-ops.harnessbar proxy http://127.0.0.1:8080
omarchy bar set io.github.fieldnote-ops.harnessbar port 3080 --json
omarchy bar set io.github.fieldnote-ops.harnessbar startOnLogin On
```

## Usage

| Action | Effect |
|---|---|
| Left click | Open/close the panel |
| Right click | Start if needed, then open the web UI |
| Middle click | Refresh status |
| `o` / `c` / `s` / `r` / `g` / `u` | Open UI / copy URL / start-stop / restart / logs / check updates |
| `Esc` | Close the panel |

Destructive actions (stop, restart, update, adopt service, remove service) ask
for confirmation first. **Stop** is only offered for a unit this plugin manages;
repair a legacy unit first. Copy URL copies a **credential**: the printed URL contains a per-process
launch token.

Shell IPC is available for keybindings and scripts:

```sh
omarchy-shell shell call io.github.fieldnote-ops.harnessbar toggle ''
omarchy-shell shell call io.github.fieldnote-ops.harnessbar refresh ''
```

The bundled helper CLI exposes the same operations plus logs, update checks, and
service setup; run `bin/harnessbar help` for the list.

## Service and files

| Path | Purpose |
|---|---|
| `~/.config/systemd/user/dsh-web.service` | harnessbar-managed unit (safe to inspect; removed by **Remove service**) |
| `$XDG_RUNTIME_DIR/harnessbar/url` | Owner-only launch URL (mode 600), deleted when the service stops |
| `journalctl --user -u dsh-web.service` | Service logs; tokens are redacted in what the panel shows |
| `~/.dsh/` | DeepSeek Harness data (sessions, settings, credentials); **never touched** by this plugin |

The unit name is intentionally `dsh-web.service` so an older local helper setup
is detected and can be repaired instead of duplicated.

## Security notes

- The plugin runs unsandboxed inside `omarchy-shell`, like every Omarchy plugin.
- No `sudo`, no `pkexec`, no system-wide files, no download-and-execute.
- The service is a regular systemd **user** unit; it cannot outlive your login.
- The launch URL is a credential. It is stored under `$XDG_RUNTIME_DIR` with
  mode 600, never printed into the journal, never shown in the panel, and only
  copied when you ask. Treat screenshots, clipboard history, and shared logs
  accordingly.
- **Open UI does not put the token in process arguments.** It serves a private
  login page from a one-shot loopback listener (`systemd-socket-activate` on
  `127.0.0.1:<random port>/<random path>`) and passes only that URL to the
  launcher. The page redirects to the tokenized URL, so the token never appears
  in `/proc/<pid>/cmdline` for the helper, the escaping helpers, the launcher,
  or the browser; it does of course appear in the browser's own address
  bar/history while the page is open.
- **The handoff page is attributed to your user.** Its URL is a credential:
  whatever can fetch it receives the launch token. Because the launcher gets
  that URL through argv (readable by other local users), the listener reverses
  its own connection's TCP four-tuple with `ss -tnpe` and serves only when the
  caller's socket matches it exactly and belongs to your uid; a missing or
  ambiguous match gets `403` without consuming the page. A same-uid process
  could still fetch it, but such a process can already read the 0600 URL file.
  Attribution happens **before** any request byte is read, the reads are capped
  (4 KiB request line, 64 headers, 16 KiB total, 10 s), and only 8 accepted
  workers may exist at once (`503` beyond that), because the listener has no
  cap of its own.
- **Why a listener instead of a `file://` page:** `dsh web` mints its session
  cookie with `SameSite=Strict`. Chromium does not send that cookie on the
  redirect that follows a navigation started from a `file://` document, so a
  local-file handoff lands on dsh's `401` page. Serving the page from
  `127.0.0.1` keeps the navigation same-site (the port does not matter) and the
  cookie is accepted. The listener answers one request for its random path,
  returns `404` to anything else, and is stopped immediately afterwards (or
  after ~20 s if the browser never asks).
- **Upgrading from 0.2.1 or earlier:** a browser window launched by the old
  plugin may still carry the old launch token in its process arguments until
  that browser process exits. Close the DeepSeek Harness window/browser once
  and reopen it from the panel; restarting `dsh-web.service` also rotates the
  old token. New opens always use the private loopback login page.
- The update action uses your existing mise/npm installation; nothing is
  downloaded silently. It only installs a strictly newer published version and
  refuses to downgrade a `next` build to the older `latest` tag.
- Omarchy's automated marketplace baseline reports the capabilities this plugin
  deliberately uses: `service-management` (systemd user unit) and
  `package-manager` (mise/npm update action), plus `privilege` from clearly
  negated documentation and `remote-build` from the development clone shown
  below. They are described here for review rather than hidden.

## Removal

1. Panel → **Remove service** (stops/disables the unit and deletes it; `~/.dsh`
   data stays untouched), or:
   ```sh
   ~/.config/omarchy/plugins/io.github.fieldnote-ops.harnessbar/bin/harnessbar remove-service
   ```
2. Remove the plugin:
   ```sh
   omarchy plugin remove io.github.fieldnote-ops.harnessbar --yes
   ```
3. If you migrated from an older local setup, delete the leftover
   `~/.local/bin/dsh-web` and `~/.local/bin/dsh-web-run` helpers at your
   convenience; harnessbar does not delete files outside its own unit.

## Troubleshooting

- **`dsh not found`** — install `dsh` or set `dshPath`.
- **Service fails / panel shows error** — open **Logs**, or run
  `journalctl --user -u dsh-web.service -n 100`.
- **Model calls fail behind a proxy** — set `proxy` and restart the service.
- **Port already in use** — set another `port` (or `0`) and restart.
- **Legacy service detected** — panel → **Repair service** rewrites the unit to
  the plugin-managed one; restart afterwards to apply.

More detail in [docs/troubleshooting.md](docs/troubleshooting.md) and
[docs/architecture.md](docs/architecture.md).

## Development

```sh
git clone https://github.com/fieldnote-ops/harnessbar.git
cd harnessbar
bash tools/preflight.sh      # manifest + tests + QML checks
git config core.hooksPath .githooks   # optional pre-push preflight
```

The tests stub `systemctl`, `dsh`, `npm`, `mise`, `journalctl`, and the launch
helpers, so they run on any machine without starting a real service. QML is
checked with `qmllint`; CI requires the tool and runs the same gates on Ubuntu.

## Compatibility

Tested live on Omarchy 4.0.6 (Quattro) with `@deepseek-ai/dsh` 0.2.1-rc.2 on
2026-10-20: non-zero bar slot, panel open/close, live status, legacy-unit
detection and one in-place service repair. Lifecycle actions are covered by
stubbed-systemd tests; restarting the service that hosts an open GUI was not
exercised in development. The plugin relies on the documented `dsh web` startup contract: the
`dsh web:` line is the readiness signal, the printed URL carries a per-process
token, and `--port 0` selects a free port. Newer DSH versions keep working as
long as that line is printed; otherwise the panel reports a clear error instead
of guessing.

## License

MIT — see [LICENSE](LICENSE). © 2026 FIELD NOTE.

[![](https://img.shields.io/badge/powered_by-dsh-4D6BFE?style=flat-square&logo=deepseek&logoColor=white)](https://github.com/deepseek-ai/deepseek-harness)
