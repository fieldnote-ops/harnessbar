# Architecture

harnessbar is a thin QML UI over one self-contained shell helper and a systemd
user service. There is no daemon of its own and no long-running state outside
systemd.

```text
┌─────────────────────────┐
│ BarWidget.qml           │  polls status, owns actions, routes IPC
│   └── Panel.qml         │  renders status/logs/updates, asks to confirm
└───────────┬─────────────┘
            │ Process: bin/harnessbar <command>
            ▼
┌─────────────────────────┐
│ bin/harnessbar          │  status/start/stop/restart/open/copy-url/logs/
│                         │  setup-service/remove-service/update/run
└───────────┬─────────────┘
            │ systemctl --user
            ▼
┌─────────────────────────┐
│ dsh-web.service         │  generated from systemd/*.template
│ ExecStart=… bin/harnessbar run
└───────────┬─────────────┘
            ▼
       dsh web --no-open --host 127.0.0.1 --port <setting>
```

## Components

### BarWidget.qml

- Resolves its own plugin directory from `Qt.resolvedUrl(".")` so the helper is
  always the copy next to the QML file (no `~/.local/bin` dependency).
- Polls `bin/harnessbar status` every `refreshSec` seconds and republishes the
  parsed JSON to the panel as `host.status`.
- Owns all side effects: start/stop/restart, open, copy URL, service setup,
  logs, update check/apply. The panel only calls these functions.
- Registers the plugin's IPC target. `open`, `close`, `toggle`, `refresh`,
  `start`, `stop`, `restart`, `openUi`, and `logs` are available through
  `omarchy-shell shell call io.github.fieldnote-ops.harnessbar <method>`.
- Busy state is time-bounded (90 s); failures always surface as panel text.

### Panel.qml

- Extends the Omarchy `Panel` base and hosts a `KeyboardPanel` with a
  `PanelKeyCatcher` for shortcuts and Escape handling.
- Displays only `host:port`, never the tokenized URL.
- Destructive actions go through an inline confirmation state, not a direct
  click. The panel is a view; it cannot mutate the service on its own.

### bin/harnessbar

A single bash entry point used by both the UI and systemd:

| Group | Commands |
|---|---|
| Status | `status` (JSON), `version`, `url` |
| Lifecycle | `start`, `stop`, `restart`, `toggle`, `run` |
| UI | `open`, `copy-url` |
| Diagnosis | `logs [lines]` |
| Service | `setup-service [--replace-legacy|--force]`, `remove-service` |
| Maintenance | `update`, `update --check` |

Settings are read from `~/.config/omarchy/shell.json` with `jq`, walking the
document for an object whose `id` equals this plugin's id. That keeps the plugin
compatible with `omarchy bar set` and with hand-edited config. The service
reads settings when it starts, so changing port/proxy needs a restart, not a
unit rewrite.

`run` is the service entry point:

1. Creates `$RUNTIME_DIRECTORY` (or `$XDG_RUNTIME_DIR/harnessbar`) with mode 700.
2. Resolves `dsh` (setting → `DSH_BIN` → mise shims → `mise which` → `PATH`).
3. Applies the optional proxy environment.
4. Executes `dsh web --no-open --host 127.0.0.1 --port <setting>` and streams
   its output to journald.
5. Watches for the documented `dsh web: http://…?token=…` readiness line,
   stores the URL in `url` (mode 600), and replaces the line in the journal with
   `dsh web: listening on host:port (launch token captured and hidden)`.
6. Removes the URL file on exit.

No PID file is written; systemd owns the process lifecycle, and the listener
port is the source of truth for the UI.

### systemd/dsh-web.service.template

Rendered by `setup-service` with the plugin's absolute root path:

- `Type=simple`, `Restart=on-failure`, `RestartSec=2`, `TimeoutStopSec=20`
- `RuntimeDirectory=harnessbar` (mode 0700, removed when the unit stops)
- `Environment=PATH=…mise/shims:…/.local/bin:/usr/local/bin:/usr/bin:/bin`
- `[Install] WantedBy=default.target`, enabled only when `startOnLogin=On`

