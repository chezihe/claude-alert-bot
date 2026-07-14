# Claude Alert Bot

[한국어](README.ko.md)

Claude Alert Bot is a native macOS utility for Claude Code and Codex users who work in iTerm2.
When a long-running session finishes, or when the agent pauses waiting for you, the app shows a floating widget on your desktop and lets you jump back to the exact iTerm2 tab or window that produced the event.

The main idea is simple: if the alert cannot take you back to the right terminal, it is not useful.
Claude Alert Bot is built around session-accurate jump-back rather than short-lived system banners.

## Screenshots

![Claude Alert Bot overview](docs/images/claude-alert-bot-overview.png)

![Claude Alert Bot menu controls](docs/images/claude-alert-bot-menu.png)

## What It Does

- Shows a floating Claude widget when a qualifying session completes or waits for input.
- Keeps a pending session queue until you clear it or jump back to the terminal.
- Jumps to the exact iTerm2 session for a row when you activate it.
- Filters noisy short runs with a configurable notification threshold.
- Supports waiting-input alerts from Claude notification hooks for permission prompts and elicitation dialogs.
- Lets you pin important rows, mute a project for 1 hour, or clear unpinned rows.
- Groups repeated alerts from the same project and shows a compact count badge.
- Can show a one-line Last Output preview of the latest captured assistant message or output under each Claude Code or Codex row when enabled from `Notification > Alert Details > Last Output`.
- Offers menu bar controls for sound, Quiet Hours, notification threshold, alert details, widget position, animation, appearance, reduce motion, launch at login, muted projects, test notification, and iTerm2 connection testing.
- Installs and maintains the bundled hook reporter automatically on launch.

## Requirements

- macOS 14 Sonoma or later
- iTerm2
- Claude Code and/or Codex CLI
- Xcode 15.4 or later only if you want to build from source
- XcodeGen only if you want to build from source

## Quick Start

Set up a personal local signature first so repeated source builds keep the same macOS permission identity. No Apple account is required.

```bash
scripts/setup-local-signing.sh
xcodegen generate
scripts/build.sh
open build/export/ClaudeAlertBot.app
```

The build output is `build/export/ClaudeAlertBot.app`. Move it to `/Applications` if you prefer a normal installed-app workflow.

### First Permission Grant

The app is controlled from its bell icon in the menu bar. Configure permissions in this order after the first launch.

1. Run `iTerm2 Connection > Test iTerm2 connection` from the bell menu and allow Automation access.
2. Click `Grant Accessibility…`.
3. Enable `ClaudeAlertBot` in `System Settings > Privacy & Security > Accessibility`.
4. Quit and relaunch the app once.

Later rebuilds reuse the same permission while the bundle identifier and local certificate remain unchanged. See [Local Signing And Accessibility Permission](docs/local-signing.md) for identity management, ad-hoc builds, and recovery steps.

On launch, the app copies the bundled reporter script to:

```text
~/Library/Application Support/ClaudeAlertBot/cab-report.sh
```

It then merges hook registrations into:

- `~/.claude/settings.json`
- `~/.codex/hooks.json` and `~/.codex/config.toml` if `~/.codex` exists

The installed hook setup covers:

- `Stop` and `UserPromptSubmit` for Claude Code
- `Stop` and `UserPromptSubmit` for Codex when `~/.codex` exists
- `Notification` for Claude permission prompts / elicitation dialogs

## Daily Use

1. Keep Claude Alert Bot running in the menu bar.
2. Run Claude Code or Codex inside iTerm2.
3. When a session qualifies for notification, the floating widget appears with a pending count badge.
4. Hover the widget to open the session list popover.
5. Activate a row to jump back to the exact terminal session.
6. Right-click a row to pin it or mute that project for 1 hour.

If you want more context in the popover, open the bell menu and choose `Notification > Alert Details > Last Output`.
Rows will show the first non-empty line of the latest captured assistant message or output when one is available.

