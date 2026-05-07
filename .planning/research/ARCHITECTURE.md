# Architecture Research

**Domain:** macOS native menu-less companion app + shell hook integration + terminal automation
**Researched:** 2026-05-07
**Confidence:** HIGH for hook contract, IPC choices, and iTerm2 identity; MEDIUM for fine-grained AppleScript focus mechanics (verified by docs but not benchmarked).

---

## Executive Architecture Decision

This is a **two-process system glued by a single Unix domain socket**:

1. A tiny **shell hook script** (the "Reporter") invoked by Claude Code's `Stop` hook on every assistant turn end. It does no UI and no waiting — it serializes a JSON payload describing the event (with the session-identity fields below), writes it to a Unix domain socket, and exits in milliseconds.
2. A long-running **Swift menu-less app** (the "Daemon UI", referred to below as the App) registered as a LaunchAgent / Login Item. It owns all state, computes elapsed time, decides whether to alert, renders the floating widget, and on click drives iTerm2 via AppleScript.

The hook **never** holds session state. It is a stateless edge that emits two events per turn (a `start` and a `stop`) and the App correlates them. This keeps the hook robust to crashes, kills, and reinstalls.

---

## System Overview

```
┌──────────────────────────── User's iTerm2 tab ───────────────────────────────┐
│                                                                              │
│  $ claude  ─────────────────────────► Claude Code process                    │
│                                              │ Stop hook fires               │
│                                              ▼                               │
│                                    ┌──────────────────┐                      │
│                                    │  Reporter (sh)   │  reads stdin JSON,   │
│                                    │  ~/.claude/hooks │  reads ITERM_SESSION │
│                                    │  /alert-bot.sh   │  _ID, TTY, PPID,     │
│                                    └────────┬─────────┘  CLAUDE_PROJECT_DIR  │
│                                             │ writes one JSON line          │
└─────────────────────────────────────────────┼────────────────────────────────┘
                                              │ AF_UNIX SOCK_STREAM
                                              ▼
┌─────────────────────────── Claude Alert Bot.app (Swift) ─────────────────────┐
│                                                                              │
│  ┌────────────────────┐    HookEvent    ┌────────────────────────────────┐   │
│  │  HookListener      │ ──────────────► │  SessionRegistry               │   │
│  │  (NWListener,      │                 │  - in-flight: [sessionId →     │   │
│  │   AF_UNIX socket)  │                 │      SessionRecord]            │   │
│  └────────────────────┘                 │  - completed-unclicked queue   │   │
│           ▲                             └─────────────┬──────────────────┘   │
│           │                                           │                      │
│           │                                  Stop event over threshold      │
│           │                                           ▼                      │
│           │                             ┌────────────────────────────┐       │
│           │                             │  NotificationOrchestrator  │       │
│           │                             │  - debounce / batching     │       │
│           │                             │  - sound (NSSound, once)   │       │
│           │                             └─────────────┬──────────────┘       │
│           │                                           ▼                      │
│           │                             ┌────────────────────────────┐       │
│           │                             │  FloatingWidgetWindow-     │       │
│           │                             │  Controller (NSPanel)      │       │
│           │                             │  - icon + project name     │       │
│           │                             │  - counter badge / list    │       │
│           │                             └─────────────┬──────────────┘       │
│           │                                  user click │                    │
│           │                                           ▼                      │
│           │                             ┌────────────────────────────┐       │
│           │                             │  iTermBridge               │       │
│           │                             │  NSAppleScript →           │       │
│           │                             │  select session by UUID    │       │
│           │                             └────────────────────────────┘       │
│                                                                              │
│  ┌────────────────────┐   read/write   ┌────────────────────────────────┐   │
│  │  SettingsStore     │ ◄────────────► │  ~/Library/Application Support │   │
│  │  (UserDefaults +   │                │  /ClaudeAlertBot/settings.json │   │
│  │   prefs window)    │                │  /sessions.json (crash recover)│   │
│  └────────────────────┘                └────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────────┘
                                              │ NSAppleScript / osascript
                                              ▼
                                       ┌──────────────┐
                                       │   iTerm2     │  select session whose
                                       │              │  unique ID == UUID,
                                       │              │  bring window to front
                                       └──────────────┘
```

