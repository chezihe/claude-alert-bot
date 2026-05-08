---
phase: 02-alert-loop
plan: 06
status: complete
completed: 2026-05-08
duration_minutes: 12
requirements: [AUD-01, AUD-02, WIDG-05]
tags: [phase-2, wave-3, orchestrator, sound, mainactor]
files_created:
  - App/NotificationOrchestrator.swift
  - App/SoundPlayer.swift
  - ClaudeAlertBotTests/NotificationOrchestratorTests.swift
  - ClaudeAlertBotTests/SoundPlayerTests.swift
files_modified: []
key_decisions:
  - "WidgetControllerProtocol locked: showWidget / hideWidget / updatePendingCount / setQueue — consumed by 02-07 (concrete controller), 02-08 (popover), 02-11 (AppDelegate wiring)."
  - "SoundPlaying protocol introduced (extension SoundPlayer: SoundPlaying) — testability seam; production callers use SoundPlayer directly via convenience init."
  - "AUD-01 dedupe is enforced by SessionRegistry.actor only (Wave 2). Orchestrator forwards playSoundOnce verbatim — no double-gating."
  - "NotificationOrchestrator constructor uses non-defaulted `sound: any SoundPlaying` + `convenience init(widget:)` — strict-concurrency-safe (default `SoundPlayer()` cannot be expressed in nonisolated default expression)."
  - "Sound is gated by AND of (playSoundOnce, SettingsStore.soundEnabled). AUD-02 enforced at orchestrator entry — same actor-level read each call (RESEARCH Pitfall 4 accept)."
---

# Plan 02-06 SUMMARY — NotificationOrchestrator + SoundPlayer

## What Shipped

Wave 3's MainActor handoff layer. SessionRegistry's actor cannot directly drive AppKit; this orchestrator is the typed bridge that turns NotifierProtocol calls into widget show/hide and AVAudioPlayer.play(). Ships parallel-buildable with 02-07 by abstracting the widget surface through `WidgetControllerProtocol`.

| File | Role | Status |
|------|------|--------|
| `App/SoundPlayer.swift` | `@MainActor final class SoundPlayer` — AVAudioPlayer wrapper, load-once, missing-file tolerant | Created |
| `App/NotificationOrchestrator.swift` | `@MainActor final class NotificationOrchestrator: NotifierProtocol` + `WidgetControllerProtocol` + `SoundPlaying` declarations | Created |
| `ClaudeAlertBotTests/SoundPlayerTests.swift` | 4 tests: default load, missing-path tolerance, playOnce engages player (CI-skip), nil-player no-op | Created |
| `ClaudeAlertBotTests/NotificationOrchestratorTests.swift` | 6 tests: present routing + AUD-02 + playSoundOnce gating + WIDG-05 hide + setQueue/updatePendingCount + protocol conformance | Created |

**Atomic commits on master:**
- `aa45848` — test(02-06): add failing SoundPlayerTests (TDD RED)
- `154b46e` — feat(02-06): SoundPlayer wrapping AVAudioPlayer (AUD-01)
- `af40594` — test(02-06): add failing NotificationOrchestratorTests (TDD RED)
- `4bf184d` — feat(02-06): NotificationOrchestrator @MainActor — NotifierProtocol impl

## Public API Surface (downstream contract — do not re-read source)

```swift
// App/SoundPlayer.swift
@MainActor protocol SoundPlaying: AnyObject {           // declared in NotificationOrchestrator.swift
    func playOnce()
}

@MainActor
final class SoundPlayer {
    init(soundURL: URL = URL(fileURLWithPath: "/System/Library/Sounds/Funk.aiff"))
    func playOnce()                                     // no-op when player nil
    #if DEBUG
    var playerForTesting: AVAudioPlayer? { get }
    #endif
}
extension SoundPlayer: SoundPlaying {}                  // production conformer

// App/NotificationOrchestrator.swift
@MainActor protocol WidgetControllerProtocol: AnyObject {
    func showWidget(pendingCount: Int, latest: CompletedSession?)
    func hideWidget()
    func updatePendingCount(_ n: Int, latest: CompletedSession?)
    func setQueue(_ queue: [CompletedSession])
}

@MainActor
final class NotificationOrchestrator: NotifierProtocol {
    init(widget: (any WidgetControllerProtocol)?,
         sound: any SoundPlaying,
         settings: @autoclosure @escaping () -> SettingsStore = SettingsStore.shared)
    convenience init(widget: (any WidgetControllerProtocol)?)   // allocates SoundPlayer()

    func bind(widget: any WidgetControllerProtocol)             // Wave 6 post-init wiring

    // NotifierProtocol
    func present(session: CompletedSession, playSoundOnce: Bool) async
    func refreshQueueState(completed: [CompletedSession], count: Int) async
}
```