The unit lives at `~/.config/systemd/user/dsh-web.service` and carries a
`Managed by harnessbar` marker. `remove-service` refuses to delete any unit
without that marker; `setup-service` backs up unmanaged files before replacing
them (`--replace-legacy` or `--force`).

## State machine (status JSON)

| State | Meaning | Bar |
|---|---|---|
| `running` | Unit active, URL present, port accepting | accent |
| `starting` | Unit active/activating, no URL yet | dim accent |
| `degraded` | Unit active, URL present, port not accepting | accent + error text |
| `stopped` | Unit inactive | dim |
| `no-service` | No unit installed | dim + setup hint |
| `legacy` | flag: unmanaged `dsh-web.service` from an older helper | dim + repair hint |
| `stale` | URL exists but service is inactive | dim + error text |
| `error` | Unit failed | urgent |
| `no-dsh` | `dsh` not found | urgent + install hint |

`supervised` is true when the systemd user manager is reachable and the unit is
active. When systemd is unavailable (restricted shell, test environment), the
helper falls back to the runtime URL plus listener probe and reports
`supervised: false`.

## Security boundaries

- No privileged operations: no `sudo`, no `pkexec`, no system files.
- No remote code execution: no `curl | sh`; the update path only calls the
  user's existing mise/npm with an explicit version.
- Update target: `update --check` reads `npm view … dist-tags` and picks the
  newest tag an installed version may follow (prerelease installs consider all
  tags, stable installs only `latest`), then compares versions with semver
  precedence. Only a strictly newer target is offered or installed, so a `next`
  build is never replaced by an older `latest`.
- Credential handling: the launch token never reaches the journal, the panel,
  the README screenshots, or any process argument. `open` stages a private
  login page (mode 600 in a 700 runtime directory) and serves it from a
  one-shot `systemd-socket-activate` listener on
  `127.0.0.1:<random port>/<random path>`, handing the launcher only that URL.
  The page redirects to the tokenized URL and is removed once served, or after
  a short TTL. Serving it from `127.0.0.1` rather than a `file://` page is
  required: `dsh web` mints a `SameSite=Strict` cookie, which Chromium does not
  send on the redirect following a navigation started from a local file, so a
  file handoff ends on dsh's 401 page. It is only copied on explicit request.
- Process control: no `/tmp` PID files and no signal delivery from untrusted
  state. `stop` goes through systemd.
- The plugin runs unsandboxed inside the shell, like every Omarchy plugin; the
  README tells users to review the source before enabling.
- Proxy values may contain credentials and are stored plaintext in
  `shell.json` (the README calls this out), but they are kept out of process
  arguments: stdin + owner-only staging + `jq --rawfile` on save, and
  environment assignments (no `env NAME=VALUE` argv) for dsh update commands.

## Compatibility constraints

- Omarchy shell plugin contract: `schemaVersion: 1`, `bar-widget` entry point,
  id outside `omarchy.*`, no symlinks, settings inline in `shell.json`.
- Qt 6.12 `Color` collision: palette access uses the aliased
  `qs.Commons as Commons` import (`Commons.Color.*`).
- DSH contract: `dsh web` prints a readiness line containing the tokenized URL;
  `--port 0` is supported. If that line disappears in a future DSH release, the
  panel reports `starting`/error rather than fabricating a URL.

## Repository layout

```text
manifest.json                 plugin manifest and settings schema
BarWidget.qml                 bar entry point, polling, actions, IPC
Panel.qml                     popup UI
bin/harnessbar                CLI and service entry point
systemd/dsh-web.service.template
tools/validate.sh             manifest/layout validation (CI gate)
tools/preflight.sh            local push gate
tests/                        manifest, QML, and helper suites (stubbed)
docs/                         this file + troubleshooting
.github/workflows/validate.yml
```