---

## Component Responsibilities

| Component | Responsibility | Implementation | Lives in |
|-----------|----------------|----------------|----------|
| **Reporter** | Serialize Stop/UserPromptSubmit context to JSON, push over Unix socket, exit. Zero UI, zero state, no waiting. | POSIX `sh` (or tiny Swift CLI bundled in app) | Shell, invoked per turn |
| **HookListener** | Owns the `AF_UNIX` socket. Accepts connections, parses one JSON line per connection, hands `HookEvent` to SessionRegistry. | `Network.framework` `NWListener` over `NWEndpoint.unix` | App |
| **SessionRegistry** | Single source of truth for in-flight sessions and the completed-but-unclicked queue. Correlates `start` and `stop` events by `sessionId`. Computes elapsed time. Persists across crashes. | Swift actor, JSON file at `~/Library/Application Support/...` | App |
| **NotificationOrchestrator** | Decides whether a stop event becomes a visible alert. Applies threshold, batching window (~2 s), sound debounce. Hands a render command to the widget. | Plain Swift class, async | App |
| **FloatingWidgetWindowController** | Manages the floating `NSPanel`: show/hide, position, counter badge, expand-to-list, hover/click events. | AppKit `NSPanel` + SwiftUI host view | App |
| **iTermBridge** | Single chokepoint for talking to iTerm2. Given a session UUID (and a TTY fallback), brings the right tab/pane to front. | `NSAppleScript` compiled once, reused. AppleScript permission prompt handled here. | App |
| **SettingsStore** | Threshold, sound on/off, widget anchor corner, mute, "auto-install hook" toggle. | `UserDefaults` + a small JSON for non-defaultable fields; preferences window in SwiftUI | App |
| **HookInstaller** | One-shot helper that edits `~/.claude/settings.json` to add the Stop hook entry, idempotently. Also offers an uninstall. | Swift, JSON5-tolerant parse | App (settings panel) |
| **AppLifecycle** | Login Item registration via `SMAppService` (macOS 13+), single-instance enforcement (kill duplicates), Gatekeeper first-run guidance. | `SMAppService.mainApp` | App |

### Deliberate non-components

- No daemon process separate from the UI app. SwiftUI/AppKit must run on the main thread; a separate `launchd`-launched headless XPC service would only add packaging pain. The App **is** the daemon — it just has no Dock icon (`LSUIElement = YES`) and no menu bar.
- No SQLite. State is small (≤ tens of in-flight sessions), bounded, and fits in a single JSON file written atomically.
- No notification-center fallback path in v1. Requirement explicitly says the widget must persist until clicked; standard `UNNotification` does not satisfy that.

---

## Recommended Project Structure

```
ClaudeAlertBot/
├── App/
│   ├── ClaudeAlertBotApp.swift          # @main, LSUIElement, single-instance check
│   ├── AppDelegate.swift                # Login-item registration, AppleScript prompt timing
│   └── Assets.xcassets                  # Claude icon, app icon, sound
├── Hook/
│   ├── HookListener.swift               # NWListener on AF_UNIX
│   ├── HookEvent.swift                  # Codable struct: start | stop | heartbeat
│   └── SocketPath.swift                 # ~/Library/Caches/ClaudeAlertBot/hook.sock
├── Reporter/
│   └── claude-alert-report.sh           # Shipped inside .app bundle's Resources/;
│                                        # HookInstaller copies/symlinks into ~/.claude/hooks/
├── Sessions/
│   ├── SessionRegistry.swift            # actor, in-flight map + completed queue
│   ├── SessionRecord.swift              # id, projectName, iterm UUID, ttys, startedAt
│   └── SessionStore.swift               # JSON persistence, atomic write
├── Notifications/
│   ├── NotificationOrchestrator.swift   # threshold, batch window, sound dedupe
│   └── SoundPlayer.swift
├── UI/
│   ├── FloatingWidgetWindowController.swift   # NSPanel subclass, level + collectionBehavior
│   ├── FloatingWidgetView.swift               # SwiftUI: icon, project, badge
│   ├── SessionListPopoverView.swift           # expanded view when badge > 1
│   └── PreferencesWindow.swift                # SwiftUI Settings scene
├── iTerm/
│   ├── iTermBridge.swift                # public API: focus(session:), isInstalled()
│   ├── ITerm2AppleScripts.swift         # compiled NSAppleScript snippets, cached
│   └── ITermSessionID.swift             # parses "w0t1p12:UUID"
├── Install/
│   ├── HookInstaller.swift              # patches ~/.claude/settings.json
│   └── SettingsJSONPatcher.swift        # idempotent merge logic
└── Settings/
    ├── SettingsStore.swift              # UserDefaults wrapper with @Published
    └── SettingsModels.swift
```