## WidgetControllerProtocol — Locked Shape (for 02-07 / 02-08 / 02-11)

**This is the contract the parallel plan 02-07 must implement.** Wave 4 (02-08 popover) and Wave 6 (02-11 AppDelegate wiring) consume the same shape.

| Method | When called | Caller responsibility |
|--------|-------------|------------------------|
| `showWidget(pendingCount:latest:)` | `present()` per Stop alert | Make NSPanel visible (orderFront), set icon, optionally update +N badge |
| `hideWidget()` | `refreshQueueState(count: 0)` | `orderOut(nil)` the NSPanel — WIDG-05 |
| `updatePendingCount(_:latest:)` | `refreshQueueState(count: N≥1)` | Update +N text badge; `latest` drives the icon's tooltip / popover focus |
| `setQueue(_:)` | `refreshQueueState(count: N≥1)` | Replace popover content source array (FIFO, oldest first) |

**Important:** `latest` parameter on showWidget/updatePendingCount = the most recently appended `CompletedSession`. For `refreshQueueState`, latest = `completed.last` (the actor appends in chronological order). Plan 02-07 should use this value to drive the popover's "currently focused row" highlight.

## SoundPlaying — Should 02-07/02-08 Use It?

**No.** SoundPlaying exists solely as a test seam for 02-06. The Settings View's "Test notification" button (plan 02-08, SET-04) uses `await SessionRegistry.shared.injectTest(soundEnabled:)` per 02-04's API freeze — it walks the standard alert path and reaches the orchestrator, which in turn invokes the production `SoundPlayer.playOnce()`. There is no separate "test sound" channel.

## AUD-01 Dedupe Enforcement Site (clarification)

The dedupe is **owned by SessionRegistry.actor (Wave 2 / 02-04)**, not by the orchestrator. The actor:
1. Computes `DedupeKey.from(sessionID:, at: stoppedAt)` (2-second bucket per D2-20).
2. Inserts into `dedupeSet`. If duplicate, sets `playSoundOnce: false` on the notifier call.
3. The orchestrator forwards `playSoundOnce` verbatim and additionally AND-gates with `SettingsStore.soundEnabled` (AUD-02).

**Why two gates:** `playSoundOnce` is the registry's "dedupe says: please don't play". `soundEnabled` is the user's "I never want sound." Both must be true → sound. Either false → silent. Tests `test_present_skipsSound_whenSoundDisabled_AUD_02` and `test_present_skipsSound_whenPlaySoundOnceFalse` verify each gate independently.

## Constructor Strict-Concurrency Note

**Deviation note (Rule 1 fix):** Initial draft used `sound: any SoundPlaying = SoundPlayer()` as a default-parameter expression. Swift's strict concurrency rejected this with: *"Call to main actor-isolated initializer 'init(soundURL:)' in a synchronous nonisolated context"*. Default expressions are evaluated in the caller's isolation, which may not be `@MainActor`.

**Fix:** Removed the default value. Added `convenience init(widget:)` that allocates `SoundPlayer()` from inside a class-level @MainActor method body, where it's safe. Tests pass `SpySoundPlayer()` explicitly. AppDelegate (Wave 6) will use the convenience initializer or pass `SoundPlayer()` explicitly.

This is a small ergonomic change vs. the plan's pseudocode but preserves the public surface (constructor still accepts `sound: any SoundPlaying`). Tests required no rewrite.

## Wave 3+ Wiring Notes

