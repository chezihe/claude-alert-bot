# Feature Research

**Domain:** macOS floating notification companion for Claude Code (developer tool, single-user, hook-driven)
**Researched:** 2026-05-07
**Confidence:** HIGH (broad survey of Claude Code companion tools, zsh-notify, terminal-notifier, ntfy, plus PROJECT.md constraints)

---

## Survey Snapshot — Comparable Tools

Findings used to derive the categories below. Detail kept compact.

| Tool | Category | Features that matter to us |
|---|---|---|
| `wyattjoh/claude-code-notification` | Claude Code hook | macOS native notification, system sound list, custom audio file, JSON-via-stdin from hook |
| `dazuiba/CCNotify` | Claude Code hook | Desktop notification for completion + "needs input" |
| `777genius/claude-notifications-go` | Claude Code hook | 6 notification types, **click-to-focus exact terminal tab** (incl. iTerm2/tmux), suppress filters by status/branch/folder, webhook (Slack/Discord/Telegram/ntfy), volume, audio device routing |
| `mylee04/code-notify` | Multi-CLI hook | Cross-platform desktop notifications |
| `foxytanuki/ccnotify` | Claude Code hook | Stop hook → Discord / ntfy / macOS notifications |
| `ChanMeng666/claude-code-audio-hooks` | Claude Code hook | Sound-only on completion |
| `marzocchi/zsh-notify` | Shell long-cmd | Time threshold (default 30s), focus check (skip if terminal focused), command blacklist regex, custom title/icon/sound, terminal-activate-on-click, expiration timing |
| `julienXX/terminal-notifier` | CLI primitive | Banner with title/subtitle/sound, `-activate` to focus an app, `-group` to dedupe, exec on click |
| `ntfy.sh` / `dschep/ntfy` | Push/notif backend | `--longer-than` threshold, foreground-only filter, multiple backends (Slack/Telegram/XMPP), wrap-cmd helper |
| `rishi-banerjee1/claude-usage-widget` | Floating macOS widget | Single-file Swift, transparent floating panel, no deps — visual reference only |

Key pattern: **click-to-focus exact tab** is the differentiating capability that few tools nail; threshold + sound + click-to-something are universal table stakes.

---

## Feature Landscape

### Table Stakes (Users Expect These)

Missing any of these makes the product feel incomplete versus the tools above. All of these map directly to PROJECT.md Active requirements (good — confirms scope is correct).

| Feature | Why Expected | Complexity | Notes |
|---|---|---|---|
| Trigger on Claude Code `Stop` hook | Every comparable Claude Code companion does this; it is the standard integration point | LOW | Claude Code passes JSON on stdin (`session_id`, `transcript_path`, `cwd`-implied via env). Locked in PROJECT.md. |
| Time-threshold filter (skip short turns) | `zsh-notify` default 30s; `ntfy` default 10s; users universally complain about notification spam on 2-second prompts | LOW | Locked at default 30s, user-configurable. Implementation: record start time on `UserPromptSubmit` or `PreToolUse` hook, diff at `Stop`. |
| Visible alert at completion | Whole point of the tool | MEDIUM | PROJECT.md picks `NSPanel` floating widget over `UNUserNotification` — stronger visual persistence. |
| Folder/project name in alert | Every survey tool shows context; without it users can't tell which session finished | LOW | Derive from cwd in hook payload; show `basename(cwd)` on widget. |
| Sound on alert (with on/off toggle) | `terminal-notifier`, `wyattjoh/...`, `zsh-notify` all do this; users mute when in calls | LOW | Single bundled sound + toggle. Multiple sound choice → defer (see Differentiators). |
| Click on alert performs a useful action | `terminal-notifier -activate`, `zsh-notify` activates terminal, `claude-notifications-go` focuses exact tab | HIGH | **This is the Core Value.** iTerm2 AppleScript: find tab by tracked PID/session ID, `select` window+tab, activate iTerm2. |
| Persist until clicked (no auto-dismiss) | Differentiator from macOS Notification Center, but for this product it's table stakes — Core Value says "don't miss it" | LOW | `NSPanel` doesn't auto-dismiss; just don't add a timer. Locked in PROJECT.md. |
| Aggregate concurrent completions | Multi-session is the user's actual workload (PROJECT.md context); a stack of 5 widgets is unusable | MEDIUM | Counter badge + click-to-expand list. Locked in PROJECT.md. |
| Settings UI (threshold, sound on/off, widget position) | `zsh-notify` config, `claude-notifications-go` JSON config; opaque tools get abandoned | MEDIUM | SwiftUI settings window, persisted to `UserDefaults` or JSON in `~/Library/Application Support/`. |
| Distributable build (`.dmg`) | Users won't `xcodebuild` themselves | LOW | Xcode archive → `create-dmg` or manual. README documents Gatekeeper right-click→Open. |
| Hook auto-install (or copy-paste guide) | `ccnotify` and `code-notify` install hook automatically; without it onboarding is broken | MEDIUM | Detect `~/.claude/settings.json`, merge `Stop` hook entry, back up original. Locked in PROJECT.md. |
| AppleScript automation permission flow | macOS shows permission dialog on first iTerm2 control attempt; if app crashes or user denies, must guide recovery | LOW | First-run check; if denied, show dialog with deep-link to `System Settings → Privacy & Security → Automation`. |

