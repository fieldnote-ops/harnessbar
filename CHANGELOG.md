# Changelog

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