### Structure rationale

- **Hook/ vs Reporter/:** the listener (Swift, in-process) and the script (shipped artifact) are conceptually one boundary but have very different lifetimes. Splitting them makes "what gets installed into `~/.claude/hooks/`" obvious.
- **Sessions/ as the kernel:** every other module either feeds it (HookListener) or reads from it (Notifications, UI, iTermBridge). Keeping it in its own folder enforces "one source of truth."
- **iTerm/ isolated:** the AppleScript surface is the most fragile part. Concentrating it in one folder lets us swap to the iTerm2 Python API or add WebSocket-based control later without touching the rest.
- **Install/ as a feature, not an afterthought:** auto-registering the hook is a Validated requirement; this module is non-trivial because `~/.claude/settings.json` may already contain user-authored hooks that must be preserved.

---

## Architectural Patterns

### Pattern 1: Stateless edge, stateful core

**What:** The hook script never persists or correlates anything. It captures everything it knows at the moment of firing — `session_id`, `cwd`, `ITERM_SESSION_ID`, `$$` (its own PID), `tty`, `CLAUDE_PROJECT_DIR` — and ships it. The App is the only thing with memory.

**When to use:** Whenever the trigger is a short-lived subprocess (Claude Code hook, Git hook, launchd `OnDemand` job). Stateful hooks accumulate stale lockfiles and sync bugs.

**Trade-offs:** App must be running for events to land. Acceptable here because (a) App is a Login Item, (b) the socket is a connect-and-fail-fast — if the App is down the hook loses ≤ 1 ms and the user simply doesn't get the alert (graceful degradation, no impact on Claude Code itself).

**Sketch:**
```sh
# claude-alert-report.sh — run by Claude Code as the Stop hook
exec >/dev/null 2>&1
read -r STDIN_JSON
SOCK="$HOME/Library/Caches/ClaudeAlertBot/hook.sock"
[ -S "$SOCK" ] || exit 0   # App not running → silent no-op
printf '%s\n' "{
  \"event\":\"stop\",
  \"hookJson\":$STDIN_JSON,
  \"itermSessionId\":\"${ITERM_SESSION_ID:-}\",
  \"tty\":\"$(tty 2>/dev/null)\",
  \"ppid\":$PPID,
  \"projectDir\":\"${CLAUDE_PROJECT_DIR:-}\"
}" | /usr/bin/nc -U "$SOCK" -w 1 || true
```

### Pattern 2: Two-event correlation, not single-shot

**What:** Add a `UserPromptSubmit` hook that fires when the user submits a prompt, emitting `event: "start"` with the same `session_id`. The App pairs `start` → `stop` to compute elapsed time precisely.

**When to use:** Whenever you need a duration but the source of truth gives you only end events. Trying to compute elapsed time from a single `Stop` is impossible — you don't know when the turn began.

**Trade-offs:** Requires installing two hooks instead of one. Worth it: without `start` events you'd be reduced to "alert on every Stop" or guessing from `transcript_path` mtime, both of which fail the 30-second-threshold requirement.

**Fallback:** if only `Stop` is configured (e.g. user manually edited their settings.json and removed the start hook), App falls back to `transcript_path` file size delta or last-modified-time as a coarse duration proxy and flags it in logs.

### Pattern 3: AppleScript by UUID, not by index

**What:** The iTerm2 `ITERM_SESSION_ID` environment variable has format `w0t1p12:<UUID>`. The UUID portion matches AppleScript's `unique ID of session`. We store **only the UUID**, never the `w/t/p` indices.