### Differentiators (Competitive Advantage)

Features no current Claude Code companion combines well — adding 2-3 of these turns "another notifier" into "the notifier that *just works*". Some are recommended for v1, others are v1.x.

| Feature | Value Proposition | Complexity | v1? | Notes |
|---|---|---|---|---|
| **Click-to-exact-iTerm2-tab** (PID-tracked) | The Core Value. Most tools open *a* terminal; PROJECT.md targets *the* tab | HIGH | YES | Already locked. The reliability of session↔tab mapping is the make-or-break for this product. |
| **Multi-session counter + expandable list** | None of the surveyed Claude Code hook tools handle concurrent completions; they spam N notifications | MEDIUM | YES | Locked in PROJECT.md. Strong differentiator versus all surveyed tools. |
| **Floating widget instead of NotificationCenter** | macOS notifications are easy to miss / auto-collapse; a floating Claude icon is unmissable | MEDIUM | YES | Locked in PROJECT.md. Reference implementation: `claude-usage-widget` Swift `NSPanel`. |
| **Per-project threshold override** | Some projects (`infra-deploy`) always take >5min; a 30s threshold is noise | LOW | NO (v1.x) | Defer — locked default+global is enough for MVP. Adds settings UI complexity. |
| Per-project sound or icon tint | Visual disambiguation when 3 widgets stack | MEDIUM | NO (v1.x) | Single bundled sound + Claude icon for MVP; deferring keeps settings UI minimal. |
| **Recent completions history (last N)** | Click-through-able log when user was AFK during a burst | MEDIUM | NO (v1.x) | PROJECT.md Out of Scope says no "히스토리 대시보드" — but a *short* in-memory recent list is arguably the same as the expandable counter. **Treat as stretch in v1.x.** Do NOT build a stats dashboard (Out of Scope). |
| Idle-detection ("only alert if user away >2min") | `zsh-notify` skips if terminal focused. Cuts noise when user is actively watching | LOW | NO (v1.x) | Use `CGEventSource` `secondsSinceLastEventType`. Defer — threshold-based filter is "good enough" for MVP and adds a confusing second axis. |
| Focus / DnD respect | Don't pop a sound while user is in a call | MEDIUM | NO (v1.x) | **Caveat:** Apple has no public DnD API. Workarounds (read `~/Library/DoNotDisturb/DB/`) are fragile and break per OS release. Defer; document as known limitation. |
| Quiet hours / schedule | Same intent as DnD respect, but user-controlled (no API issue) | LOW | NO (v1.x) | Cleaner alternative to DnD-respect. Add in v1.x if users ask. |
| Snooze ("remind me in 5min") | If user clicks-to-focus but isn't ready, current widget vanishes | LOW | NO (v1.x) | Only valuable if widget dismissed early. Since widget already persists until click, snooze is redundant. **Skip permanently.** |
| Hook auto-install with one click | `ccnotify` does CLI install; a GUI "Install Claude Code hook" button is friendlier for non-CLI users | MEDIUM | YES (recommended) | Already implied by PROJECT.md ("자동으로 등록하거나 명확한 설치 가이드"). Pick the auto-register path for differentiation. |
| Granular hook event support (`Stop` + `Notification` for permission prompts) | `claude-notifications-go` distinguishes "task done" vs "needs input"; valuable when running long agents | MEDIUM | NO (v1.x) | PROJECT.md locks `Stop` only for v1. Revisit after validation. |
| Onboarding wizard (Automation permission, hook install, sound test) | Most surveyed tools just dump a README; a wizard would reduce setup failures from Automation/Gatekeeper friction | MEDIUM | YES (lite) | A 3-screen first-run sheet (welcome → install hook → grant Automation → test) materially reduces support burden. |

