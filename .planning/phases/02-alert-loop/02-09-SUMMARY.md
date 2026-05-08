---
phase: 02-alert-loop
plan: 09
status: complete
completed: 2026-05-08
duration_minutes: 6
requirements: [SESS-04]
tags: [phase-2, wave-4, observers, gc, lifecycle, dispatchsource]
files_created:
  - App/WakeObserver.swift
  - App/WorkspaceFrontmostObserver.swift
  - App/SessionGCTimer.swift
  - ClaudeAlertBotTests/SessionGCTimerTests.swift
files_modified:
  - ClaudeAlertBot.xcodeproj/project.pbxproj
key_decisions:
  - "WakeObserver takes injected onWake closure — Wave 6 wires Task { await SessionRegistry.shared.runGC() } at construction site (matches AppDelegate's signalSources injection style; preserves observer testability without coupling to actor)"
  - "WorkspaceFrontmostObserver gates on bundle ID com.googlecode.iterm2 BEFORE invoking AppleScriptHelper (T-FRONTMOST-SPAM-01) — prevents AppleScript spam on every Cmd-Tab"
  - "SessionGCTimer.start() schedules first fire at .now() + interval (deferred), not .now() — production behavior is 'first GC happens 30 min after boot', not 'on boot'; lazy ingest GC + WakeObserver cover the boot moment"
  - "SessionRegistry.peekPending() was already shipped by 02-04 (verified in 02-04 SUMMARY line 72; no patch needed in 02-09)"
---

# Plan 02-09 SUMMARY — Wave 4 Lifecycle Observers + GC Timer

## What Shipped

Wave 4 second half — the three lifecycle components that complete SESS-04's three-trigger GC pattern (RESEARCH Pattern 6) and D2-15's NSWorkspace activate-driven auto-clear. All three follow the institutional `[weak self]` + retained-token/source pattern from PATTERNS.md (Phase 1 `signalSources` lineage at `App/AppDelegate.swift:16,96-105`).

| File | Role | Status |
|------|------|--------|
| `App/WakeObserver.swift` | NSWorkspace.didWakeNotification observer; fires injected `onWake()` closure on wake | Created |
| `App/WorkspaceFrontmostObserver.swift` | NSWorkspace.didActivateApplicationNotification observer; D2-15 auto-clear on iTerm2 frontmost | Created |
| `App/SessionGCTimer.swift` | DispatchSourceTimer wrapper; default 30-min; retained source; cancel + deinit symmetric | Created |
| `ClaudeAlertBotTests/SessionGCTimerTests.swift` | 4 unit tests (construction, fires-at-interval, cancel-stops, retention) | Created |

**Atomic commits on master:**
- `116cdb9` — `feat(02-09): WakeObserver + WorkspaceFrontmostObserver (SESS-04 + D2-15)` (Task 1, no-TDD per plan)
- `d53931c` — `test(02-09): add failing SessionGCTimerTests (TDD RED)` (Task 2 RED gate)
- `bd7bdc0` — `feat(02-09): SessionGCTimer DispatchSourceTimer wrapper (SESS-04)` (Task 2 GREEN gate)

## Public API Surface (Wave 6 wiring contract — do not re-read source)

```swift
@MainActor
final class WakeObserver {
    init(onWake: @escaping () -> Void)   // Wave 6: pass `{ Task { await SessionRegistry.shared.runGC() } }`
    deinit                                // Removes NSWorkspace observer token
}

@MainActor
final class WorkspaceFrontmostObserver {
    init()                                // Self-contained; reads SessionRegistry.shared.peekPending() + AppleScriptHelper.shared
    deinit                                // Removes NSWorkspace observer token
}

@MainActor
final class SessionGCTimer {
    init(interval: TimeInterval = 30 * 60, onTick: @escaping () -> Void)
    func start()                          // Schedules first fire at .now() + interval (NOT immediate)
    func cancel()                         // Cancels source; deinit also cancels for symmetry
}
```

## Wave 6 Wiring Notes (for 02-11)

`AppDelegate.applicationDidFinishLaunching(_:)` must retain all three as **stored properties** (otherwise observers/timer deallocate immediately and signals are silently lost — Pattern 8a institutional knowledge from `signalSources`). Order is irrelevant among the three; they don't depend on each other. They MAY be created before or after `await SessionRegistry.shared.restore()` — they only fire on async events that won't beat the restore.

