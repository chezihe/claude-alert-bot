# Claude Alert Bot — macOS Implementation Spec

> **Reference prototype:** internal motion prototype
> The HTML file is the source of truth for visuals, motion, and interaction. This document maps it to native macOS APIs.
>
> **Current implementation note:** repository-level constraints in `AGENTS.md` / `CLAUDE.md` override prototype-era alternatives below. The app currently uses Claude Code / Codex CLI hooks + Unix domain socket IPC, `NSAppleScript` for iTerm2, `AVAudioPlayer` for sound, and a floating `NSPanel` widget.

---

## 1. App Architecture

| Concern | Native API |
|---|---|
| Floating widget (the bot glyph) | `NSPanel` subclass + `NSHostingView`, floating above spaces; `MenuBarExtra` is only the Settings/Quit handle |
| Popover panel | `NSPopover` (behavior: `.transient`, animates: `true`, contentSize matches HTML 270×auto) |
| Frosted material | `NSVisualEffectView` — `.material = .popover`, `.blendingMode = .behindWindow`, `.state = .active` |
| Glyph rendering | SwiftUI `Image("ClaudeCodeIcon")` inside `WidgetIconView` |
| Animations | `CABasicAnimation` / `CAKeyframeAnimation` (timings below), or SwiftUI `.animation()` with custom `Animation.spring` |
| Sounds (optional) | `AVAudioPlayer` on new alert, gated by Quiet Hours |
| Right-click menu | SwiftUI context menu on popover rows / grouped project headers |
| Settings window | Standard `NSWindow` opened from the gear icon in popover footer |
| Persistence | `UserDefaults` for prefs, `Codable` queue snapshots in `~/Library/Application Support/ClaudeAlertBot/sessions.json` |

---

## 2. iTerm2 Integration

The widget needs to know **(a) when a Claude Code or Codex CLI session finishes** and **(b) how to focus that exact iTerm session** when the user clicks a row.

**Current implementation:** Claude Code and Codex CLI `Stop` / `UserPromptSubmit` hooks run `Reporter/cab-report.sh`, which posts a JSON envelope to the app over a Unix domain socket. Row click focuses iTerm2 with compiled `NSAppleScript`. The iTerm2 Python API is not used in this project.

Each event payload:

```json
{
  "schema_version": 1,
  "event": "stop",
  "session_id": "...",       // iTerm2 session UUID
  "transcript_path": "...",
  "cwd": "...",
  "iterm_session_id": "...",
  "tty": "/dev/ttys001",
  "term_program": "iTerm.app",
  "ts": "2026-05-10T00:00:00Z",
  "started_at": 1730000000,
  "exit_code": 0,            // 0 = success, nonzero = error
  "kind": "success" | "error" | "waiting",
  "last_output": "..."       // optional, last 3-5 lines
}
```

**Row click → focus session:**
```swift
await ITerm2Jumper().jump(to: session)
```
If session no longer exists, mark row `unavailable` (50% opacity, hollow status dot) — see prototype.

---

## 3. Visual Tokens

Lift these directly from the HTML.

### Color
| Token | Light | Dark |
|---|---|---|
| Accent (warm orange) | `#D97757` | `#D97757` |
| Accent dark | `#B8492C` | `#B8492C` |
| Status: success | `#D97757` | `#D97757` |
| Status: error | `#E5484D` | `#E5484D` |
| Status: waiting | `#F5A623` | `#F5A623` |
| Popover bg (behind material) | `rgba(248,247,245,0.55)` | `rgba(38,38,42,0.55)` |
| Row hover | `rgba(217,119,87,0.13)` | `rgba(217,119,87,0.20)` |
| Text primary | `#1d1d1f` | `#f5f5f7` |
| Text secondary | `rgba(20,20,22,0.5)` | `rgba(255,255,255,0.55)` |

### Geometry
- Popover: 270pt wide, 14pt corner radius
- Row: 36pt min height, 12pt horizontal padding, 8pt vertical padding
- Status dot: 7pt; hollow ring stroke 1.5pt
- Widget glyph: 36pt glyph in a 50pt drawable (HTML proto host 56pt, downsized to fit the native panel without clipping shadow + badge overhang). Badge is a min-18pt-tall accent-dark capsule with a 2pt outer ring and a `+5/-6` top-trailing overhang. A 40×8pt elliptical ground shadow sits at the panel bottom, breathing in sync with bounce (0.9s) and going static under heart/ring/roam.
- Context menu: 180pt min width, 8pt corner radius