### Anti-Features (Commonly Requested, Often Problematic)

Things that *seem* like good additions for a notifier but conflict with PROJECT.md scope, this product's Core Value, or single-user-tool philosophy. Documented so they aren't quietly re-added.

| Feature | Why Requested | Why Problematic | Alternative |
|---|---|---|---|
| Webhook / Slack / Discord / Telegram forwarding | `ntfy`, `claude-notifications-go`, `ccnotify` all do this | Core Value is *jump back to the iTerm2 tab*. A Slack message can't focus iTerm2. Adds backend coupling, secret storage, network failure modes — all for a UX that fails at the Core Value. | Out of scope. If user wants remote pings, they should use one of the existing webhook tools alongside this app. |
| Reply-from-widget / quick action ("Continue", "/clear") | Slack/Mail-style notifications have reply | Claude Code is a TTY app; injecting input is brittle (PTY, shell quoting, AppleScript `keystroke`). High failure rate, low value — user is one click away from the actual terminal anyway. | Click-to-focus is the action. Replying happens in the terminal. |
| Last-Claude-response preview on widget | Surface info — "did it succeed?" before clicking | PROJECT.md Out of Scope: "위젯에는 폴더명만". Reasoning: response previews bloat the widget, leak sensitive content on shared screens, and pull users into reading on the widget instead of jumping to the tab (Core Value erosion). | Folder name only. Click to read body in iTerm2. |
| Progress / mid-task notifications | "Tell me when it hits step 5" | PROJECT.md Out of Scope explicitly. Claude Code emits no standard progress hook; would require log scraping. Noise risk is high. | `Stop` hook only. |
| Always-visible menu bar / Dock icon | Discoverability — "is the app running?" | PROJECT.md Out of Scope. The whole UX is "invisible until needed". A menu bar icon while idle is visual noise. | Hidden `LSUIElement`. App presence verified via the floating widget itself when it triggers. |
| Auto-dismiss timer | macOS notification convention | Directly contradicts Core Value ("don't miss it") and PROJECT.md. The whole differentiator is persistence. | Persist until click. Period. |
| Notification Center integration | Native macOS feel | PROJECT.md Out of Scope. NSUserNotification fades; this product *requires* persistence. | `NSPanel` floating widget. |
| Stats / analytics dashboard ("avg session length", "completions/day") | Quantified-self appeal | PROJECT.md Out of Scope. Dashboard maintenance is large; not part of Core Value. | None. If demanded post-launch, separate tool. |
| iCloud sync of settings | Multi-Mac developers | PROJECT.md Out of Scope. Single-machine tool. iCloud entitlements require code signing (also out of scope). | Local `UserDefaults` only. |
| Auto-update (Sparkle) | UX expectation | PROJECT.md Out of Scope for v1; Sparkle works without paid signing but requires EdDSA setup, hosting, and appcast feed — heavy for an unsigned hobby distribution. | Manual `.dmg` re-download. README-documented. Re-evaluate at user-count threshold. |
| Multi-terminal support (Terminal.app / Warp / Ghostty / kitty) | Wider audience | PROJECT.md Out of Scope for MVP. Each terminal needs its own focus/tab API; AppleScript coverage varies wildly. The session↔tab mapping work is iTerm2-shaped. | iTerm2 only for v1. Revisit after validation. |
| Windows / Linux build | Cross-platform habit | PROJECT.md Out of Scope. Floating-widget UX and AppleScript-based focus are macOS-specific by definition. | macOS only. |
| Code-signed / notarized / App Store build | "Real app" feel | PROJECT.md Out of Scope ($99/yr). Right-click→Open is acceptable cost. | README documents Gatekeeper bypass. |
| Custom message templates | Power-user flair | The widget displays exactly one short label (folder name). Templating adds settings surface for negligible value. | Folder name + count; non-configurable. |
| Multiple notification "channels" (different settings for "Stop" vs "Notification" vs error) | Power user differentiation, like `claude-notifications-go` | v1 is `Stop`-only. Adds settings complexity before any real demand. | Single channel for v1. |

