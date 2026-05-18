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
- Offers menu bar controls for sound, Quiet Hours, widget position, animation, appearance, reduce motion, launch at login, muted projects, test notification, and iTerm2 connection testing.
- Installs and maintains the bundled hook reporter automatically on launch.

## Requirements

- macOS 14 Sonoma or later
- iTerm2
- Claude Code and/or Codex CLI
- Xcode 15.4 or later only if you want to build from source

## Install And First Run

1. Install a built `ClaudeAlertBot.app`, or build it locally from this repository.
2. Move the app to `/Applications` if you want a normal app-style install.
3. Launch the app.

If macOS blocks the unsigned app on first launch, use `System Settings > Privacy & Security > Open Anyway`.
As a fallback, clear quarantine manually:

```bash
xattr -cr /Applications/ClaudeAlertBot.app
```

Claude Alert Bot runs as an accessory app, so you control it from the bell icon in the macOS menu bar.

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

After launch, open the bell menu and run `iTerm2 Connection > Test iTerm2 connection`.
macOS may ask for:

- Automation permission, so the app can control iTerm2
- Accessibility permission, so the app can reliably raise the exact iTerm2 window across Spaces

## Daily Use

1. Keep Claude Alert Bot running in the menu bar.
2. Run Claude Code or Codex inside iTerm2.
3. When a session qualifies for notification, the floating widget appears with a pending count badge.
4. Hover the widget to open the session list popover.
5. Activate a row to jump back to the exact terminal session.
6. Right-click a row to pin it or mute that project for 1 hour.

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
When the finished iTerm2 session is already the current frontmost session, the app skips the completion alert.

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

## Build From Source

Generate the Xcode project, build the app, and open the exported bundle:

```bash
xcodegen generate
scripts/build.sh
open build/export/ClaudeAlertBot.app
```

The release-style build output is:

```text
build/export/ClaudeAlertBot.app
```

Run the test suite with:

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
- If the connection test passes but row clicks still cannot raise the exact window, follow the Accessibility recovery steps below.
- Make sure iTerm2 is already running.

### Clicking A Row Activates The Wrong Session

This happens on multi-display setups, or when several iTerm2 windows are open at once, and the clicked row brings up a different session than expected. Almost always it means Accessibility permission is not in effect. Without it, the app falls back to a plain app-level activation and macOS picks whichever iTerm2 window it prefers — typically the one on the screen under the mouse cursor.

It shows up most often with self-built copies. Ad-hoc signing (the local-only signature used when there is no Developer ID certificate) changes the binary fingerprint (cdhash) on every rebuild, so macOS does not carry the previously-granted permission over to the new build.

Recovery steps:

1. Quit the running app.
   ```bash
   pkill -x ClaudeAlertBot
   ```
2. Clear the previous Accessibility registration.
   ```bash
   tccutil reset Accessibility com.claudealert.bot
   ```
3. Open the freshly built app.
   ```bash
   open build/export/ClaudeAlertBot.app
   ```
4. Open the bell menu and click `Grant Accessibility…`.
5. In `System Settings > Privacy & Security > Accessibility`, turn on the `ClaudeAlertBot` toggle.
6. Quit and relaunch the app. Trust state is captured at process startup.
7. Check the log.

After `tccutil reset`, the app may not appear in System Settings immediately. Click `Grant Accessibility…` from the app menu to create the new entry, then turn on the toggle.

If you create a new ad-hoc build with `scripts/build.sh`, macOS may treat it as a new binary and the permission can become stale again. Repeat the same recovery steps if the symptom returns.

To confirm the permission is actually applied, check the log:

```bash
/usr/bin/log show --predicate 'subsystem == "com.claudealert.bot.hook"' --info --last 5m
```

Healthy logs include:

- `[ax-raised ... code=0]`
- `[jumped session=...]`
- When needed, `[ax-match path=focused-main-fallback ...]`

Problem logs include:

- `[ax-trust trusted=false ...]`
- `[ax-skip reason=not-trusted]`
- `[activate-fallback]`

If those remain, a stale registration from a previous build is probably still in the way. Start again from recovery step 1.

### Hook Repair

If you want to reapply the reporter script and hook configuration manually during development:

```bash
scripts/dev-install-hook.sh --apply
```

### Unsigned App Warning

If `Open Anyway` is not enough, clear quarantine:

```bash
xattr -cr /Applications/ClaudeAlertBot.app
```

## Current Scope

- iTerm2 only
- macOS 14+
- Unsigned / ad-hoc signed distribution
- No external Swift dependencies

## License

MIT. See [LICENSE](LICENSE).
