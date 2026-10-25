# Changelog

## 0.3.4 — 2026-10-25

Fix the update check, which could silently downgrade a newer dsh.

- `update --check` compared the `latest` dist-tag against the installed version
  with a plain string inequality. dsh publishes newer release candidates under
  `next` (`latest` = `0.2.1-rc.2`, `next` = `0.2.1-rc.3`), so an installed
  `0.2.1-rc.3` was reported as updatable and the update action installed
  `0.2.1-rc.2`, downgrading it and then reporting success.
- The check now reads `npm view @deepseek-ai/dsh dist-tags --json` and picks the
  newest tag the install may follow: prerelease installs consider all tags
  (so `0.2.1-rc.3` is found on `next`), stable installs only `latest`.
- Versions are compared with semver precedence (numeric prerelease identifiers,
  prerelease below release, build metadata ignored) instead of `!=`.
- `updatable` is true only for a strictly newer target, `update` refuses to
  install an older one (`refusing to downgrade`), and an already-current install
  reports `already up to date` without invoking mise/npm.
- The check JSON adds `channel`; the panel shows it for non-`latest` targets,
  e.g. `dsh 0.2.1-rc.2 → 0.2.1-rc.3 (mise, next)`.
- Tests cover prerelease tag selection, `rc.10 > rc.9`, no-downgrade on apply,
  stable-only tracking, and the no-op apply path.


## 0.3.3 — 2026-10-25

Fix `Open UI` landing on `dsh web`'s "dsh web authentication required" page.

- Root cause: `dsh web` mints its session cookie with `SameSite=Strict`, and
  Chromium does not send that cookie on the redirect that follows a navigation
  started from a `file://` document. The 0.2.2 redirect page therefore always
  ended on dsh's 401, and the browser kept showing it.
- `Open UI` now stages the login page behind a one-shot
  `systemd-socket-activate` listener on `127.0.0.1:<random port>/<random path>`
  and hands the launcher only that URL. The navigation is same-site (ports are
  ignored), so the token exchange and its cookie work, while the token still
  never appears in any process argument.
- The listener answers the exact random path once with the redirect page, sends
  `404` to anything else, and stops right after serving; the staged page is
  removed and any listener left waiting is stopped after ~20 s.
- `Content-Length` is measured in bytes, so the page's multibyte ellipsis no
  longer truncates the response.
- New runtime requirement: `systemd-socket-activate` (ships with systemd) serves
  the staged page; the README requirements table lists it.
- Tests cover the served response, the wrong-path `404`, the single-shot
  shutdown, the TTL cleanup, and the byte-accurate length; docs replace the
  `file://` handoff description and document the 401 symptom.


## 0.3.2 — 2026-10-21

Fix the panel's proxy stdin path found in marketplace review:

- Quickshell `Process.write()` requires `stdinEnabled: true`; the action process
  now enables it, so the proxy reaches the helper instead of the helper seeing
  EOF.
- Even an empty proxy (the explicit "clear" action) is written as a newline,
  and the helper rejects zero-byte stdin instead of silently treating it as
  direct. Failed delivery no longer clears a configured proxy.
- Static checks cover `stdinEnabled`; helper tests cover empty-line clear and
  zero-byte rejection.


## 0.3.1 — 2026-10-21

Marketplace-review hardening for proxy credentials.

- The panel now passes the proxy to the helper over stdin; the helper stages it
  in an owner-only runtime file and updates `shell.json` through `jq --rawfile`.
  The proxy URL (which may contain user:password) no longer appears in any
  process argument.
- dsh update commands receive the proxy through environment variables on the
  child process instead of `env NAME=VALUE ...` arguments, so the proxy cannot
  be recovered from readable procfs command lines.
- Non-secret settings (port, dshPath, startOnLogin) still go through
  `omarchy bar set`; startOnLogin is applied to the managed unit on save.
- Tests assert the proxy is absent from the omarchy and jq argv, and that it
  lands in shell.json; docs explain the stdin path.


## 0.3.0 — 2026-10-21

Settings and onboarding release. Scope stays "local dsh web service"; TUI,
agents usage, remote/mobile, and multi-instance are explicitly out.

- **Panel settings editor**: edit Proxy, Port, dshPath, and Start on login
  inline; values are saved through `omarchy bar set`, including validation
  (port range, http(s) proxy, absolute dshPath). Port/proxy apply after
  Restart; start-on-login is applied to the managed unit immediately.
- **Missing-dsh guidance**: when dsh is not installed, the panel shows the
  mise/npm install commands with Copy buttons. It never installs DSH itself.
- **Update visibility**: the panel checks for dsh updates quietly when opened
  (throttled to once per 15 minutes) and the bar tooltip reports an available
  update. Updating still requires explicit confirmation.
- **Proxy UX**: default stays empty (direct); docs/examples now use a generic
  `http://127.0.0.1:8080`; the panel shows a sanitized "direct"/"proxy host"
  summary and validates the URL before saving.
- **Cleaner service row**: "Apply settings" is now "Re-apply unit", matching
  what it actually does.
- Tests: 102 helper assertions (including settings/copy commands); QML static
  checks cover the new panel controls.

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
