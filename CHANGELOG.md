# Changelog

## 0.2.3 — 2026-10-21

Follow-up to marketplace review feedback on the Open UI handoff.

- The HTML/JS escaping subprocesses (`jq`) now receive the tokenized URL on
  **stdin**, not through `--arg`, so the launch token never appears in any
  child process argument. The private redirect page is unchanged.
- Metadata escaping now emits the actual attribute/string values (raw HTML
  escaping and a JSON-quoted JS string) instead of jq's quoted string output.
- Tests add a jq-wrapper assertion that the escaping subprocess argv is
  token-free (85 helper assertions).

## 0.2.2 — 2026-10-21

Security hardening for the Open UI handoff after marketplace review.

- **The launch token never appears in process arguments.** `Open UI` now writes
  a private, owner-only `file://` redirect page under `$XDG_RUNTIME_DIR` and
  hands the web-app/browser launcher only that file path. The page redirects to
  the tokenized URL, so `/proc/<pid>/cmdline` contains no credential. The page
  is removed after about 20 seconds, and stale pages are swept on the next open.
- Meta-refresh and script URLs are escaped with `jq` so reserved characters in
  the launch URL stay inert; URLs with unsupported characters are refused
  instead of being passed as arguments.
- `xdg-open`/browser mode uses the same private redirect page.
- Tests cover token-free launcher argv, page permissions, redirect content,
  reserved-character escaping, and page cleanup (82 helper assertions).
- Upgrade note: a browser window launched by 0.2.1 or earlier may keep the old
  token in its argv until that browser process exits; close and reopen it (or
  restart `dsh-web.service` to rotate the token).

## 0.2.1 — 2026-10-20

Hardening release after an independent review; no behaviour changes for the
happy path.

- `stop` / `remove-service` now refuse to act on units harnessbar does not
  manage, and `remove-service` aborts if the service cannot be stopped instead
  of silently deleting the unit.
- Unit replacement refuses to proceed when the existing unit cannot be backed
  up; backups use unique names; unit rendering no longer treats `&` in the
  plugin path as a pattern.
- Legacy detection accepts both old `dsh-web` and `dsh-web-run` helpers.
- Launch-token capture uses a private umask, verifies the write, and says so
  when the URL could not be stored; wider log redaction covers JSON `token`
  fields, Authorization/Bearer headers, URL userinfo, and the proxy log line.
- Panel: Start/Stop follows the actual unit state (including `starting`),
  Adopt goes through confirmation, **Apply settings** re-applies the unit and
  `startOnLogin`, update state resets after an update, journal text is plain
  text, and Check updates remains available when no update exists.
- Bar icon dims while stopped; command timeouts no longer reassign a running
  process; refresh interval handles invalid settings.
- Settings/readability: stricter port validation, clearer systemd-unavailable
  error, `~/.local/bin/dsh` auto-detection, and documentation corrections
  (`jq` dependency, capability wording, live-test scope).
- Tests: 69 helper assertions, failure-path and `&`-path coverage; CI requires
  `qmllint`; validation checks the official `defaultSection` set and the preview.

## 0.2.0 — 2026-10-20

First public release of **harnessbar**, a service-grade Omarchy bar widget for
the local DeepSeek Harness web UI.

- Bar widget: live status (running / starting / stopped / degraded / error),
  version in the tooltip, left click opens the panel, right click opens the UI,
  middle click refreshes.
- Panel: status, version, host:port, Open UI, Copy token URL, Start/Stop,
  Restart, Logs, service Install/Repair/Remove, update check/apply, error
  banner, inline confirmations, and keyboard shortcuts.
- Background service: installs a systemd **user** unit
  (`~/.config/systemd/user/dsh-web.service`) on explicit request, with
  `Restart=on-failure`, login-start option, and journald logging.
- Settings: `port`, `proxy`, `dshPath`, `openMode`, `startOnLogin`,
  `refreshSec`, `glyph`, all stored inline in `~/.config/omarchy/shell.json`
  and compatible with `omarchy bar set`.
- Update management: detects mise vs npm installations, shows installed/latest
  versions, updates on request, and restarts the service.
- Legacy migration: detects the older `~/.local/bin/dsh-web-run` unit and
  repairs it in place (`setup-service --replace-legacy`).
- Security: no sudo/pkexec, no download-and-execute, no shared `/tmp` PID
  state, owner-only runtime URL file, launch token redacted from journald and
  never shown in the panel.
- Documentation and quality: README (English + 简体中文), architecture and
  troubleshooting notes, manifest/QML/shell validation, stubbed test suite,
  preflight script, git pre-push hook, and GitHub Actions validation.