## Feature Overview

### Persistent Queue

Claude Alert Bot keeps alerts visible until you act on them.
That makes it useful for long-running agent work where a standard banner would disappear before you return.

### Threshold Filtering

You can choose how long a run must take before it produces an alert.
Short, noisy runs can be suppressed without losing session accuracy for meaningful completions.
Failed runs still produce alerts even when they are shorter than the threshold.
If a stop event has a non-zero exit code, Claude Alert Bot treats it as a failed run.
Waiting-input alerts appear immediately.

### Row Indicators

The status dot shows the alert type: green for success, red for error, and yellow for waiting input.
Rows normally show the completed run time.
If the app cannot determine the run time, the time indicator is shown as `?`.
When `Last Output` is enabled, Claude Code and Codex rows can show one secondary preview line.
Blank output is ignored, multiline output uses the first non-empty line, and long text is truncated to fit the row.

### Quiet Hours

Quiet Hours suppresses sound and animated alert emphasis while still keeping the queue and count badge active.
You can leave the app running without losing pending sessions.

### Queue Controls

Rows can be pinned so they survive bulk clear actions.
Projects can be muted for 1 hour.
Repeated alerts from the same project are grouped to keep the popover compact.

### iTerm2 Jump Reliability

The app tracks the iTerm2 session identity carried by the hook event and uses AppleScript plus window raising to return you to the right place.
There is also a built-in connection test in the menu bar for diagnosing permission or reachability issues.

## Development And Testing

Follow [Quick Start](#quick-start) for the build and first launch. Identity status checks, one-off ad-hoc builds, certificate removal, and permission recovery are documented separately in [Local Signing And Accessibility Permission](docs/local-signing.md).

Run the full test suite with:

```bash
xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'
```

## Troubleshooting

### No Alerts Appear

- Make sure Claude Alert Bot is running.
- Make sure your agent session is running in iTerm2.
- Check that hooks were merged into `~/.claude/settings.json` or `~/.codex/hooks.json`.
- Lower the notification threshold from the menu bar if your sessions are too short to qualify.

### Clicking A Row Does Not Jump

- Run `iTerm2 Connection > Test iTerm2 connection` from the bell menu.
- If that test fails, treat it as an Automation/iTerm2 connection issue. Grant Automation permission if macOS asks, and reset AppleEvents only when the connection test needs to be initialized again.
  ```bash
  tccutil reset AppleEvents com.claudealert.bot
  ```
- If the connection test passes but row clicks still cannot raise the exact window, see [Recover Accessibility Permission](docs/local-signing.md#recover-accessibility-permission).
- Make sure iTerm2 is already running.

### Clicking A Row Activates The Wrong Session

This happens on multi-display setups, or when several iTerm2 windows are open at once, and the clicked row brings up a different session than expected. Almost always it means Accessibility permission is not in effect. Without it, the app falls back to a plain app-level activation and macOS picks whichever iTerm2 window it prefers — typically the one on the screen under the mouse cursor.

Start with `scripts/build.sh --signing-status`. For `mode=local`, quit the old process and reopen the new build before resetting TCC. For ad-hoc builds or a permission state that remains stale, follow the status-based recovery and logging steps in [Local Signing And Accessibility Permission](docs/local-signing.md#recover-accessibility-permission).

### Hook Repair

If you want to reapply the reporter script and hook configuration manually during development:

```bash
scripts/dev-install-hook.sh --apply
```

### If macOS Blocks The App

For an externally downloaded app blocked by Gatekeeper, see [If macOS Blocks The App](docs/local-signing.md#if-macos-blocks-the-app). Locally built copies normally do not need quarantine removal.

## Current Scope

- iTerm2 only
- macOS 14+
- Local self-signed or ad-hoc source builds without Developer ID notarization
- No external Swift dependencies

## License

MIT. See [LICENSE](LICENSE).