### Typography
- UI: SF Pro (system font)
- Mono (terminal-flash overlay): SF Mono
- Sizes: row body 13pt, timestamps 11.5pt, secondary 11pt, kbd hints 10pt

---

## 4. Motion

Each animation maps to the HTML prototype's `@keyframes` block (the visual source of truth) and a matching SwiftUI primitive.

| Animation | Duration | Curve | Notes |
|---|---|---|---|
| Bounce (idle) | 0.9s, infinite | easeInOut, 5-keyframe | 2-axis squash-and-stretch. Bottom (0%, 100%): scale(1.04, 0.94) translateY 0. Apex (50%): scale(0.97, 1.05) translateY -5pt. Mid (18%, 82%): scale(1.01, 0.99) translateY -2pt. Source: HTML `@keyframes bounce-cute`. |
| Breathe | 2.4s, autoreverse, infinite | `easeInOut` | scale 1.0↔1.06 |
| Heart (idle) | 1.4s, infinite | easeInOut, 6-keyframe | Double-pulse: 14% scale 1.14, 28% 1.0, 42% 1.08, 56% 1.0, 56→100% idle. Source: HTML `@keyframes heartbeat`. |
| Ring (bell) | 1.4s, infinite | `easeInOut` | Damped top-anchor swing: 0° → -14° → 12° → -9° → 7° → -4° → 2° → 0°. Source: HTML `@keyframes ring`. |
| Roam (running track) | 1.6s, infinite, **linear** | linear | 24×6pt elliptical path, counter-clockwise |
| Drift | 6s, infinite | `easeInOut` | random jitter within 14×16pt |
| New-alert pulse | 0.45s | spring (response 0.3, damping 0.5) | scale 1.14 → 0.96 → 1.06 → 1, rotate ±7°. HTML prototype uses `cubic-bezier(.4, 1.5, .5, 1)`; Swift uses chained springs. Treated as equivalent. |
| Sonar wave | 0.75s | `easeOut` | ring scales 0.5 → 3.0, opacity 0.75 → 0. Base 14pt → peak 42pt. **Known divergence:** widget drawable is 44pt so the peak brushes the panel edge; HTML host is 56pt. Deferred — see divergence notes below. |
| Status dot ripple (just-arrived) | 1s × 3 cycles | `easeOut` | secondary ring scale 1 → 2.4, opacity 0.6 → 0 |
| Row dismiss | 0.32s | `easeIn` | translateX(8pt) + opacity + height collapse. Implemented via SwiftUI `.transition(.asymmetric(...))` on ForEach children, driven by a `displayQueue` `@State` mirror inside `PopoverContentView`. |
| Popover open | spring (response 0.35, damping 0.6) | spring with mild overshoot | NSPopover's stock alpha fade plus a content-level scale 0.85→1.0 anchored at the widget corner. Not a window-level spring (NSPopover does not expose one); the content scale is the dominant motion. |

### Known motion divergences (acknowledged, deferred)

- **Sonar drawable.** HTML widget host is 56×56pt giving the 42pt peak sonar 7pt of margin per side. The native widget panel is 44×44pt, so the peak sonar tail brushes the panel edge. Widening `GeometryTokens.widgetBaseSize` would cascade into badge offset, hover hit-test area, and corner-snap geometry — out of scope for a motion-only sweep. Revisit if users report the clipping is visible.
- **New-alert pulse curve.** HTML applies a single `cubic-bezier(.4, 1.5, .5, 1)` over 0.45s; Swift chains four `spring(response: 0.3, damping: 0.5)` calls at 0%, 25%, 50%, and 100% of the same window. End shape is close. Refactor to a `KeyframeAnimator` if the spring chain ever produces visible jitter.
- **Popover open spring.** Window-level spring is not achievable through `NSPopover.show(relativeTo:)` — the stock alpha fade is always applied. Approximated via a content-level scale spring anchored at the widget corner. Migrating to a custom `NSPanel`-based popover would unlock a true window-level spring but is a much larger change.

