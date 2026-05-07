# Project Research Summary

**Project:** Claude Alert Bot
**Domain:** macOS native floating-notification companion app for Claude Code (Swift/SwiftUI, iTerm2-targeted, hook-driven, unsigned `.dmg` distribution)
**Researched:** 2026-05-07
**Confidence:** HIGH on technical stack, architecture, and pitfalls; MEDIUM on unsigned-distribution UX (Apple keeps tightening) and on session→tab mapping reliability under exotic shell environments (tmux, nix-shell, containers).

## Executive Summary

Claude Alert Bot is a single-user macOS accessory app whose entire purpose is to convert a Claude Code `Stop` hook into a persistent, click-to-jump floating widget that lands the user back on the *exact* iTerm2 tab where the work happened. The genuine differentiator vs. ~7 surveyed Claude Code notifiers (wyattjoh, dazuiba/CCNotify, 777genius/claude-notifications-go, foxytanuki/ccnotify, etc.) is the combination of three properties — **floating widget that persists until clicked + counter-aggregation of concurrent completions + click-to-exact-tab via stable iTerm2 UUID**. None of the surveyed tools deliver all three, and that triple is the moat.

The recommended build is a **two-process system glued by a single AF_UNIX socket**: a thin POSIX `sh` Reporter installed as the Claude Code Stop *and* UserPromptSubmit hooks (start+stop correlation is mandatory to compute elapsed time against the 30 s threshold), and a long-running Swift app running headless (`LSUIElement=true`) with `Network.framework` `NWListener` accepting JSON events, a Swift-actor `SessionRegistry` correlating start/stop by `session_id`, an `NSPanel`-based widget (subclassed with `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded` + `.canJoinAllSpaces` + `.fullScreenAuxiliary` + `.stationary`), and an `iTermBridge` that drives compiled-once `NSAppleScript` via `unique ID of session` (UUID parsed from `ITERM_SESSION_ID`). Target macOS 14 Sonoma minimum. Distribute as ad-hoc-signed (`codesign -s -`) `.app` inside a `create-dmg`-built `.dmg` — no Apple Developer Program required.

The single highest-risk component is **session→tab mapping**. PPID-walking is broken because iTerm2's per-app server collapses panes under one parent. The robust path is multi-strategy: primary = UUID from `ITERM_SESSION_ID`, fallback = TTY captured at hook time, last-resort = friendly "session no longer exists" error rather than wrong-jump. The second-highest risk is the **distribution UX**: PROJECT.md's "right-click → Open" instruction is **outdated for macOS 15+**; the current canonical workaround is **System Settings → Privacy & Security → Open Anyway** (or `xattr -cr` for advanced users). The README must reflect this from day one. Third, **the hook MUST always `exit 0`** — `exit 2` from a Stop hook makes Claude Code loop infinitely; this architectural constraint forces the thin-shell-hook + fat-daemon split.

## Key Findings

### Recommended Stack

Pure Apple frameworks; **zero third-party Swift dependencies for MVP**. The stack maps each requirement to the simplest first-party API that meets it durably across macOS 14/15/26.

**Core technologies:**
- **Swift 5.10 / Xcode 15.4+** — application language, locked by PROJECT.md
- **SwiftUI + AppKit interop (`NSHostingView` inside `NSPanel`)** — SwiftUI's `Window` scene cannot pin above all Spaces; AppKit interop is non-negotiable for the floater
- **`Network.framework` (`NWListener` + `NWEndpoint.unix`)** — modern, no-entitlements local IPC for hook → app
- **`NSAppleScript` (compile once, execute many)** — iTerm2 control; richer than ScriptingBridge, ~10–100× faster than `Process` + `osascript`
- **`AVAudioPlayer` (AVFoundation)** — sound playback; `NSSound` has reported macOS 26 CoreAudio init regressions
- **`UNUserNotificationCenter` (optional secondary channel)** — *only* for sound delivery if Focus/DnD respect is required (UN sounds respect Focus; raw audio APIs do not)
- **`SMAppService.mainApp` (macOS 13+)** — launch-at-login, replaces deprecated `SMLoginItemSetEnabled`
- **`create-dmg` (sindresorhus, npm)** — single-command DMG packaging on Apple Silicon
- **Ad-hoc `codesign -s -`** — *required on Apple Silicon to launch at all*; free, no Developer Program needed