---

## Feature Dependencies

```
Stop hook receiver (HOOK)
    └─requires─> Hook auto-install OR install guide (INSTALL)

Time-threshold filter (THRESHOLD)
    └─requires─> Session start-time tracking (TRACK)
                     └─requires─> Per-session state file or in-memory store (STATE)

Click-to-iTerm2-tab (FOCUS)
    └─requires─> Session ↔ iTerm2 tab mapping (MAP)
                     └─requires─> Hook PID/session-id capture at start (TRACK)
                     └─requires─> AppleScript automation permission (PERM)

Floating widget (WIDGET)
    └─requires─> NSPanel + collectionBehavior (PANEL)

Counter badge + expand-to-list (AGGREGATE)
    └─requires─> WIDGET
    └─requires─> MAP (each list row needs to know its target tab)

Settings UI (SETTINGS)
    └─requires─> THRESHOLD, sound toggle, widget position store (PREFS)

DMG distribution (DMG)
    └─requires─> Xcode archive
    └─enhances─> INSTALL (DMG can bundle the hook installer)

Onboarding wizard (ONBOARD) [recommended differentiator]
    └─requires─> INSTALL, PERM check, sound test
    └─enhances─> All of the above on first run
```

### Dependency Notes

- **THRESHOLD requires TRACK:** You can't measure duration without recording start time. Implementation choice (PROJECT.md Context): either Claude Code emits a `UserPromptSubmit`-equivalent event we hook, or we instrument the `Stop` hook to read elapsed time from a state file we wrote at prompt start. This is a **plan-phase decision** — flag for next research pass.
- **FOCUS requires MAP requires TRACK:** The PID-tracking approach (PROJECT.md Context option 1) makes TRACK do double duty — start-time *and* session↔tab identity come from the same record. Strong argument for picking that approach.
- **AGGREGATE requires MAP:** Each entry in the expanded list must know its specific tab. Without MAP, the list is decorative.
- **PERM is a soft dependency for FOCUS:** The app *runs* without Automation permission, but the click action silently fails. Onboarding must surface this explicitly or users will think the app is broken.
- **DMG enhances INSTALL:** A first-run `.dmg` install can chain into hook install + Automation permission prompt — turning three confusing setup steps into one wizard.
- **No hard conflicts** between in-scope features. The conflicts are between in-scope items and Anti-Features (e.g. auto-dismiss conflicts with persistence; Slack forwarding conflicts with click-to-focus).

---

## MVP Definition

### Launch With (v1)

Each of these is locked by PROJECT.md Active. They are the smallest set that delivers the Core Value ("don't miss it + jump to *the* tab").

- [ ] `Stop` hook receiver, JSON-on-stdin (HOOK) — without this nothing triggers
- [ ] Session start-time tracking + duration calc (TRACK + THRESHOLD) — kills 2-second-prompt noise
- [ ] Configurable threshold, default 30s — survey shows 30s is the right default (zsh-notify match)
- [ ] Floating Claude-icon widget via `NSPanel` (WIDGET) — Core Value depends on persistence
- [ ] Folder name on widget — minimum disambiguation
- [ ] Single sound on alert + on/off toggle — universal table stake
- [ ] Persist until clicked (no auto-dismiss) — directly Core Value
- [ ] Counter badge + click-to-expand list for concurrent completions (AGGREGATE) — multi-session is the actual workload
- [ ] Click → focus exact iTerm2 tab via PID-tracked AppleScript (FOCUS + MAP) — the Core Value
- [ ] Settings window: threshold, sound on/off, widget position (SETTINGS)
- [ ] `.dmg` distribution + Gatekeeper README (DMG)
- [ ] Hook auto-install (settings.json merge) with manual fallback (INSTALL)
- [ ] Automation permission first-run check + recovery dialog (PERM)
- [ ] First-run onboarding wizard *(recommended differentiator, lite)* — 3 screens: install hook, grant Automation, test