- **02-07 (FloatingWidgetWindowController, parallel):** Implement `WidgetControllerProtocol` on the new `final class FloatingWidgetWindowController: NSWindowController, WidgetControllerProtocol`. Its `setQueue` becomes the NSPopover content data source (Wave 4 02-08).
- **02-08 (Settings + popover, Wave 4):** Test notification button calls `await SessionRegistry.shared.injectTest(soundEnabled: settingsStore.soundEnabled)` — the orchestrator's `present()` is the same call site as a real Stop, so no special-casing.
- **02-11 (AppDelegate boot, Wave 6):** Construct in this order:
  ```swift
  // (1) FloatingWidgetWindowController (02-07)
  let widget = FloatingWidgetWindowController(...)
  // (2) NotificationOrchestrator (this plan)
  let orch = NotificationOrchestrator(widget: widget)
  // (3) Bind to registry
  await SessionRegistry.shared.bind(notifier: orch)
  // (4) Pitfall #11 — restore BEFORE listener.start() (02-04 contract)
  await SessionRegistry.shared.restore()
  // (5) Listener start
  await listener.start()
  ```

## Threat Model Closure

| Threat ID | Disposition | Closure |
|-----------|-------------|---------|
| T-AUDIO-01 | mitigate | `try AVAudioPlayer(contentsOf:)` wrapped in do/catch — failure leaves `player = nil`. `playOnce()` `guard let p = player` short-circuits. Test 2 + Test 4 verify (the missing-file path is exercised twice). |
| T-MAINACTOR-01 | mitigate | `NotifierProtocol`, `WidgetControllerProtocol`, `SoundPlaying` are all `@MainActor`. Compiler enforces `await` at the SessionRegistry-actor → orchestrator boundary. SessionRegistry already calls via `let n = self.notifier; await n?.present(...)` (verified in 02-04). |
| T-SETTINGS-01 (carry from 02-04) | accept | `SettingsStore.soundEnabled` read at `present()` entry via `let store = settings()`. Race window is microseconds; user toggle is human-paced. RESEARCH Pitfall 4 explicit accept. |

## Verification Run Results

| Verification | Command | Result |
|--------------|---------|--------|
| `verify_2_06_01` | `xcodebuild test -only-testing:ClaudeAlertBotTests/SoundPlayerTests` | 4/4 pass (0.54s) |
| `verify_2_06_02` | `xcodebuild test -only-testing:ClaudeAlertBotTests/NotificationOrchestratorTests` | 6/6 pass (0.85s) |
| Production build | `xcodebuild build -scheme ClaudeAlertBot` | BUILD SUCCEEDED (no new warnings; pre-existing build-script warnings inherited from Phase 1) |
| Full test target (regression) | `xcodebuild test -scheme ClaudeAlertBot` | 50/50 pass (Phase 1 + 02-00 + 02-02 + 02-03 + 02-04 + 02-05 + 02-06 — was 40/40 before this plan, 4 + 6 new tests, 0 regressions) |
| `final class NotificationOrchestrator: NotifierProtocol` count | `grep -c App/NotificationOrchestrator.swift` | 1 |
| `WidgetControllerProtocol` ref count | `grep -c App/NotificationOrchestrator.swift` | 6 (declaration + property + bind + init param + convenience init + show/hide call sites) |
| `soundEnabled` ref count | `grep -c App/NotificationOrchestrator.swift` | 4 (read in present + log + comment refs) |
| `SoundPlaying` declaration | `grep -c 'protocol SoundPlaying' App/NotificationOrchestrator.swift` | 1 |
| `SoundPlayer` conforms | `grep -c 'extension SoundPlayer: SoundPlaying' App/NotificationOrchestrator.swift` | 1 |

## Verifier Row Bodies (for 02-11 to graft into scripts/verify-phase-2.sh)

