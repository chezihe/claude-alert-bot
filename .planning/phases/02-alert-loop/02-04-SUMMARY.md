---
phase: 02-alert-loop
plan: 04
status: complete
completed: 2026-05-08
duration_minutes: 8
requirements: [SESS-01, SESS-02, SESS-03, SESS-04, THR-01, THR-02, AUD-01]
tags: [phase-2, wave-2, actor, persistence, threshold, dedupe, gc]
files_created:
  - App/SessionRegistry.swift
  - App/SessionStore.swift
  - ClaudeAlertBotTests/SessionRegistryTests.swift
  - ClaudeAlertBotTests/SessionStoreTests.swift
  - ClaudeAlertBotTests/Fixtures/MockNotifier+NotifierProtocol.swift
files_modified: []
key_decisions:
  - "AUD-01 dedupe scope = sound only (completed queue appends unconditionally) — Phase 4 may broaden"
  - "Clock DI seam (now / sleepNanoseconds) enables Test K (injectTest auto-dismiss) without 30s real-time wait"
  - "MockNotifier+NotifierProtocol.swift extension file ships in Fixtures/ — Wave 0's MockNotifier.swift unchanged byte-for-byte (file-ownership invariant)"
  - "Test fixtures must use now-anchored, whole-second timestamps (not historical 1_700_000_000 epochs) — lazy GC at top of ingest() evicts >6h-old in-flight seeds, and ISO8601 default formatter strips fractional seconds"
---

# Plan 02-04 SUMMARY — SessionRegistry actor + SessionStore persistence

## What Shipped

Wave 2 core domain. The actor that owns all mutable session state plus its persistence partner. Heart of Phase 2 — every Wave 3+ plan (NotificationOrchestrator, widget, observers, Settings) consumes this actor.

| File | Role | Status |
|------|------|--------|
| `App/SessionStore.swift` | Atomic save / load + corrupt-file recovery (SESS-03 / T-FILE-01 / T-SCHEMA-01) | Created |
| `App/SessionRegistry.swift` | `actor SessionRegistry` — ingest, threshold, dedupe, GC, restore, injectTest, NotifierProtocol declared inline | Created |
| `ClaudeAlertBotTests/SessionStoreTests.swift` | 5 tests: round-trip, missing→nil, garbage→rename, 0600 perms, schema=2→rename | Created |
| `ClaudeAlertBotTests/SessionRegistryTests.swift` | 13 tests (A–M): ingest dispatch, threshold filter, AUD-01 dedupe, THR-02, D2-13, D2-14, SESS-04 GC, clearOne/All, injectTest auto-dismiss + non-persistence, restore | Created |
| `ClaudeAlertBotTests/Fixtures/MockNotifier+NotifierProtocol.swift` | NotifierProtocol conformance via extension only — Wave 0's MockNotifier.swift untouched | Created |

**Atomic commits on master:**
- `169d5a0` — test(02-04): add failing SessionStoreTests (TDD RED)
- `74c0bf7` — feat(02-04): SessionStore actor with atomic save + corrupt-file recovery
- `efefcf6` — test(02-04): add failing SessionRegistryTests + NotifierProtocol extension (TDD RED)
- `35a2be1` — feat(02-04): SessionRegistry actor with ingest/threshold/dedupe/GC/restore/injectTest

## Public API Surface (downstream contract — do not re-read source)

```swift
@MainActor protocol NotifierProtocol: AnyObject {
    func present(session: CompletedSession, playSoundOnce: Bool) async
    func refreshQueueState(completed: [CompletedSession], count: Int) async
}

struct Clock {
    var now: () -> Date = { Date() }
    var sleepNanoseconds: (UInt64) async throws -> Void = {
        try await Task.sleep(nanoseconds: $0)
    }
}

actor SessionRegistry {
    static let shared: SessionRegistry                   // Production singleton.
    init(persistence: SessionStore, clock: Clock = Clock())

    func bind(notifier: any NotifierProtocol)
    func restore() async                                  // Pitfall #11 anchor.
    func ingest(_ event: HookEvent,
                thresholdSeconds: Int,
                soundEnabled: Bool,
                suppressIfFrontmost: @Sendable (String?) async -> Bool) async
    func runGC(now: Date? = nil) async                    // SESS-04 6h sweep.
    func clearOne(sessionID: String) async
    func clearAll() async
    func peekPending() -> [CompletedSession]              // copy snapshot for D2-15 observer.
    func injectTest(soundEnabled: Bool) async             // D2-21 / D2-22.

    #if DEBUG
    func seedCompletedForTesting(_ s: CompletedSession)
    func seedInFlightForTesting(sessionID: String, started: Date, cwd: String?)
    func snapshotForTesting() -> (inFlight: [String: InFlightStart], completed: [CompletedSession])
    #endif
}

actor SessionStore {
    init(url: URL)
    static func atDefaultLocation() -> SessionStore       // SocketPaths.sessionsJSONPath
    func save(_ snapshot: SessionsSnapshot) async         // .atomic + 0600 chmod
    func load() async -> SessionsSnapshot?                // nil on missing/corrupt/schema mismatch
}
```