**Min OS:** macOS 14 Sonoma. macOS 13's `MenuBarExtra` quirks aren't worth the long-tail user gain; macOS 15 would shed too many users.

See [STACK.md](./STACK.md) for the full matrix and rejected alternatives (XPC, URL scheme, Distributed Notifications, ScriptingBridge, NSSound, Sparkle, node-appdmg).

### Expected Features

The Active requirement list in PROJECT.md is already aligned with table stakes from the comparable-tool survey. The 30 s default threshold matches zsh-notify's industry norm.

**Must have (table stakes — all locked in PROJECT.md Active):**
- Stop hook receiver, JSON-on-stdin
- Time-threshold filter (default 30 s, configurable)
- Floating Claude-icon widget via `NSPanel`, persists until clicked
- Folder name on widget (from `cwd` / `CLAUDE_PROJECT_DIR`)
- Single sound + on/off toggle
- Counter badge + click-to-expand list for concurrent completions
- Click → focus exact iTerm2 tab via UUID-tracked AppleScript
- Settings window (threshold / sound / position) via SwiftUI `Settings` scene + `@AppStorage`
- `.dmg` distribution + Gatekeeper README (with **macOS 15+ "Open Anyway" path**, not "right-click → Open")
- Hook auto-install (idempotent merge into `~/.claude/settings.json`) with manual fallback
- Automation permission first-run check + recovery dialog (`NSAppleEventsUsageDescription` + deep link to System Settings)

**Should have (recommended differentiators for v1):**
- **First-run onboarding wizard** (3 screens: install hook → grant Automation → test notification)
- **Auto-merge `~/.claude/settings.json`** rather than copy-paste guide