**When to use:** Always, for iTerm2. Indices shift whenever the user opens/closes/reorders tabs. UUIDs are stable for the life of a pane.

**Trade-offs:** Looking up a session by UUID requires iterating windows × tabs × sessions in AppleScript. For typical user counts (≤ 50 sessions) this is sub-100 ms and runs only on click, so it's fine.

**Sketch:**
```applescript
tell application "iTerm2"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if (unique ID of s) is "{{UUID}}" then
          select t
          select s
          activate
          return
        end if
      end repeat
    end repeat
  end repeat
end tell
```

### Pattern 4: NSPanel, not NSWindow

**What:** Floating widget is an `NSPanel` with `level = .statusBar` (above normal windows but below system alerts), `collectionBehavior = [.canJoinAllSpaces, .stationary]`, `isFloatingPanel = true`, and `becomesKeyOnlyIfNeeded = true`.

**When to use:** Any always-on-top, doesn't-steal-focus UI on macOS.

**Trade-offs:** `NSPanel` cannot host modal sheets cleanly. Fine for a click-target widget; if we ever wanted dropdowns inside it, switch to `.popover` or move complex UI to a separate window.

---

## Session Identity — The Critical Decision

This is the single most consequential design choice and deserves its own section.

### Goal

Given a Stop event from Claude Code, recover the iTerm2 tab that hosts the `claude` process — even when (a) the user has 5 concurrent sessions, (b) tabs have been reordered since `claude` started, and (c) the `claude` process forked and the immediate PPID isn't iTerm2.

### Candidates evaluated

| Mechanism | What it gives us | Reliability | Cost |
|-----------|------------------|-------------|------|
| **A. `ITERM_SESSION_ID` env var read in the hook** | `w0t1p12:UUID`. The UUID half maps 1:1 to iTerm2's AppleScript `unique ID`. | **HIGH.** Set by iTerm2 on shell launch; inherited by every child including `claude`; survives tab reorder. | Zero — already in `environ` |
| **B. PPID walking up to iTerm2's tab/server process** | A process tree path to iTerm2 | LOW–MEDIUM. iTerm2 uses a single per-app server process; siblings are indistinguishable. PPID may be a wrapper (tmux, fish, asdf) | Cheap but brittle |
| **C. TTY (`$(tty)`) matched against AppleScript `tty of session`** | Pseudo-terminal path like `/dev/ttys003` | MEDIUM. Stable for the session, queryable from AppleScript. Unique per pane. | Cheap |
| **D. Claude's `session_id` from stdin JSON** | A Claude session UUID | N/A for terminal mapping — Claude doesn't know which terminal it lives in. Useful only as our own correlation key. | Free |
| **E. `cwd` from stdin JSON or `CLAUDE_PROJECT_DIR`** | Absolute path of the project | Useful for the **display label** but not unique — two tabs in the same repo collide. | Free |

### Recommendation: A (primary) + C (fallback) + D (correlation key)

**Primary mechanism:** parse `ITERM_SESSION_ID`, take everything after the colon, treat that UUID as the iTerm2 identity. Store it on the `SessionRecord`.