### Add After Validation (v1.x)

Add these once v1 is shipped, real users have used it, and specific pain is reported.

- [ ] Per-project threshold override — trigger: a user says "infra repo always over 30s, want 5min there"
- [ ] Per-project sound or widget tint — trigger: user runs 4+ concurrent sessions and reports stack confusion
- [ ] Recent completions ring buffer (last 5–10) — trigger: user reports missing a click on the dismissed widget. Stay short and *not* a dashboard (Out of Scope guard).
- [ ] Quiet hours / schedule — trigger: meeting-heavy user complains about call-time pings
- [ ] Idle-detection ("only alert if AFK >2min") — trigger: user-noise feedback that 30s threshold isn't enough
- [ ] `Notification` hook (permission prompts) — trigger: long-agent users want "needs input" alerts
- [ ] Sound picker (system sounds dropdown) — trivial once SETTINGS exists; defer until anyone asks

### Future Consideration (v2+)

Defer until product-market fit; would change the product's shape.

- [ ] Multi-terminal: Terminal.app / Warp / Ghostty / kitty — significant per-terminal mapping work; revisit if user requests dominate
- [ ] Auto-update (Sparkle) — needs EdDSA setup + appcast hosting; only worth it past ~50 active users
- [ ] Code signing / notarization — $99/yr; re-evaluate if Gatekeeper friction becomes the #1 install issue
- [ ] Multi-Mac sync — entitlement-heavy, contradicts single-machine ethos
- [ ] Granular per-channel settings (Stop vs Notification vs error) — wait for v1.x to surface real demand

### Permanently Excluded

- Webhook / Slack / Discord forwarding — incompatible with Core Value (no remote tab to focus)
- Reply / quick-action from widget — brittle PTY injection; click-to-tab is the action
- Response-body preview on widget — PROJECT.md Out of Scope, also leaks content
- Mid-task progress notifications — Out of Scope; noise risk
- Stats dashboard — Out of Scope; not Core Value
- Auto-dismiss / Notification Center route — directly contradicts Core Value
- Always-visible menu bar / Dock icon — Out of Scope
- Snooze — redundant given persistence

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---|---|---|---|
| Stop hook receive + JSON parse | HIGH | LOW | P1 |
| Time threshold (default 30s, configurable) | HIGH | LOW | P1 |
| Session start-time tracking | HIGH | MEDIUM | P1 |
| Floating widget (`NSPanel`) | HIGH | MEDIUM | P1 |
| Folder name display | HIGH | LOW | P1 |
| Sound + on/off | MEDIUM | LOW | P1 |
| Persist-until-click | HIGH | LOW | P1 |
| Concurrent aggregate (counter + list) | HIGH | MEDIUM | P1 |
| Click-to-iTerm2-tab via PID map | HIGH | HIGH | P1 |
| Settings window | MEDIUM | MEDIUM | P1 |
| `.dmg` distribution + README | HIGH | LOW | P1 |
| Hook auto-install | HIGH | MEDIUM | P1 |
| Automation-permission first-run check | HIGH | LOW | P1 |
| Onboarding wizard (3-screen) | MEDIUM | MEDIUM | P1 (recommended) |
| Per-project threshold override | MEDIUM | LOW | P2 |
| Per-project sound/tint | LOW | MEDIUM | P2 |
| Recent completions ring buffer | MEDIUM | MEDIUM | P2 |
| Quiet hours | MEDIUM | LOW | P2 |
| Idle-detection alternative | LOW | LOW | P2 |
| Sound picker | LOW | LOW | P2 |
| `Notification` hook (permission prompts) | MEDIUM | MEDIUM | P2 |
| Multi-terminal | MEDIUM | HIGH | P3 |
| Auto-update (Sparkle) | LOW | MEDIUM | P3 |
| Code signing / notarization | LOW (cost-LOW for users) | HIGH ($) | P3 |
| Webhook / Slack / Discord | LOW (anti-fit) | MEDIUM | EXCLUDE |
| Reply-from-widget | LOW | HIGH | EXCLUDE |
| Response preview | LOW (anti-fit) | LOW | EXCLUDE |
| Mid-task progress | LOW | HIGH | EXCLUDE |
| Stats dashboard | LOW | HIGH | EXCLUDE |
| Auto-dismiss | NEGATIVE | LOW | EXCLUDE |
| Snooze | LOW | LOW | EXCLUDE |