```swift
// In AppDelegate (Wave 6):
private var wakeObserver: WakeObserver?
private var frontmostObserver: WorkspaceFrontmostObserver?
private var gcTimer: SessionGCTimer?

// inside applicationDidFinishLaunching, after restore() / before listener.start():
self.wakeObserver = WakeObserver {
    Task { await SessionRegistry.shared.runGC() }
}
self.frontmostObserver = WorkspaceFrontmostObserver()
self.gcTimer = SessionGCTimer {
    Task { await SessionRegistry.shared.runGC() }
}
self.gcTimer?.start()
```

## Pattern Anchors (regression guards for Wave 6 + future plans)

| Anchor | Source | Verification |
|--------|--------|--------------|
| Verbatim `CRITICAL: retain` comment per file | PATTERNS.md §"DispatchSource / observer retention" | `grep -c 'CRITICAL: retain' App/WakeObserver.swift App/WorkspaceFrontmostObserver.swift App/SessionGCTimer.swift` → `1 1 1` |
| `[weak self]` capture per file | PATTERNS.md retention rule | `grep -c '\[weak self\]' …` → `1 1 1` |
| Bundle ID iTerm2 filter (T-FRONTMOST-SPAM-01) | PLAN.md threat model | `grep -c 'com.googlecode.iterm2' App/WorkspaceFrontmostObserver.swift` → `1` |
| `peekPending()` already exists on SessionRegistry | 02-04 SUMMARY line 72 (`func peekPending() -> [CompletedSession]`) + `App/SessionRegistry.swift:154-156` | `grep -n 'peekPending' App/SessionRegistry.swift` → `154` |

## Threat Model Disposition Closures

| Threat ID | Disposition | How closed |
|-----------|-------------|-----------|
| T-OBSERVER-RETAIN-01 | mitigate | `private var token: NSObjectProtocol?` and `private var source: DispatchSourceTimer?` retained on each class instance. `[weak self]` in handlers prevents retain cycles. `test_timer_isRetained_handlerFiresPostInit` verifies the timer mechanism survives an outer optional reference cycle. |
| T-FRONTMOST-SPAM-01 | mitigate | `app?.bundleIdentifier == "com.googlecode.iterm2"` early-return in WorkspaceFrontmostObserver before any AppleScript work. |
| T-PERM-DENIED-01 (carry) | mitigate | `AppleScriptHelper.frontmostMatches` returns false on permission denial; observer iterates without finding matches; user is informed via Wave 5 banner (not this observer). |
| T-LEAK-OBS-01 | accept | App lifetime = process lifetime; observers live for full app run; deinit-time cleanup covers process exit. |

## Verifier Row Bodies (for 02-11 to graft into scripts/verify-phase-2.sh)

```bash
verify_2_09_01() {
    local id="2-09-01" name="Observers + timer compile + retention pattern (CRITICAL: retain comment, [weak self], bundle-ID filter)"
    if xcodebuild build -scheme ClaudeAlertBot -destination 'platform=macOS' > /tmp/cab-test-out.log 2>&1; then
        if [ "$(grep -c 'CRITICAL: retain' App/WakeObserver.swift App/WorkspaceFrontmostObserver.swift App/SessionGCTimer.swift | grep -c ':1$')" = "3" ] && \
           [ "$(grep -c 'com.googlecode.iterm2' App/WorkspaceFrontmostObserver.swift)" -ge 1 ]; then
            _record_pass "$id" "$name"
        else
            _record_fail "$id" "$name" "anchor grep regression — see App/WakeObserver.swift, App/WorkspaceFrontmostObserver.swift, App/SessionGCTimer.swift"
        fi
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

verify_2_09_02() {
    local id="2-09-02" name="SessionGCTimer fires at interval (SESS-04 mechanism, retention contract)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/SessionGCTimerTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}
```

## Verification Run Results