**Reduce Motion (Accessibility):** when `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion == true`, disable all infinite loops, replace springs with linear 0.15s fades.

---

## 5. State Model

```swift
struct Session: Identifiable, Codable {
    let id: UUID                       // sessionID
    let itermSessionID: String?
    let projectName: String
    let stoppedAt: Date
    let durationSec: Int?              // nil = orphan (unknown duration)
    let kind: AlertKind                // .success | .error | .waiting
    var available: Bool                // false = iTerm session gone
    var pinned: Bool = false
    var justArrived: Bool = false      // 3-second decay flag
}

enum AlertKind: String, Codable {
    case success, error, waiting
}

@Observable
final class AlertBotStore {
    var queue: [Session] = []
    var quietHours: Bool = false
    var mutedProjects: [String: Date] = [:]   // project → unmute time
    var reduceMotion: Bool = false
    // ...
}
```

### Behaviors
- **Onboarding:** if `queue.isEmpty && !state.everHadAlerts`, popover shows "Listening to iTerm" empty state
- **Aging:** rows older than 60min get desaturated (`saturation(0.4)` on the whole row, binary on/off; opacity unchanged) — see `EffectTokens.agedSaturation`
- **Grouping:** when 3+ sessions share `projectName`, collapse into a header row with count badge; tap to expand
- **Mute project:** right-click row → "Mute this project for 1h" — stores `Date().addingTimeInterval(3600)` in `mutedProjects[projectName]`. Incoming alerts for muted projects bypass the queue silently.
- **Pin:** muted from auto-clear sweeps; persists across app restarts
- **Quiet Hours:** glyph animation paused, quiet marker shown, badge remains visible but desaturated; alerts still queue but no sound/pulse fires
- **Clear All / Clear Unpinned:** appears when at least 2 unpinned sessions are clearable; pinned sessions are preserved

---

## 6. Files to Build

```
ClaudeAlertBot/
├── App/
│   ├── ClaudeAlertBotApp.swift
│   ├── AppDelegate.swift
│   ├── FloatingWidgetPanel.swift
│   ├── FloatingWidgetWindowController.swift
│   ├── WidgetIconView.swift
│   ├── WidgetPopoverController.swift
│   ├── PopoverContentView.swift
│   ├── PopoverRowView.swift
│   ├── EmptyStateView.swift
│   ├── SettingsView.swift
│   ├── SessionRegistry.swift
│   ├── SessionStore.swift
│   ├── HookListener.swift
│   ├── AppleScriptHelper.swift
│   ├── ITerm2Jumper.swift
│   └── SoundPlayer.swift
├── Reporter/
│   └── cab-report.sh              // Claude Code / Codex CLI hook reporter
├── ClaudeAlertBotTests/
│   └── ...                        // XCTest coverage
└── Resources/
    └── Sounds/                    // optional future bundled sounds
```

---

## 7. Out of Scope (Prototype Liberties)

These exist in the HTML for demo purposes only:
- The fake "iTerm flash" overlay when clicking a row — real app calls `ITerm2Jumper.jump(to:)`
- The dev controls panel on the right — remove entirely
- The "v2" chip banner — remove
- The `<desktop>` background and dock — replace with real macOS host
- Dust particles under "Roam" animation — keep if performance allows; cosmetic only

---

## 8. Recommended Build Order

1. **Floating widget + popover shell** with hardcoded queue → match prototype look
2. **Animations** — start with breathe (simplest), then bounce, then new-alert pulse
3. **Claude hook + iTerm2 AppleScript bridge** — get one real alert end-to-end
4. **Row interactions** — click-to-focus, context menu, mute/pin
5. **Settings window** + persistence
6. **Quiet Hours, Reduce Motion, aging** — polish pass
7. **Sound integration** — Focus/DnD detection was retracted; Quiet Hours is the supported mute path.

---

**Resolved implementation decisions:**
- App Sandbox stays off.
- Sparkle auto-update is out of scope.
- Code signing is ad-hoc only; notarization is out of scope.
