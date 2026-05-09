# Claude Alert Bot — macOS Implementation Spec

> **Reference prototype:** `Claude Alert Bot - Prototype v2.html`
> The HTML file is the source of truth for visuals, motion, and interaction. This document maps it to native macOS APIs.

---

## 1. App Architecture

| Concern | Native API |
|---|---|
| Menu-bar widget (the floating bot glyph) | `NSStatusItem` with custom `NSView` (do **not** use the default text/image — we need full custom drawing for the breathing/bounce animations and badge) |
| Popover panel | `NSPopover` (behavior: `.transient`, animates: `true`, contentSize matches HTML 270×auto) |
| Frosted material | `NSVisualEffectView` — `.material = .popover`, `.blendingMode = .behindWindow`, `.state = .active` |
| Glyph rendering | Custom `CALayer` tree, or SwiftUI `Canvas` inside the status item view |
| Animations | `CABasicAnimation` / `CAKeyframeAnimation` (timings below), or SwiftUI `.animation()` with custom `Animation.spring` |
| Sounds (optional) | `NSSound(named: "Tink")` on new alert, gated by Quiet Hours |
| Right-click menu | `NSMenu` attached to status item / popover row |
| Settings window | Standard `NSWindow` opened from the gear icon in popover footer |
| Persistence | `UserDefaults` for prefs, `Codable` queue snapshots in `~/Library/Application Support/AlertBot/` |

---

## 2. iTerm2 Integration

The widget needs to know **(a) when a Claude Code session finishes** and **(b) how to focus that exact iTerm session** when the user clicks a row.

**Recommended:** iTerm2 Python API (`iterm2` package). Spawn a long-lived helper script that:

1. Subscribes to session-end / prompt-detected events
2. Filters for sessions where the running command was `claude` / `claude code`
3. Posts an event to the AlertBot app (Unix domain socket, XPC, or local HTTP)

Each event payload:

```json
{
  "session_id": "...",       // iTerm2 session UUID
  "project_name": "...",     // basename of cwd
  "started_at": 1730000000,
  "stopped_at": 1730000067,
  "exit_code": 0,            // 0 = success, nonzero = error
  "kind": "success" | "error" | "waiting",
  "last_output": "..."       // optional, last 3-5 lines
}
```

**Fallback:** AppleScript polling (less reliable, higher latency).

**Row click → focus session:**
```swift
// via iTerm2 Python API
session = await iterm2.Session.async_get(session_id)
await session.async_activate()
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
- Popover: 280pt wide, 14pt corner radius
- Row: 36pt min height, 12pt horizontal padding, 8pt vertical padding
- Status dot: 7pt; hollow ring stroke 1.5pt
- Widget glyph: ~22pt in 28pt status item; badge offsets `top: -11, right: -5`
- Context menu: 180pt min width, 8pt corner radius

### Typography
- UI: SF Pro (system font)
- Mono (terminal-flash overlay): SF Mono
- Sizes: row body 13pt, timestamps 11.5pt, secondary 11pt, kbd hints 10pt

---

## 4. Motion

Each animation in the prototype maps to a Core Animation timing curve.

| Animation | Duration | Curve | Notes |
|---|---|---|---|
| Bounce (idle) | 0.45s, autoreverse, infinite | `easeInOut` | 5pt vertical + scale 1.04↔0.94 squash |
| Breathe | 2.4s, autoreverse, infinite | `easeInOut` | scale 1.0↔1.06 |
| Ring (bell) | 0.55s | `easeInOut` | rotate ±10° from top anchor |
| Roam (running track) | 1.6s, infinite, **linear** | linear | 24×6pt elliptical path, counter-clockwise |
| Drift | 6s, infinite | `easeInOut` | random jitter within 14×16pt |
| New-alert pulse | 0.45s | spring (response 0.3, damping 0.5) | scale 1.14 → 0.96 → 1.06 → 1, rotate ±7° |
| Sonar wave | 0.75s | `easeOut` | ring scales 0.5 → 3.0, opacity 0.75 → 0 |
| Status dot ripple (just-arrived) | 1s × 3 cycles | `easeOut` | secondary ring scale 1 → 2.4, opacity 0.6 → 0 |
| Row dismiss | 0.32s | `easeIn` | translateX(8pt) + opacity + height collapse |
| Popover open | 0.45s | spring | from widget origin, slight overshoot |

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
- **Aging:** rows older than 60min get desaturated (filter `saturate(0.25) brightness(1.15)` on the dot, opacity 0.55 on project text)
- **Grouping:** when 3+ sessions share `projectName`, collapse into a header row with count badge; tap to expand
- **Mute project:** right-click row → "Mute this project for 1h" — stores `Date().addingTimeInterval(3600)` in `mutedProjects[projectName]`. Incoming alerts for muted projects bypass the queue silently.
- **Pin:** muted from auto-clear sweeps; persists across app restarts
- **Quiet Hours:** glyph animation paused, moon overlay shown, badge desaturated; alerts still queue but no sound/pulse fires
- **Clear All:** appears only when `queue.count >= 2`

---

## 6. Files to Build

```
AlertBot/
├── AlertBotApp.swift              // @main, lifecycle
├── StatusItemController.swift     // NSStatusItem + custom view
├── Views/
│   ├── WidgetView.swift           // glyph + badge + animations
│   ├── PopoverView.swift          // SwiftUI list of sessions
│   ├── SessionRow.swift           // single row with status dot
│   ├── EmptyStateView.swift       // onboarding "Listening..."
│   └── PreferencesWindow.swift    // gear icon target
├── Models/
│   ├── Session.swift
│   └── AlertBotStore.swift
├── Services/
│   ├── ITermBridge.swift          // Python API socket client
│   ├── NotificationCoordinator.swift
│   └── PersistenceController.swift
└── Resources/
    └── Sounds/Tink.aiff
```

---

## 7. Out of Scope (Prototype Liberties)

These exist in the HTML for demo purposes only:
- The fake "iTerm flash" overlay when clicking a row — real app just calls `async_activate()`
- The dev controls panel on the right — remove entirely
- The "v2" chip banner — remove
- The `<desktop>` background and dock — replace with real macOS host
- Dust particles under "Roam" animation — keep if performance allows; cosmetic only

---

## 8. Recommended Build Order

1. **Status item + popover shell** with hardcoded queue → match prototype look
2. **Animations** — start with breathe (simplest), then bounce, then new-alert pulse
3. **iTerm2 bridge** — get one real alert end-to-end
4. **Row interactions** — click-to-focus, context menu, mute/pin
5. **Settings window** + persistence
6. **Quiet Hours, Reduce Motion, aging** — polish pass
7. **Sound + Focus filter integration**

---

**Questions for the implementer:**
- App Sandbox? (iTerm2 bridge needs Apple Events entitlement either way)
- Sparkle for auto-update?
- Code signing / notarization plan?
