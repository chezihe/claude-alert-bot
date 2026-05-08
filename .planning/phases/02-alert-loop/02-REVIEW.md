---
phase: 2
status: warnings
critical: 0
warnings: 6
info: 7
reviewed: 2026-05-08
depth: standard
---

# Phase 2 Code Review — Alert Loop

## Summary

Phase 2 is in solid shape — the high-leverage invariants the plan called out (Pitfall #11 boot ordering, observer/timer retention, AppleScript compile-once + serial queue, NSPanel collection-behavior triple, AUD-02 sound gating, atomic `sessions.json` save with corrupt-rename fallback) are all implemented and explicitly tested. The actor-isolated `SessionRegistry` plus `@MainActor`-isolated UI surface gives a clean single-direction data flow. No security holes (envelope size cap, schema gate, file 0600/dir 0700, no AppleScript string interpolation) and no `NSApp.activate(ignoringOtherApps:)` regressions in the App/ tree.

The findings below are mostly correctness edge-cases and lifecycle leaks rather than blockers: an unbounded `dedupeSet` that grows for the lifetime of the process, a Sound-gating double-check that subtly disagrees with `D2-20` (sound-only dedupe scope), a couple of `Task` fire-and-forget paths whose cancellation/retry behavior is undefined, plus a stale comment-vs-code drift around `bind(widget:)`. None block shipping; all should be tracked.

## Critical

None.

## Warning

### WR-01: `dedupeSet` grows unboundedly inside the actor

**File:** `App/SessionRegistry.swift:30, 97-98`
**Issue:** `dedupeSet: Set<DedupeKey>` only ever has `.insert()` called on it; no eviction path exists in `runGC`, `clearOne`, `clearAll`, or `restore`. Every Stop event (even those that were dedupe-suppressed, or below threshold-but-dedupe-checked) adds a permanent entry. For a long-running menu-bar app that fires across days/weeks of Claude sessions, this is an ever-growing set held inside a long-lived actor — a slow leak that survives GC ticks. The 2-second bucketed key bounds the rate but not the total.
**Fix:** Drop entries from `dedupeSet` whenever the corresponding session ages out of `completed`, or simpler — purge keys older than (e.g.) 6h inside `runGC`. Concrete:
```swift
func runGC(now: Date? = nil) async {
    let n = now ?? clock.now()
    let sixHours: TimeInterval = 6 * 3600
    // existing inFlight prune ...
    let cutoffBucket = Int(n.addingTimeInterval(-sixHours).timeIntervalSince1970) / 2
    dedupeSet = dedupeSet.filter { $0.bucketedTS >= cutoffBucket }
    // existing persist ...
}
```

### WR-02: Sound is double-gated against `SettingsStore.soundEnabled` — diverges from D2-20 contract

**File:** `App/NotificationOrchestrator.swift:71`, `App/SessionRegistry.swift:127`
**Issue:** `SessionRegistry.handleStop` already computes `playSoundOnce: soundEnabled && !isDup` (line 127) using the `soundEnabled` flag passed via `ingest`. Then `NotificationOrchestrator.present` re-reads `SettingsStore.shared.soundEnabled` and AND-gates it again (line 71). If the user toggles `soundEnabled` between registry-side decision and orchestrator-side present, the second gate wins — but more importantly, this hides the "registry already dedupe-decided" intent and means the AUD-01 dedupe (sound-only scope per D2-20) will be silently overridden if the toggle goes from off→on between the two points. The unit tests pass because they set `SettingsStore.shared.soundEnabled` once at the top of each test, masking the inconsistency.
**Fix:** Pick one authoritative gate. Recommended: registry computes the final boolean and orchestrator just obeys, removing the second `SettingsStore` read at present-time:
```swift
// NotificationOrchestrator.present
if playSoundOnce {
    sound.playOnce()
    log.notice("present session=\(session.sessionID, privacy: .public) sound=on")
} else {
    log.notice("present session=\(session.sessionID, privacy: .public) sound=off")
}
```
…and delete the `settings: () -> SettingsStore` injection (it has no other use). Update `test_present_skipsSound_whenSoundDisabled_AUD_02` to assert that `SessionRegistry` is the gating layer — pass `soundEnabled: false` through `ingest` and assert no `present` sound call.

### WR-03: `injectTest` auto-dismiss `Task` accumulates on rapid retries; no cancellation

**File:** `App/SessionRegistry.swift:174-177`
**Issue:** Each `injectTest` spawns an unstructured `Task { try? await clock.sleepNanoseconds(30 * 1_000_000_000); await self?.clearOne(...) }`. If the user mashes the "테스트 알림 보내기" button repeatedly, N concurrent dismiss tasks arrive 30s later, each racing to `clearOne` distinct test IDs (so functionally OK), but the tasks are unbounded and uncancellable. More subtly: if the user clicks the popover row to clear a test alert manually (D2-08 path), the auto-dismiss task still fires 30s later and its `clearOne(sessionID: sid)` is a no-op against an already-empty queue — fine, but logged as `clearOne ...` which clutters telemetry.
**Fix:** Track the task in a property and cancel a previous one before spawning the next; or guard the `clearOne` call with a "still present" check inside the actor.

### WR-04: `WorkspaceFrontmostObserver` triggers serial AppleScript queries per pending alert

**File:** `App/WorkspaceFrontmostObserver.swift:38-47`
**Issue:** `evaluatePendingAlerts` loops over `pending` and `await`s `frontmostMatches` for each one. Each call hits the serialized AppleScript queue (1s upper bound). With N pending sessions you serialize N × up-to-1s of AppleScript calls every time iTerm2 becomes frontmost. The frontmost session can only be one tab/session — once you find a match and `clearOne`, you can break. Also: every iteration re-runs the same AppleScript ("get id of current session…") returning the same string until iTerm2 changes — so this does N redundant queries.
**Fix:** Run the cheap-query once, then compare its result to all pending sessions in-process:
```swift
private func evaluatePendingAlerts() async {
    let pending = await SessionRegistry.shared.peekPending()
    let targets = pending.compactMap { $0.itermSessionID }
    guard !targets.isEmpty else { return }
    // One AppleScript call gets the current frontmost id; match in Swift.
    for s in pending {
        guard let target = s.itermSessionID else { continue }
        if await AppleScriptHelper.shared.frontmostMatches(itermSessionID: target) {
            await SessionRegistry.shared.clearOne(sessionID: s.sessionID)
            return  // only one frontmost session can match
        }
    }
}
```
…or expose a `currentFrontmostID() async -> String?` on the helper and do all comparisons in Swift after one call.

### WR-05: `HookListener.handle` decode-error path silently drops connections without metrics

**File:** `App/HookListener.swift:120-122`
**Issue:** A malformed envelope (typo, partial JSON, schema-version mismatch on line 88) is logged and dropped. There is no per-connection counter, no retry, no notification to the user. In a hook-misconfiguration scenario the user sees "no alerts" with zero feedback. The same applies to the `> 64KB` cap (line 67-71) and to `event.schema_version != 1` (line 88-91). For a self-distributed tool, this risks "silent failure" complaints with no triage path.
**Fix:** Bump these to `.error`-level OSLog and include the first 200 bytes of the buffer (already privacy-classed appropriately at `.private`). Also consider an in-app counter exposed in Settings as a dev aid (out of v1 scope). Minimum recommended change:
```swift
log.error("decode failed (size=\(buffer.count)): \(String(describing: error), privacy: .public). first 200B=\(String(data: buffer.prefix(200), encoding: .utf8) ?? "<binary>", privacy: .private)")
```

### WR-06: `WidgetPopoverController.showPopover` rebuilds `NSHostingController` on every hover

**File:** `App/WidgetPopoverController.swift:60-67`
**Issue:** Every entry into `showPopover` (every 150ms-confirmed hover) constructs a fresh `NSHostingController` and assigns it to `pop.contentViewController`. This destroys SwiftUI state — `@State private var isHovered` in `PopoverRowView` resets each time. Because the popover is short-lived (transient) this is mostly invisible, but if the user is hovering, the row becomes hovered, and re-entering during exit grace re-builds — the row hover state flickers. More importantly, repeated NSHostingController churn during fast hover cycles allocates and tears down SwiftUI graphs on the hot path.
**Fix:** Build the hosting controller once and update its `rootView` on subsequent shows (mirrors `FloatingWidgetWindowController.updateRootView`):
```swift
private var hosting: NSHostingController<PopoverContentView>?
// in showPopover:
if let h = hosting {
    h.rootView = content
} else {
    let h = NSHostingController(rootView: content)
    hosting = h
    pop.contentViewController = h
}
```

## Info

### IN-01: Stale comment on `NotificationOrchestrator.bind(widget:)` wiring

**File:** `App/NotificationOrchestrator.swift:16-17, 62-64`
**Issue:** Class-level comment claims "AppDelegate (Wave 6 / 02-11) wires the concrete controller via `bind(widget:)` after construction". `AppDelegate.swift:60` actually uses the `convenience init(widget:)` directly and never calls `bind(widget:)`. The `bind(widget:)` method is dead code in the production path (still useful for tests). Either remove `bind(widget:)` or fix the comment to read "two-phase wire is supported via bind(widget:); production currently uses the eager convenience init".
**Fix:** Update comment.

### IN-02: `becomesKeyOnlyIfNeeded = true` is redundant given `canBecomeKey { false }`

**File:** `App/FloatingWidgetPanel.swift:15, 26`
**Issue:** With `canBecomeKey` overridden to return false, `becomesKeyOnlyIfNeeded` has no observable effect. Harmless but the comment "WIDG-02" suggests it's part of the contract — consider deleting one or the other to reduce confusion.
**Fix:** Pick one; the override on line 26 is the stronger guarantee, so the line-15 setter is the candidate to drop.

### IN-03: `PopoverContentRules.timeSuffix` allocates a new `DateFormatter` per call

**File:** `App/PopoverContentView.swift:24-28`
**Issue:** `DateFormatter` is expensive to instantiate. Called once per duplicate-project row each time the popover renders. Performance is out of v1 scope, but a single `static let formatter` cache is trivially safer.
**Fix:**
```swift
private static let hhmmFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "HH:mm"
    return f
}()
static func timeSuffix(for date: Date) -> String { hhmmFormatter.string(from: date) }
```

### IN-04: `WidgetPopoverController` empty-queue guard missing

**File:** `App/WidgetPopoverController.swift:49-76`
**Issue:** `showPopover` does not early-return when `queue` is empty. With `max(1, queue.count)` the body is still 36pt tall, the ForEach renders nothing. Visually a 280×36 empty translucent strip. Should never happen in practice (orchestrator hides the widget at count=0), but a defensive `guard !queue.isEmpty else { return }` would harden the contract.
**Fix:** Add the guard at the top of `showPopover`.

### IN-05: `parseTS` constructs a new `ISO8601DateFormatter` per call

**File:** `App/SessionRegistry.swift:189-193`
**Issue:** Same DateFormatter cost issue as IN-03. Called twice per ingest (start and stop). A static instance shaves microseconds and is a one-line change.
**Fix:**
```swift
private static let isoFormatter = ISO8601DateFormatter()
private func parseTS(_ s: String?) -> Date? {
    guard let s = s else { return nil }
    return Self.isoFormatter.date(from: s)
}
```

### IN-06: Test fixture emits empty-string for nil `cwd`/`iterm_session_id`, not `null`

**File:** `ClaudeAlertBotTests/Fixtures/HookEventFactory.swift:16`
**Issue:** `"cwd":"\(cwd ?? "")"` produces `"cwd":""` when caller passes `nil`. `HookEvent.cwd` is `String?` and the JSON parser accepts both `""` and `null`. Downstream `ProjectName.derive` treats `""` as "skip" via the `!s.isEmpty` check, so it works — but the fixture is lying about the wire format. If a future change to `ProjectName` switches to `s != nil` instead of `!s.isEmpty`, tests will pass while production breaks. Replace with proper JSON null.
**Fix:** Build the dictionary with `JSONSerialization` or use a string-builder that emits `null` for `nil`:
```swift
let cwdJSON = cwd.map { "\"\($0)\"" } ?? "null"
let json = """{"...":..., "cwd":\(cwdJSON), ...}"""
```

### IN-07: `installSignalHandler` only handles SIGTERM/SIGINT, ignores SIGHUP

**File:** `App/AppDelegate.swift:101-102, 154-165`
**Issue:** Phase 1 carryover. SIGHUP is the conventional "config reload / parent died" signal. For a daemon-style menu-bar app receiving SIGHUP from launchd in some restart scenarios, the lack of a handler means default action (terminate without socket cleanup) — leaving stale socket file. Low probability but easy to harden.
**Fix:** Add `installSignalHandler(SIGHUP)` next to SIGTERM/SIGINT.

## Verified-clean callouts

- **Pitfall #11 ordering correct.** `AppDelegate.swift:52-98` — the `Task { @MainActor in ... await SessionRegistry.shared.restore(); ...; try l.start() }` block guarantees `restore()` completes before `listener.start()`. The DispatchSource signal handlers are correctly retained in `signalSources` array (line 164) — Phase 1 institutional comment preserved.
- **NSPanel collection behavior triple set correctly.** `FloatingWidgetPanel.swift:14` — `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` matches RESEARCH Pattern 7 and Pitfall #1. Tests assert all three flags present (`FloatingWidgetPanelTests.test_collectionBehavior_threeFlagsPresent`).
- **AppleScript compile-once + serial queue + 1s timeout.** `AppleScriptHelper.swift:24, 31-38, 42-47` — dedicated `com.claudealert.bot.applescript` queue, `with timeout of 1 second` AppleScript-side hard timeout, `compileAndReturnError(nil)` once, classification function pure-tested. No `target` interpolation into AppleScript source — match is in Swift (T-INJECTION-01 mitigated).
- **No `NSApp.activate(ignoringOtherApps:)` in App/.** `grep -rn 'activate(ignoringOtherApps' App/` returns zero hits. LSUIElement invariant preserved per D2-29.
- **`@MainActor` discipline.** All AppKit-touching surfaces (`SettingsStore`, `NotificationOrchestrator`, `FloatingWidgetWindowController`, `WidgetPopoverController`, `SessionGCTimer`, `WakeObserver`, `WorkspaceFrontmostObserver`) are explicitly `@MainActor`-isolated. `SessionRegistry` and `SessionStore` actors stay off main thread for I/O and state mutation.
- **Observer retention.** `WakeObserver.token`, `WorkspaceFrontmostObserver.token`, `SessionGCTimer.source`, and `AppDelegate.signalSources` all retain their underlying observer/source — every relevant file carries the `CRITICAL: retain` comment as a regression guard, verified by `verify_2_09_01`'s grep.
- **Sessions.json security.** `SessionStore.swift:28-33` writes atomically and chmods to 0600; parent dir 0700 from `AppDelegate.ensureDirectories`. `test_save_setsFile_0600_perms` enforces.
- **Schema-version gate at IPC ingress.** `HookListener.swift:88-91` rejects unknown `schema_version`, and `SessionStore.swift:51-55` renames-and-bails on schema mismatch — both forward-compat hardening points are tested (`test_load_schemaMismatch_renamesAndReturnsNil`).
- **AppDelegate stale-socket reclaim guards against double `group.leave`.** `AppDelegate.swift:128-141` — explicit `leftOnce` flag prevents libdispatch crash on repeated `.failed/.cancelled/.waiting` callbacks.

---

_Reviewed: 2026-05-08_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