## Wave 3+ Wiring Notes (for downstream plans)

- **Wave 3 (02-06 NotificationOrchestrator):** Implement `NotifierProtocol` concretely (`@MainActor final class`). Bind via `await SessionRegistry.shared.bind(notifier: self)` from `AppDelegate`.
- **Wave 5 (02-08 SettingsView Test button):** Call `await SessionRegistry.shared.injectTest(soundEnabled: settingsStore.soundEnabled)`. The 30s auto-dismiss is owned by the actor — Settings code does not need to schedule timers.
- **Wave 6 (02-11 AppDelegate boot order):** **Pitfall #11** — call `await SessionRegistry.shared.restore()` BEFORE `await listener.start()`. If listener wins the race, an early Stop arrival will see an empty queue and write a duplicate row that overwrites the disk snapshot before restore loads it.
- **Wave 4 (02-09 WorkspaceFrontmostObserver — D2-15):** Reads `await SessionRegistry.shared.peekPending()` to find candidates whose `itermSessionID` matches the activated app's frontmost iTerm tab UUID; calls `clearOne(sessionID:)` for matches.
- **HookListener dispatch (02-11):** `Task { @MainActor in await SessionRegistry.shared.ingest(event, thresholdSeconds: settings.thresholdSeconds, soundEnabled: settings.soundEnabled) { iTermID in await frontmostHelper.matches(iTermID) } }`. The `suppressIfFrontmost` closure is the seam for Phase 2 Wave 4 (D2-14 cheap-query) — Wave 2 ships it as a parameter so callers wire it without modifying the registry.

## Design Choices (locked)

1. **AUD-01 dedupe scope = sound only.** `completed.append(session)` runs unconditionally on every alert-passing Stop. Only `playSoundOnce: soundEnabled && !isDup` is gated by `dedupeSet`. Phase 4 may broaden the dedupe to suppress the visual alert too — by extending `DedupeKey` (e.g. add `transcript_path`) the actor's call site does not change.
2. **THR-02 = orphan Stop always emits.** When `inFlight.removeValue(forKey: sid)` returns nil, `durationSec=nil` and the threshold guard short-circuits to `passes = true`. PROJECT.md "절대 silently drop 안 함" enforced at code level.
3. **D2-13 auto-clear is silent.** `handleStart` removes pending Stop alerts for the same session_id from `completed` *before* registering inFlight. No notifier call.
4. **Clock DI for tests.** Production constructor uses `Clock()` defaults (real Date.now, real Task.sleep). Tests pass a `Clock` whose `sleepNanoseconds` returns immediately, letting Test K verify auto-dismiss without a 30-second wait.
5. **Test seams under `#if DEBUG`.** `seedCompletedForTesting`, `seedInFlightForTesting`, `snapshotForTesting()` exist only in Debug builds. Release builds expose only the public API surface above.
6. **Lazy GC kick at top of `ingest()`.** Pattern 6 third trigger. Wave 4 adds wake observer + periodic timer triggers without changing this entrance.

## SessionStore Pre-Conditions

- Parent dir `~/Library/Application Support/ClaudeAlertBot/` exists at 0700 (Phase 1 `AppDelegate.ensureDirectories()` invariant). SessionStore does NOT recreate the dir — it assumes Wave 6 boot ordering: ensureDirectories → restore → ingest.
- File at `SocketPaths.sessionsJSONPath`. After every save, perms forced to 0600 (parent at 0700 means non-owner cannot enumerate the file regardless).
- `Data.write(to:options:[.atomic])` uses Foundation's temp-file + rename(2) on APFS. Stale `*.tmp` from a crashed prior run is overwritten on next write — no janitor needed (D2-24 verified).

## Pitfall Anchors

| Pitfall | How this plan closes it |
|---------|-------------------------|
| #9 (concurrent ingest race) | `actor SessionRegistry` — every mutation is implicitly serialized. The `@Sendable` closure boundary on `suppressIfFrontmost` enforces actor crossing. |
| #11 (boot ordering) | `restore()` is the explicit entry point for AppDelegate to call BEFORE `listener.start()`. Wave 6 plan 02-11 owns the wiring. |
| T-FILE-01 (sessions.json corruption) | `Data.write(.atomic)` + decode-failure rename to `*.corrupt-{ts}` + boot empty (UI-SPEC line 190). Tests 3 + 5 in SessionStoreTests verify. |
| T-SCHEMA-01 (schema downgrade) | `SessionsSnapshot.currentSchema = 1`; load rejects mismatch and renames. Test 5 verifies. |

## Verifier Row Bodies (for 02-11 to graft into scripts/verify-phase-2.sh)