**Fallback mechanism:** if `ITERM_SESSION_ID` is unset (user disabled iTerm2 Shell Integration, or runs `claude` inside a `tmux` that wasn't launched from iTerm2), fall back to the TTY captured by the hook. iTerm2 AppleScript exposes `tty of session`, so we can still find the right pane — just slower.

**Internal correlation:** Claude's `session_id` is the key the App uses to match `start` events to `stop` events. It is **not** used to find the terminal.

**Display label:** derive the project name from `basename(cwd)` (or `CLAUDE_PROJECT_DIR`). Show this on the widget.

### Why not PPID walking

iTerm2 (since the v3 server architecture) hosts all panes under a single `iTerm2` process via its `iTerm2Server` helper. PPID-walking from the `claude` process leads to a shell, then to that shared server — which gives us "this came from iTerm2" but **not which tab**. PPID alone cannot disambiguate concurrent sessions, which directly violates the Core Value ("정확한 그 세션으로의 점프"). Reject.

### Why this is robust

- **Tab reorder:** UUIDs don't change. ✅
- **`claude` exits and is restarted in same tab:** new shell child still inherits the same `ITERM_SESSION_ID` because iTerm2 sets it once per pane. ✅
- **User splits a pane mid-task:** new pane gets a new UUID; existing in-flight session keeps the original UUID — correct behavior. ✅
- **User closes the tab while task is running:** UUID lookup fails on click. iTermBridge surfaces a friendly error ("That terminal is gone — its project was X") instead of opening a random tab. ✅
- **tmux inside iTerm2:** `ITERM_SESSION_ID` is exported by iTerm2's shell integration and survives tmux child processes if the user attaches/detaches without re-launching tmux from outside iTerm2. ⚠️ Edge case: tmux session persisted across iTerm2 restarts. The TTY fallback handles new attachments; the original UUID becomes stale. Document this as a known limitation in PITFALLS.

---

## Data Flow — End-to-End on a Stop Event

```
T+0   user starts a Claude turn in iTerm2 tab (UUID=ABC)
       │
       │  UserPromptSubmit hook fires
       ▼
T+1ms Reporter reads stdin JSON {session_id: S1, cwd: /repo/foo, ...},
       reads ITERM_SESSION_ID env (=w0t1p3:ABC), tty (=/dev/ttys004),
       writes one JSON line to AF_UNIX socket, exits.
       │
       ▼
T+2ms HookListener.NWListener accepts, parses, hands HookEvent.start to
       SessionRegistry.
       │
       ▼
T+3ms SessionRegistry creates SessionRecord{
         claudeSessionId: S1,
         itermUUID: ABC,
         tty: /dev/ttys004,
         projectName: "foo",
         startedAt: T+0,
         status: .inFlight
       } and persists sessions.json atomically.
       │
       ▼
       ... user walks away ...
       │
T+47s Claude finishes its turn → Stop hook fires.
       │
       ▼
T+47s+1ms Reporter ships HookEvent.stop with same session_id=S1.
       │
       ▼
T+47s+2ms SessionRegistry looks up S1, computes elapsed = 47s,
       moves record to .completedUnclicked, hands it to
       NotificationOrchestrator.
       │
       ▼
T+47s+3ms NotificationOrchestrator checks elapsed (47 ≥ threshold 30) ✓.
       Opens a 2-second batching window in case other sessions also
       finish (debounce). After window closes:
       │
       ▼
T+49s  NotificationOrchestrator asks FloatingWidgetWindowController
       to render. If queue length == 1 → single-session widget with
       project name "foo". If > 1 → counter-badge widget.
       Plays sound once via SoundPlayer.
       │
       ▼
T+49s  NSPanel.orderFrontRegardless(); panel level=.statusBar,
       collectionBehavior includes .canJoinAllSpaces.
       │
       │ ... time passes, widget remains visible ...
       │
T+Xs  user clicks widget.
       │
       │  case A (queue size 1):
       ▼
       FloatingWidgetWindowController emits .didSelect(record)
       → SessionRegistry marks record .clicked, removes from queue
       → iTermBridge.focus(itermUUID: ABC, ttyFallback: /dev/ttys004)
       │
       │  case B (queue size > 1):
       ▼
       Widget expands to SessionListPopoverView. User picks one.
       Same flow as A for the chosen record. Other records stay
       in queue; widget collapses back to the badge with N-1.
       │
       ▼
T+Xs+5ms iTermBridge runs cached NSAppleScript:
         tell application "iTerm2" to activate
         …iterate windows/tabs/sessions, find unique ID == ABC,
           select tab, select session.
         If not found → fall back: find session whose tty == /dev/ttys004.
         If still not found → show transient error ("That terminal closed").
       │
       ▼
T+Xs+50ms iTerm2 brings window forward, focuses tab and pane.
       Widget hides if queue is now empty.
```

### State persistence flow

`SessionRegistry` writes `sessions.json` after every mutation. On App relaunch:
- `.inFlight` records older than N hours (configurable, default 6) are dropped — they are almost certainly leftovers from a kill -9.
- `.completedUnclicked` records are restored and re-rendered. The user explicitly requested no auto-dismiss, so a restart should not erase pending alerts.

---

## Concurrency & Race Conditions

The "near-simultaneous Stop events" requirement creates several real races. Each is enumerated and handled.

### Race 1: Two stops within the same millisecond

Two `claude` processes finish at the same wall-clock instant. Both `nc -U` the socket.

**Resolution:** `NWListener` accepts each connection on its own queue; `HookEvent` decoding is independent. SessionRegistry is a Swift `actor`, so its `record(stop:)` calls serialize automatically. No data race.

### Race 2: Stop arrives before Start

The user already had a `claude` turn in progress when the App was first launched (so the App missed the `start` event). Then `Stop` fires.

**Resolution:** SessionRegistry treats an unknown `session_id` on a stop as "elapsed = unknown." NotificationOrchestrator policy: alert anyway, with a "?" instead of a duration. Better to over-alert once than miss the first completion after install.

### Race 3: Click during render of new entry

User clicks the widget at the exact moment another stop event is being added.

**Resolution:** All click handling and registry mutation flow through the actor. The click message takes a snapshot of the queue; if the queue grew between snapshot and AppleScript dispatch, the new entry simply remains in the queue and the widget re-renders the new badge count when control returns.

### Race 4: AppleScript call takes longer than expected

iTerm2 is unresponsive (e.g., user has a modal dialog open in iTerm2). AppleScript blocks for seconds.

**Resolution:** iTermBridge runs every AppleScript on a dedicated serial dispatch queue with a hard 3-second timeout. On timeout: surface error, leave the record in the queue so the user can retry. Never block the main thread with `NSAppleScript.executeAndReturnError` — always trampoline to a background queue, return result via async continuation.

### Race 5: Same session generates multiple Stops

Claude's `stop_hook_active` infinite-loop guard means Stop can fire twice for one logical turn.

**Resolution:** SessionRegistry deduplicates by `(claudeSessionId, stoppedAt-rounded-to-second)`. A stop arriving for a session already in `.completedUnclicked` is ignored.

### Race 6: Hook fires while App is starting up

App is mid-launch; the socket isn't listening yet.

**Resolution:** Hook script tolerates `connect()` failure as a no-op (`|| true`). One missed event is acceptable; the App will catch the next one. Optional polish: have the App, on launch, scan recent `transcript_path` mtimes and synthesize stop events for any Claude session that has finished but isn't in `sessions.json` — only if its mtime is within the last 60 s.

---

## Scaling Considerations

This is a single-user desktop app, so "scaling" means concurrent in-flight Claude sessions on one Mac.

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1–5 concurrent sessions (typical) | No adjustment. Linear iteration over registry, single panel widget. |
| 5–20 concurrent sessions | List popover for the badge becomes essential (already designed). AppleScript loop time still under 100 ms. |
| 20–50 concurrent sessions | Cache compiled `NSAppleScript` once per app launch; do not recompile per click. Already the plan. Memory cost ~ a few KB per record — trivial. |
| 50+ sessions | Almost certainly indicates a leak (stale `.inFlight` records). Garbage-collect records older than 6 h on every registry mutation. |

### First bottleneck if it ever became a real concern

AppleScript round-trip latency for the focus operation. Mitigation path: switch iTermBridge from `NSAppleScript` to iTerm2's Python API over its WebSocket (gRPC-ish). Defer until measured.

---

## Anti-Patterns (specific to this domain)

### Anti-pattern 1: Storing the iTerm2 window/tab/pane indices

**What people do:** Capture `w0t1p3` from `ITERM_SESSION_ID` and use indices for AppleScript lookup.
**Why wrong:** Indices shift on tab open/close/reorder. The widget will silently focus the wrong tab.
**Do this instead:** Use only the UUID portion. Store `tty` as fallback.

### Anti-pattern 2: A long-running AppleScript "watcher" inside iTerm2

**What people do:** Use the iTerm2 Python API's persistent connection to watch sessions and push events back.
**Why wrong:** Adds a second source of truth that drifts from Claude's hook events. Doubles the failure modes.
**Do this instead:** AppleScript is **only** invoked on click. Source of truth for "what's running" is the hook stream.

### Anti-pattern 3: Making the hook block on App acknowledgment

**What people do:** Hook waits for the App to confirm receipt before exiting, so events are guaranteed delivered.
**Why wrong:** Slows every Claude turn end. If the App is unresponsive, blocks Claude itself.
**Do this instead:** Fire-and-forget over the socket. Lose the event silently if the App is down.

### Anti-pattern 4: Using `UNUserNotificationCenter` as the widget

**What people do:** Use the macOS notification banner because it's "the standard."
**Why wrong:** macOS auto-dismisses banners. The Core Value explicitly requires persistence-until-clicked.
**Do this instead:** Custom `NSPanel`. Notification center is not in scope.

### Anti-pattern 5: Polling the hook socket file from the App

**What people do:** Periodically `stat` a status file written by the hook.
**Why wrong:** Latency; missed events between polls; needs file locking.
**Do this instead:** `NWListener` on a Unix domain socket — push, not pull.

### Anti-pattern 6: Letting the Settings UI mutate `SessionRegistry` directly

**What people do:** Settings panel reaches into the registry to clear records.
**Why wrong:** Couples user-facing config to runtime state; surprise side effects.
**Do this instead:** Settings emits intent (`registry.clearAll()`); registry validates and acts. One owner per state.

---

## Integration Points

### External services (local processes)

| Service | Integration Pattern | Notes / Gotchas |
|---------|---------------------|-----------------|
| Claude Code | Stop + UserPromptSubmit hooks → shell script → AF_UNIX socket → App | Hooks must be registered in `~/.claude/settings.json`. HookInstaller does this idempotently. Stop hook receives JSON via stdin (fields: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, plus `stop_hook_active`). `CLAUDE_PROJECT_DIR` is set in env. |
| iTerm2 | `NSAppleScript` (via `iTermBridge`); fallback to `osascript` subprocess if `NSAppleScript` fails inside hardened-runtime | First call triggers macOS Automation permission dialog. Pre-warm at app launch with a no-op script (`tell app "iTerm2" to get name`) so the dialog appears at install time, not at the user's first click. |
| macOS LaunchServices / SMAppService | Login Item registration | `SMAppService.mainApp.register()` (macOS 13+). Earlier: `SMLoginItemSetEnabled` (deprecated). PROJECT.md targets macOS 13+ so use `SMAppService`. |

### Internal boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Reporter ↔ HookListener | One-way JSON line over `AF_UNIX SOCK_STREAM` | Length-prefix not needed; one connection = one message; close = EOF. |
| HookListener → SessionRegistry | Direct async call to actor | HookListener decodes; registry validates. |
| SessionRegistry → NotificationOrchestrator | AsyncStream of `SessionEvent` | Decouples persistence from UI policy. |
| NotificationOrchestrator → FloatingWidgetWindowController | `@MainActor` method call | UI mutations on main thread only. |
| FloatingWidgetWindowController → SessionRegistry | Click event with `claudeSessionId` | Widget never holds records by reference — only by ID, so registry can mutate freely. |
| Anything → iTermBridge | `func focus(itermUUID: String, ttyFallback: String?) async throws` | Single function. Hides AppleScript entirely. |
| SettingsStore → others | Combine `@Published` properties + UserDefaults | Threshold change must immediately re-evaluate `.completedUnclicked` queue (records that were below the old threshold but above the new one would otherwise stay hidden). |

---

## Build Order Implications

The roadmap should respect these dependencies. Each phase listed assumes the previous one works end-to-end (`/gsd-transition` boundary).

### Phase 1: Hook → App → log

Goal: a Stop event in Claude Code lands as a log line in the App.
- Reporter shell script (just `event` + `session_id` + `cwd`)
- HookListener over AF_UNIX
- Bare-bones App skeleton (LSUIElement, no UI), prints to OSLog
- HookInstaller v0 (manual JSON edit guidance, automation later)

**Why first:** every other component depends on receiving events. Without this, nothing can be tested with real data.

### Phase 2: SessionRegistry + threshold + minimal widget

Goal: when a Claude turn exceeds 30 s, an NSPanel appears showing the project name. Click dismisses.
- Add UserPromptSubmit hook for start events
- SessionRegistry with persistence
- NotificationOrchestrator (threshold + sound)
- FloatingWidgetWindowController (single-session form, no badge)

**Why second:** validates the elapsed-time correlation pattern with real Claude sessions before adding terminal-targeting complexity.

### Phase 3: iTermBridge + UUID lookup

Goal: clicking the widget jumps to the correct iTerm2 tab.
- Capture `ITERM_SESSION_ID` in Reporter
- Store UUID in SessionRecord
- iTermBridge AppleScript
- TTY fallback path
- AppleScript permission pre-warm

**Why third:** this is the riskiest piece (Apple permission flow, AppleScript correctness, tab-not-found edge cases). Build it after the basic alert loop is proven.

### Phase 4: Multi-session UX

- Counter badge widget
- Expanded list popover
- Batching window (2 s) in NotificationOrchestrator
- Settings UI for threshold / sound / position

### Phase 5: Distribution polish

- HookInstaller automated patch of `~/.claude/settings.json`
- Login Item registration via SMAppService
- DMG packaging
- README with Gatekeeper bypass instructions

### Critical insight: defer iTerm2 work

A common mistake would be to build iTermBridge first because it's the visible "wow" feature. Don't. The hook-→-App pipeline is the spine; the widget is the face; the iTerm2 jump is the punchline. In that order.

---

## Sources

- [Claude Code Hooks Reference (official)](https://code.claude.com/docs/en/hooks) — stdin JSON fields (`session_id`, `transcript_path`, `cwd`, `hook_event_name`), `CLAUDE_PROJECT_DIR` env var, `stop_hook_active` semantics — **HIGH** confidence, primary source.
- [iTerm2 Variables Documentation](https://iterm2.com/documentation-variables.html) — `termid` and `TERM_SESSION_ID` env var existence; session `id` as unique identifier.
- [iTerm2 AppleScript Documentation](https://github.com/gnachman/iterm2-website/blob/master/source/_includes/documentation-applescript.md) — `unique ID` property of session; iteration pattern for lookup; note that AppleScript "is no longer receiving improvements" (still functional, but motivates Python API as future migration).
- [iTerm2-discuss thread on session navigation](https://groups.google.com/g/iterm2-discuss/c/VXZiw3dbReQ) — historical confirmation that index-based addressing is unreliable; UUID approach is the recommended replacement (developer's own note).
- [Apple `SMAppService` documentation](https://developer.apple.com/documentation/servicemanagement/smappservice) — login item registration on macOS 13+.
- [Apple `Network` framework / `NWListener` over Unix domain socket](https://developer.apple.com/documentation/network/nwlistener) — modern replacement for `BSD socket` boilerplate.

### Confidence inventory

| Claim | Confidence | Why |
|-------|------------|-----|
| Stop hook delivers `session_id`, `cwd`, `transcript_path` via stdin JSON | HIGH | Official docs verified |
| `CLAUDE_PROJECT_DIR` env var is set during hooks | HIGH | Official docs verified |
| `ITERM_SESSION_ID` format `wXtYpZ:UUID`, UUID matches AppleScript `unique ID` | MEDIUM-HIGH | Confirmed in iTerm2 docs and discuss thread; not double-checked against current iTerm2 source. Validate during Phase 3 with a 5-line probe script. |
| AF_UNIX SOCK_STREAM is the right IPC choice | HIGH | Standard pattern; no permission entitlements needed; tolerant to App-not-running |
| `NSPanel` with `.statusBar` level + `canJoinAllSpaces` gives correct floating behavior | HIGH | Standard AppKit pattern, widely used |
| AppleScript `unique ID` query latency is acceptable | MEDIUM | Should be sub-100 ms for ≤ 50 sessions; not measured. Phase 3 should benchmark. |
| iTerm2 Shell Integration sets `ITERM_SESSION_ID` automatically without extra setup | MEDIUM | True when shell integration is installed (default since iTerm2 v3.2 with explicit installation step). PITFALLS.md should flag the "user disabled shell integration" case. |

---

*Architecture research for: macOS native floating-widget companion + Claude Code Stop hook + iTerm2 session targeting*
*Researched: 2026-05-07*