```bash
verify_2_06_01() {
    local id="2-06-01" name="SoundPlayer load-once + tolerate missing file (AUD-01)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/SoundPlayerTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

verify_2_06_02() {
    local id="2-06-02" name="NotificationOrchestrator AUD-02 sound toggle + WIDG-05 hideWidget routing"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/NotificationOrchestratorTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Strict-concurrency build error] Default `SoundPlayer()` parameter rejected**
- **Found during:** Task 2 GREEN first compile attempt
- **Issue:** `init(... sound: any SoundPlaying = SoundPlayer(), ...)` failed to compile: *"Call to main actor-isolated initializer 'init(soundURL:)' in a synchronous nonisolated context."* Swift evaluates default expressions in the caller's isolation context.
- **Fix:** Removed the default value; added `convenience init(widget:)` that constructs `SoundPlayer()` inside a `@MainActor`-isolated method body. Tests pass `SpySoundPlayer()` explicitly. Public surface unchanged for production callers (AppDelegate calls the convenience initializer).
- **Files modified:** `App/NotificationOrchestrator.swift` (constructor signature only)
- **Commit:** `4bf184d` (Task 2 GREEN — same atomic unit; no separate fix-up commit)
- **Documented in plan?** No — plan's pseudocode used the default. Same-shape issue may resurface in 02-07/02-08 if they expose default-parameter NSPanel constructors; planners should use convenience initializers instead.

**2. [Rule 2 — Missing test setUp/tearDown] SettingsStore mutation isolation**
- **Found during:** Reading the plan (preventive)
- **Issue:** Plan body says "set `SettingsStore.shared.soundEnabled = false` in the test (and reset in tearDown ... since that's the default)." This is correctness-critical — without explicit reset, test ordering can cross-contaminate.
- **Fix:** Added `setUp()` and `tearDown()` to `NotificationOrchestratorTests` that reset `SettingsStore.shared.soundEnabled = true`. Both methods are `@MainActor` async to match XCTest expectations.
- **Files modified:** `ClaudeAlertBotTests/NotificationOrchestratorTests.swift` (boilerplate only)
- **Commit:** `af40594` (RED — included from initial test file write)

No production code deviations beyond #1. Plan executed verbatim otherwise.

## Self-Check: PASSED

- [x] App/SoundPlayer.swift exists and compiles
- [x] App/NotificationOrchestrator.swift exists and compiles
- [x] ClaudeAlertBotTests/SoundPlayerTests.swift exists (4/4 pass)
- [x] ClaudeAlertBotTests/NotificationOrchestratorTests.swift exists (6/6 pass)
- [x] `final class NotificationOrchestrator: NotifierProtocol` — verified by grep (1)
- [x] `WidgetControllerProtocol` declared in NotificationOrchestrator.swift — verified by grep (≥2 — actual 6)
- [x] `protocol SoundPlaying` declared and `SoundPlayer` conforms — verified by grep (1 + 1)
- [x] AUD-02 (sound toggle off → no playback) verified by `test_present_skipsSound_whenSoundDisabled_AUD_02`
- [x] WIDG-05 (count==0 → widget hidden) verified by `test_refreshQueueState_emptyCount_hidesWidget_WIDG_05`
- [x] AUD-01 (`playSoundOnce` dedupe gate) verified by `test_present_skipsSound_whenPlaySoundOnceFalse`
- [x] Production xcodebuild build succeeds
- [x] Full test target run: 50/50 pass — no regressions (Phase 1 + 02-00..05 stable)
- [x] git log: 4 commits on master (RED + GREEN ×2)

## Commit-existence verification

```bash
git log --oneline | grep -E "aa45848|154b46e|af40594|4bf184d"
# 4bf184d feat(02-06): NotificationOrchestrator @MainActor — NotifierProtocol impl
# af40594 test(02-06): add failing NotificationOrchestratorTests (TDD RED)
# 154b46e feat(02-06): SoundPlayer wrapping AVAudioPlayer (AUD-01)
# aa45848 test(02-06): add failing SoundPlayerTests (TDD RED)
```

## TDD Gate Compliance

| Gate | Commit | Type |
|------|--------|------|
| RED (Task 1) | `aa45848` | `test(02-06)` |
| GREEN (Task 1) | `154b46e` | `feat(02-06)` |
| RED (Task 2) | `af40594` | `test(02-06)` |
| GREEN (Task 2) | `4bf184d` | `feat(02-06)` |

Both tasks followed RED → GREEN strictly. No REFACTOR commits — implementations are minimal-and-canonical (RESEARCH Pattern 10 for SoundPlayer; PATTERNS.md §NotificationOrchestrator for the orchestrator).

## Key Files

- `/Users/choijihye/Study/source/claude_alert_bot/App/SoundPlayer.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/App/NotificationOrchestrator.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/ClaudeAlertBotTests/SoundPlayerTests.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/ClaudeAlertBotTests/NotificationOrchestratorTests.swift`

## Next

Wave 3's other plan, **02-07 (FloatingWidgetPanel + WindowController)**, is the parallel companion — it provides the concrete `WidgetControllerProtocol` implementation. After 02-07 lands, Wave 4 (02-08 SettingsView + popover) can wire the SET-04 Test notification button to `SessionRegistry.shared.injectTest(...)` knowing the full alert path is operational. Wave 6 (02-11) then performs the AppDelegate wiring per the boot order documented above.