```bash
verify_2_04_01() {
    local id="2-04-01" name="SessionRegistry actor — ingest, threshold, dedupe, THR-02, D2-13, GC, injectTest"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/SessionRegistryTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

verify_2_04_02() {
    local id="2-04-02" name="SessionStore atomic save/load + corrupt-file recovery (SESS-03)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/SessionStoreTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Test bug] Test C/D used historical timestamp 1_700_000_000 (Nov 2023)**
- **Found during:** Task 2 GREEN run (3 failures: C, D — and a follow-up duration off-by-one in D)
- **Issue:** `seedInFlightForTesting(started: Date(timeIntervalSince1970: 1_700_000_000))` was older than 6 h relative to `clock.now()` (May 2026). The lazy GC at top of `ingest()` evicted the seeded in-flight before `handleStop` could read it, so duration computed as nil → THR-02 fallback always alerted, breaking Test C (expected drop) and Test D (expected duration=31).
- **Fix:** Anchor seeds at `Date()` (now). After re-run, Test D still failed (`30 ≠ 31`) because the default `ISO8601DateFormatter` strips fractional seconds, so a sub-second stoppedAt round-tripped to a 30.x value that `Int(...)` truncated. Final fix: use a whole-second base `Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))`.
- **Files modified:** `ClaudeAlertBotTests/SessionRegistryTests.swift` (Test C and Test D bodies only — same commit as Task 2 GREEN since the test file lives in the same atomic unit as the implementation it covers under TDD)
- **Commit:** `35a2be1` (Task 2 GREEN includes both the impl and the timestamp fix to the not-yet-committed RED test file)

No production code deviations. Plan executed verbatim otherwise.

## Verification Run Results

| Verification | Command | Result |
|--------------|---------|--------|
| `verify_2_04_02` | `xcodebuild test -only-testing:ClaudeAlertBotTests/SessionStoreTests` | 5/5 pass |
| `verify_2_04_01` | `xcodebuild test -only-testing:ClaudeAlertBotTests/SessionRegistryTests` | 13/13 pass |
| Production build | `xcodebuild build -scheme ClaudeAlertBot` | BUILD SUCCEEDED |
| Full test target (regression) | `xcodebuild test -scheme ClaudeAlertBot` | 31/31 pass (Phase 1 + 02-00 + 02-02 + 02-03 + 02-04 — no regressions) |
| `await persist()` count | `grep -c 'await persist()' App/SessionRegistry.swift` | 7 (≥4 required) |
| Wave 0 MockNotifier untouched | `git diff HEAD~4 -- ClaudeAlertBotTests/Fixtures/MockNotifier.swift` | empty (file-ownership invariant preserved) |

## Self-Check: PASSED

- [x] App/SessionStore.swift exists and compiles
- [x] App/SessionRegistry.swift exists and compiles (singleton + DI init both present)
- [x] ClaudeAlertBotTests/SessionStoreTests.swift exists (5/5 pass)
- [x] ClaudeAlertBotTests/SessionRegistryTests.swift exists (13/13 pass)
- [x] ClaudeAlertBotTests/Fixtures/MockNotifier+NotifierProtocol.swift exists
- [x] ClaudeAlertBotTests/Fixtures/MockNotifier.swift unchanged (file-ownership invariant)
- [x] Production xcodebuild build succeeds
- [x] Full test target run: 31/31 pass — no regressions in Phase 1 / 02-00 / 02-02 / 02-03
- [x] `git log --oneline | grep 02-04` → 4 commits (RED + GREEN ×2)
- [x] grep `'await persist()' App/SessionRegistry.swift` → 7 (≥4 required by success criterion #4)
- [x] No imports of SettingsStore from inside the SessionRegistry actor (single-direction rule preserved per RESEARCH Pattern 4) — `grep SettingsStore App/SessionRegistry.swift` returns nothing.

## TDD Gate Compliance

| Gate | Commit | Type |
|------|--------|------|
| RED (Task 1) | `169d5a0` | `test(02-04)` |
| GREEN (Task 1) | `74c0bf7` | `feat(02-04)` |
| RED (Task 2) | `efefcf6` | `test(02-04)` |
| GREEN (Task 2) | `35a2be1` | `feat(02-04)` |

Both tasks followed RED → GREEN strictly. No REFACTOR commits — implementations matched the canonical RESEARCH Pattern 2 / Pattern 5 templates and required no cleanup.

## Key Files

- `/Users/choijihye/Study/source/claude_alert_bot/App/SessionRegistry.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/App/SessionStore.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/ClaudeAlertBotTests/SessionRegistryTests.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/ClaudeAlertBotTests/SessionStoreTests.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/ClaudeAlertBotTests/Fixtures/MockNotifier+NotifierProtocol.swift`

## Next

Wave 2's other plan, **02-05 (AppleScriptHelper actor)**, is the parallel companion — it provides the `suppressIfFrontmost` closure body that this plan's `ingest()` exposes as a parameter. After both Wave 2 plans land, Wave 3 (02-06 NotificationOrchestrator) can implement `NotifierProtocol` concretely against the API surface frozen above.