| Check | Command | Result |
|-------|---------|--------|
| Production build | `xcodebuild build -scheme ClaudeAlertBot -destination 'platform=macOS'` | BUILD SUCCEEDED |
| `verify_2_09_02` (SessionGCTimerTests) | `xcodebuild test -only-testing:ClaudeAlertBotTests/SessionGCTimerTests` | 4/4 pass (1.384s including 0.35s + 0.7s + 0.2s wall sleeps) |
| Full target regression | `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` | 71/71 pass (was 67/67 + 4 new = 71). Zero regressions across Phase 1 / 02-00 / 02-02..09. |
| Anchor: `CRITICAL: retain` per file | `grep -c 'CRITICAL: retain' App/{WakeObserver,WorkspaceFrontmostObserver,SessionGCTimer}.swift` | 1 / 1 / 1 (3 total) |
| Anchor: `[weak self]` per file | `grep -c '\[weak self\]' App/{WakeObserver,WorkspaceFrontmostObserver,SessionGCTimer}.swift` | 1 / 1 / 1 (3 total) |
| Anchor: bundle ID filter | `grep -c 'com.googlecode.iterm2' App/WorkspaceFrontmostObserver.swift` | 1 |
| `peekPending()` already on registry (02-04 contract) | `grep -n 'peekPending' App/SessionRegistry.swift` | 154 |

## Deviations from Plan

None. Plan executed verbatim across both tasks. The plan's must_haves stated WakeObserver "fires `Task { await SessionRegistry.shared.runGC() }` on every wake event"; the action template (which is the executable contract) shipped the same behavior via an injected `onWake` closure that Wave 6 wires to that exact expression — preserving testability and matching AppDelegate's `signalSources` injection style. Both representations are consistent.

## TDD Gate Compliance

| Gate | Commit | Type |
|------|--------|------|
| Task 1 (no TDD per plan) | `116cdb9` | `feat(02-09)` |
| Task 2 RED | `d53931c` | `test(02-09)` |
| Task 2 GREEN | `bd7bdc0` | `feat(02-09)` |

Task 2 followed RED → GREEN strictly. RED build failed with `Cannot find 'SessionGCTimer' in scope` (4 test references, 1 type reference) before the impl was added. No REFACTOR commit — the impl matched the plan template exactly and required no cleanup.

## Self-Check: PASSED

- [x] App/WakeObserver.swift exists and compiles
- [x] App/WorkspaceFrontmostObserver.swift exists and compiles
- [x] App/SessionGCTimer.swift exists and compiles
- [x] ClaudeAlertBotTests/SessionGCTimerTests.swift exists (4/4 pass)
- [x] Production build succeeds
- [x] Full test target: 71/71 pass — zero regressions in Phase 1 / 02-00 / 02-02..08
- [x] git log --oneline | grep '02-09' → 3 commits (RED + 2 GREEN)
- [x] Verbatim retention comment in each file (PATTERNS.md anchor)
- [x] Bundle ID filter `com.googlecode.iterm2` present (T-FRONTMOST-SPAM-01)
- [x] SessionRegistry.peekPending() consumed by WorkspaceFrontmostObserver as planned (02-04 API contract honored)

## Key Files

- `/Users/choijihye/Study/source/claude_alert_bot/App/WakeObserver.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/App/WorkspaceFrontmostObserver.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/App/SessionGCTimer.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/ClaudeAlertBotTests/SessionGCTimerTests.swift`

## Next

**Plan 02-10** — `scripts/verify-phase-2.sh` script that grafts together all verifier row bodies recorded by 02-04 / 02-05 / 02-06 / 02-07 / 02-08 / 02-09. The bodies above (`verify_2_09_01` and `verify_2_09_02`) are ready for direct lift.

**Plan 02-11** — Wave 6 AppDelegate boot wiring. Must retain WakeObserver / WorkspaceFrontmostObserver / SessionGCTimer as stored properties (mirror the institutional `signalSources` pattern). Wires `WakeObserver { Task { await SessionRegistry.shared.runGC() } }` and `SessionGCTimer { Task { await SessionRegistry.shared.runGC() } }`. The frontmost observer is self-contained — `WorkspaceFrontmostObserver()` with no callback. Pitfall #11 boot order (`restore()` before `listener.start()`) remains owned by 02-11; the three Wave 4 components have no ordering constraint with restore() / listener.start().