**Priority key:**
- P1: Must have for launch
- P2: v1.x — add when validated demand
- P3: v2+ — defer until PMF
- EXCLUDE: deliberately do not build

---

## Competitor Feature Analysis

| Feature | wyattjoh/claude-code-notification | claude-notifications-go | zsh-notify | terminal-notifier | Our Approach |
|---|---|---|---|---|---|
| Trigger | Claude Code hook (Notification + Stop) | Claude Code hooks (6 types) | shell precmd | manual `; terminal-notifier` | Stop hook only (v1) |
| Visual surface | macOS NotificationCenter | NotificationCenter | NotificationCenter | NotificationCenter | **Floating `NSPanel` widget** (persistent) |
| Persistence | Auto-dismiss | Auto-dismiss | Auto-dismiss | Auto-dismiss | **Until clicked** |
| Click action | None / open URL | Focus exact terminal tab (iTerm2/Warp/Ghostty/tmux) | Activate terminal | `-activate` an app | **Focus exact iTerm2 tab via PID** |
| Threshold filter | None | Configurable suppress windows | Default 30s | None (caller decides) | **Default 30s, configurable** |
| Multi-event aggregation | None | None | None | `-group` dedupes | **Counter badge + expand list** (unique) |
| Sound | System sounds + custom file | Custom MP3 + volume + device | Custom sound | System sound | Single bundled sound + on/off (v1); picker in v1.x |
| Webhook forwarding | No | Yes (Slack/Discord/ntfy/etc) | No | No | **No (anti-feature)** |
| Hook install | Manual | One-line install | Plugin manager | N/A | **Auto-merge into settings.json** |
| Multi-terminal | N/A (notification only, no focus) | Yes (many) | Terminal.app + iTerm2 | N/A | **iTerm2 only (v1)** |
| Distribution | `cargo install` | `go install` / homebrew | zsh plugin | brew | **`.dmg` (unsigned)** |

**Where we win:** persistence + click-to-exact-tab + concurrent-aggregate is a combination none of the surveyed tools deliver. That's the differentiation surface.

**Where we deliberately lose:** cross-platform, multi-terminal, webhook forwarding. Owning the macOS-iTerm2-Claude-Code intersection completely beats being mediocre on all three axes.

---

## Sources

- [disler/claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery)
- [Claude Code Hooks reference](https://code.claude.com/docs/en/hooks)
- [wyattjoh/claude-code-notification](https://github.com/wyattjoh/claude-code-notification)
- [dazuiba/CCNotify](https://github.com/dazuiba/CCNotify)
- [777genius/claude-notifications-go](https://github.com/777genius/claude-notifications-go) — strongest comparable; click-to-focus exact tab
- [mylee04/code-notify](https://github.com/mylee04/code-notify)
- [foxytanuki/ccnotify](https://github.com/foxytanuki/ccnotify)
- [ChanMeng666/claude-code-audio-hooks](https://github.com/ChanMeng666/claude-code-audio-hooks)
- [marzocchi/zsh-notify](https://github.com/marzocchi/zsh-notify)
- [julienXX/terminal-notifier](https://github.com/julienXX/terminal-notifier)
- [ntfy.sh docs — examples](https://docs.ntfy.sh/examples/)
- [dschep/ntfy](https://github.com/dschep/ntfy)
- [rishi-banerjee1/claude-usage-widget](https://rishi-banerjee1.github.io/claude-usage-widget/) — Swift floating-panel reference
- [Claude Code feature request: macOS widget](https://github.com/anthropics/claude-code/issues/18018)
- [Claude Code feature request: system notifications](https://github.com/anthropics/claude-code/issues/26581)
- [Claude Code feature request: audio notifications](https://github.com/anthropics/claude-code/issues/15795)
- [sindresorhus/do-not-disturb](https://github.com/sindresorhus/do-not-disturb) — confirms no public DnD API
- [Apple Developer Forums: Checking for doNotDisturb](https://developer.apple.com/forums/thread/100511)
- PROJECT.md (locked Active requirements + Out of Scope)

---
*Feature research for: macOS floating notification companion for Claude Code*
*Researched: 2026-05-07*