**Defer to v1.x (validated demand):**
- Per-project threshold override; per-project sound/tint
- Recent-completions ring buffer (≤10; *not* a stats dashboard — that's Out of Scope)
- Quiet hours / schedule (cleaner than DnD-respect, which has no public API)
- Idle-detection alternative ("only if AFK >2min")
- `Notification` hook (permission prompts) alongside `Stop`
- Sound picker

**Defer to v2+:**
- Multi-terminal (Terminal.app / Warp / Ghostty / kitty)
- Auto-update (Sparkle)
- Code signing / notarization

**Permanently excluded:** Webhook/Slack forwarding, reply-from-widget, response-body preview, mid-task progress, auto-dismiss, always-visible menu bar, snooze.

See [FEATURES.md](./FEATURES.md) for the full prioritization matrix and competitor breakdown.

### Architecture Approach

**Two-process system, single Unix-domain socket boundary.** Stateless edge (the Reporter) + stateful core (the App). The Reporter exits in milliseconds; the App owns all correlation, persistence, UI, and AppleScript dispatch.

**Major components:**
1. **Reporter (POSIX `sh`)** — captures `session_id`, `cwd`, `ITERM_SESSION_ID`, `tty`, `PPID`, `CLAUDE_PROJECT_DIR`; writes one JSON line via `nc -U`; exits. **Always `exit 0`**. Installed as both `Stop` *and* `UserPromptSubmit` hooks.
2. **HookListener (Swift `NWListener` over `AF_UNIX`)** — accepts connections, decodes `HookEvent`, hands to registry.
3. **SessionRegistry (Swift `actor`)** — single source of truth. In-flight map + completed-but-unclicked queue. Persists to `sessions.json` atomically; survives crashes; GC stale `.inFlight` after 6 h.
4. **NotificationOrchestrator** — applies threshold, ~500 ms–2 s batching window, sound dedupe.
5. **FloatingWidgetWindowController** — custom `NSPanel` subclass with the correct flags; SwiftUI hosted via `NSHostingView`.
6. **iTermBridge** — single AppleScript chokepoint. Compiled-once `NSAppleScript`, run on background queue with hard 3 s timeout. Lookup: **UUID first → TTY fallback → friendly error** (never wrong-jump).
7. **HookInstaller** — idempotent JSON5-tolerant patcher of `~/.claude/settings.json`.
8. **SettingsStore + AppLifecycle (`SMAppService.mainApp`)** — `@AppStorage`-backed prefs; login-item state read live from `.status`.

**Key architectural patterns:** Stateless edge / stateful core; two-event correlation (start + stop); AppleScript by UUID, never by index; NSPanel, not NSWindow / SwiftUI `Window`.

See [ARCHITECTURE.md](./ARCHITECTURE.md) for component diagrams, race-condition analysis, and end-to-end data flow.

### Critical Pitfalls

1. **Hook `exit 2` makes Claude loop forever.** Stop hook MUST `exit 0` on success and on most failures; reserve non-zero only for "configuration is broken." Drives the thin-shell-hook + fat-daemon split. Address in Phase 1.

2. **Wrong tab on click destroys Core Value.** PPID-walking is broken because iTerm2's per-app server collapses panes under one parent. Fix: capture `ITERM_SESSION_ID` (UUID half) AND `tty` at hook time; multi-strategy lookup at click time; explicit "session no longer exists" fallback. Test matrix must include tmux, nix-shell, nested zsh/fish, venv, split panes.

3. **Floating widget steals focus.** Subclass `NSPanel` with `.nonactivatingPanel`, override `canBecomeKey` carefully, set `becomesKeyOnlyIfNeeded=true`, `LSUIElement=true`, host SwiftUI in `NSHostingView`. On click, jump straight to iTerm2 — do **not** call `NSApp.activate` on self first.

4. **Apple Events permission denial is unrecoverable without docs.** Mandatory `NSAppleEventsUsageDescription` with a specific user-trustworthy reason; trigger the prompt deterministically during onboarding, not at first real event; detect `errAEEventNotPermitted (-1743)` and surface deep link `x-apple.systempreferences:com.apple.preference.security?Privacy_Automation`; document `tccutil reset AppleEvents <bundle-id>` in README.

5. **"App is damaged" on Apple Silicon + macOS 15+ "Open Anyway" UX.** (a) every Apple Silicon binary must be at least ad-hoc-signed (`codesign --force --deep --sign -`) to launch at all; (b) macOS 15+ removed right-click → Open. PROJECT.md's distribution constraint is **outdated**. Canonical paths: System Settings → Privacy & Security → Open Anyway, or `xattr -cr`. Ship a `bypass-gatekeeper.command` helper in the DMG. Test on a fresh user account or VM.

**Other notable pitfalls** (full detail in [PITFALLS.md](./PITFALLS.md)):
- Sound during Focus/DnD: `NSSound`/`AVAudioPlayer` ignore Focus state. Recommended dual-channel: visual via `NSPanel`, audio via `UNNotificationSound`. Or accept Focus-bypass + provide explicit user mute.
- Concurrent Stop hook races: serialize through Swift `actor`; composite dedup key `(session_id, transcript_path, timestamp-rounded)`; stress-test with 10 hooks in 100 ms.
- AppleScript on main thread → beachball: always background queue + 3 s hard timeout + click debounce.
- Notch / multi-display: use `NSScreen.safeAreaInsets`; validate restored frames; provide "Reset widget position".
- `SMAppService` silent failure: read `.status`, never cache a Bool; require app in `/Applications`.

## Implications for Roadmap

### Phase 1: Foundation — Hook → App → Log

**Rationale:** Every other component depends on receiving events. The "stateless edge, stateful core" boundary and `LSUIElement`-headless skeleton are decisions that compound. Pitfalls #1 (hook `exit 2`), #3 (focus stealing), and the build-pipeline half of #5 (ad-hoc signing) must be locked here.

**Delivers:** A Stop event in a real Claude Code session lands as an OSLog line in the running App, with the App invisible (no Dock icon, no menu bar, no key-stealing window).

**Addresses:** Stop hook receiver; foundational pieces of the eventual hook-install requirement.

**Uses:** Swift / Xcode project; `Network.framework` `NWListener` + `NWEndpoint.unix`; `LSUIElement=true`; ad-hoc `codesign -s -` in build script.

**Implements:** Reporter shell script (start-and-stop variants); HookListener; bare AppLifecycle (single-instance, accessory activation policy).

**Avoids:** Pitfall #1 (hook `exit 0` policy), Pitfall #3 (NSPanel-flag discipline), Pitfall #5a (ad-hoc sign).

### Phase 2: Alert Loop — Threshold + Single Floating Widget

**Rationale:** Validates the start/stop correlation pattern with real Claude sessions before adding terminal-targeting complexity. Produces a *visibly working notifier* — minus the iTerm2 jump.

**Delivers:** A Claude turn that exceeds 30 s causes a persistent floating Claude-icon widget showing the project name. Click dismisses (no jump yet). Sound plays once. Settings persist across restarts.

**Addresses:** Time-threshold filter; floating `NSPanel` widget; folder-name display; sound + toggle; persist-until-click; Settings window.

**Uses:** SwiftUI `Settings` scene + `@AppStorage`; `NSPanel` subclass with `NSHostingView`; `AVAudioPlayer`.

**Implements:** UserPromptSubmit hook variant in Reporter; `SessionRegistry`; `NotificationOrchestrator`; `FloatingWidgetWindowController` (single-session form); `SettingsStore`.

### Phase 3: Click-to-iTerm2 — UUID Lookup + Permission Flow

**Rationale:** **Highest-risk piece** — Apple Events permission, AppleScript correctness, tab-not-found edge cases, session-identity decisions. Doing it after Phases 1–2 means the test harness already exists. Concentrating risk here makes it appropriate to flag for additional research.

**Delivers:** Clicking the widget jumps to the exact iTerm2 tab. Works across tab reorder, pane split, tab close (graceful error). Permission prompt triggered deterministically via "Test connection" UI.

**Addresses:** Click → focus exact iTerm2 tab; Automation permission first-run check + recovery dialog.

**Uses:** `NSAppleScript`; `NSAppleEventsUsageDescription`; System Settings deep link.

**Implements:** `iTermBridge` (UUID-by-iteration AppleScript, TTY fallback, hard 3 s timeout on background queue, click debounce); permission pre-warm at app launch.

**Avoids:** Pitfall #2 (wrong tab); Pitfall #4 (TCC denial); Pitfall #10 (AppleScript main-thread block).

### Phase 4: Multi-Session UX — Counter Badge + Stress Hardening

**Rationale:** Multi-session is the user's actual workload. Concurrent races cannot be reliably bolted on later — actor discipline and dedup keys must be enforced before stress shipping.

**Delivers:** Counter badge widget; click-to-expand session list popover; 10-hooks-in-100ms stress test passes; click order preserved.

**Addresses:** Counter badge + expandable list (Core differentiator); concurrent completion handling.

**Implements:** Batching window (~500 ms–2 s); `SessionListPopoverView`; composite dedup key.

**Avoids:** Pitfall #9 (concurrent races); Pitfall #2 again under load.

### Phase 5: Distribution Polish — Auto-install, DMG, Onboarding

**Rationale:** Onboarding wizard chains hook-install + Automation prompt + sound test. README/DMG come last because they reflect the now-validated UX, and the macOS 15+ "Open Anyway" instructions can only be written correctly once the actual user-facing path has been tested.

**Delivers:** A new user installs from `.dmg`, runs a 3-screen onboarding wizard, has a working notifier without touching their terminal. Uninstall path strips the hook entry cleanly.

**Addresses:** Hook auto-install with idempotent JSON merge; first-run onboarding wizard; `.dmg` distribution; README with current Gatekeeper bypass; Login Item registration via `SMAppService` (optional — can defer).

**Uses:** `create-dmg`; `xcodebuild archive` + `codesign --force --deep --sign -`; `SMAppService.mainApp` (optional); `bypass-gatekeeper.command` helper inside DMG.

**Implements:** `HookInstaller`; onboarding views; release-script glue.

**Avoids:** Pitfall #5b (PROJECT.md's outdated instruction replaced); Pitfall #8 (`SMAppService` cache mistake).

### Phase Ordering Rationale

- **Spine before face before punchline.** Hook-→-App pipeline is the spine, the widget is the face, the iTerm2 jump is the punchline — in that order.
- **Risk concentration in Phase 3.** Apple Events permission, AppleScript correctness, and session-identity edge cases concentrated in one phase, after a working alert loop exists.
- **Concurrency gate in Phase 4, not Phase 1.** Actor discipline established in Phase 2; stress-test gate at Phase 4 when multi-session UI exists to verify against.
- **Distribution last because the README reflects reality.** The correct macOS 15+ flow can only be written once the user-facing path is tested.

### Research Flags

**Phases likely needing deeper research during planning (`/gsd-research-phase`):**

- **Phase 3 (Click-to-iTerm2):** Open questions: (a) `ITERM_SESSION_ID` behavior in tmux/screen/nix-shell/zellij/containerized shells; (b) AppleScript `unique ID` lookup latency under typical pane counts; (c) recovery UX for `errAEEventNotPermitted` deep-link reliability across macOS 14/15/26.
- **Phase 5 (Distribution):** Validate (a) exact dialog text on macOS 14/15/26 when launching ad-hoc-signed-but-quarantined app; (b) whether `SMAppService.mainApp` strictly requires `/Applications`; (c) whether shipping `bypass-gatekeeper.command` triggers extra Gatekeeper friction.

**Phases with standard patterns (skip research-phase):**

- **Phase 1 (Foundation):** `LSUIElement` + `NWListener` over `AF_UNIX` + ad-hoc-sign well-documented.
- **Phase 2 (Alert Loop):** `NSPanel` floating-widget pattern well-documented; `@AppStorage` + SwiftUI `Settings` scene textbook.
- **Phase 4 (Multi-Session UX):** Counter badge + popover list straightforward SwiftUI; concurrency model already specified.

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Apple frameworks all GA since macOS 10.15–13; verified against Apple docs and 2024–2026 community sources. MEDIUM only on unsigned-distribution UX details (Apple keeps tightening). |
| Features | HIGH | Broad survey of 10+ comparable tools + PROJECT.md alignment. Differentiator triple empirically validated as missing from all surveyed tools. |
| Architecture | HIGH on hook contract, IPC choice, iTerm2 identity strategy; MEDIUM on AppleScript focus-mechanics latency (claimed sub-100 ms but not benchmarked) and `ITERM_SESSION_ID` behavior in exotic shells. |
| Pitfalls | HIGH on distribution / NSPanel / Apple Events; MEDIUM on Claude Code hook race behavior (under-documented in real-world stress) and DnD/Focus sound behavior. |

**Overall confidence:** HIGH for proceeding to roadmap and Phase 1 execution. Medium-confidence areas are concentrated in Phase 3 (session→tab mapping under exotic shells) and Phase 5 (distribution UX per OS release), both flagged for deeper research.

### Gaps to Address

- **PROJECT.md distribution instruction is outdated.** Constraints section says "우클릭 → 열기," removed in macOS 15+. Update PROJECT.md alongside Phase 5 README, OR earlier. Keep ad-hoc signing locked from Phase 1 regardless.
- **Two hooks, not one.** Architecture requires both `Stop` *and* `UserPromptSubmit` for elapsed-time computation. PROJECT.md mentions only `Stop`. Hook-install requirement (FEATURES + Phase 5) needs scoping for two entries. Surface in roadmap acceptance criteria.
- **`ITERM_SESSION_ID` reliability under tmux/nix-shell/containers.** Highest-risk failure mode. Recommended: build a logging mode in Phase 1 (`~/Library/Logs/ClaudeAlertBot/hook.log` recording `(timestamp, env-snapshot, ppid-chain, tty)`). Phase 3 research must include tmux/venv/nested-shell test matrix.
- **AppleScript `unique ID` latency unmeasured.** Phase 3 should benchmark with a 5-line probe script.
- **Focus/DnD sound respect — pick a strategy before Phase 2.** Three options: (a) `UNNotificationSound` + `NSPanel` dual-channel; (b) accept Focus-bypass + explicit user mute; (c) defer to v1.x. Recommendation: (a). Roadmapper should lock this before Phase 2.
- **No selection of socket vs. HTTP-on-localhost as IPC.** Both sound. Roadmapper should pick one and commit before Phase 1 — recommendation: AF_UNIX socket (no port management, no `settings.json` port hardcoding). HTTP is the strong alternative if installer ergonomics push back.

## Sources

### Primary (HIGH confidence)
- [Hooks reference — Claude Code Docs](https://code.claude.com/docs/en/hooks)
- [NSWindow.CollectionBehavior — Apple Developer](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)
- [nonactivatingPanel — Apple Developer](https://developer.apple.com/documentation/appkit/nswindow/stylemask-swift.struct/nonactivatingpanel)
- [NWListener — Apple Developer](https://developer.apple.com/documentation/network/nwlistener)
- [SMAppService — Apple Developer](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [NSAppleEventsUsageDescription — Apple Developer](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)
- [iTerm2 AppleScript Documentation](https://iterm2.com/documentation-scripting.html)
- [iTerm2 Variables Documentation](https://iterm2.com/documentation-variables.html)

### Secondary (MEDIUM confidence)
- [Showing Settings from macOS Menu Bar Items — Peter Steinberger (2025)](https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items)
- [SwiftUI Floating Panel: NSPanel Patterns — fazm.ai](https://fazm.ai/blog/swiftui-floating-panel)
- [Fine-Tuning macOS App Activation Behavior — artlasovsky.com](https://artlasovsky.com/fine-tuning-macos-app-activation-behavior)
- [create-dmg (sindresorhus, npm)](https://github.com/sindresorhus/create-dmg)
- [Apple Forces The Signing Of Applications In MacOS Sequoia 15.1 — Hackaday](https://hackaday.com/2024/11/01/apple-forces-the-signing-of-applications-in-macos-sequoia-15-1/)
- [Open unsigned applications on macOS Sequoia and newer — Hacks Guide Wiki](https://wiki.hacks.guide/wiki/Open_unsigned_applications_on_macOS_Sequoia_and_newer)
- [777genius/claude-notifications-go](https://github.com/777genius/claude-notifications-go)
- [marzocchi/zsh-notify](https://github.com/marzocchi/zsh-notify)
- [BUG: stale session_id — anthropics/claude-code#9188](https://github.com/anthropics/claude-code/issues/9188)
- [Notifications do not respect focus mode — Mailspring Community](https://community.getmailspring.com/t/notifications-do-not-respect-focus-mode-on-macos/9737)

For full-detail sourcing per area, see [STACK.md](./STACK.md), [FEATURES.md](./FEATURES.md), [ARCHITECTURE.md](./ARCHITECTURE.md), [PITFALLS.md](./PITFALLS.md).
