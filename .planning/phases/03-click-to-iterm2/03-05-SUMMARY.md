---
phase: 03-click-to-iterm2
plan: 05
subsystem: ui
tags: [swift, applescript, terminaljumper, adapter-pattern, oslog, mainactor]

requires:
  - phase: 03-click-to-iterm2/03-01
    provides: TerminalJumper protocol + JumpResult enum
  - phase: 03-click-to-iterm2/03-04
    provides: AppleScriptHelper.runJumpByUUID(_:) → JumpResult, scriptResultToJump mapping

provides:
  - "App/ITerm2Jumper.swift — v1 single conformer of TerminalJumper, thin orchestrator over AppleScriptHelper"
  - "OSLog 4-prefix contract on widget category: [jumped], [jump-missed], [jump-denied], [jump-error]"
  - "D3-04 envelope-form regression guard at the ITerm2Jumper boundary (test passes)"
  - "Pitfall #1 grep-gate clean (0 matches in jump code paths)"

affects:
  - 03-06 (PopoverRowView state machine consumes JumpResult)
  - 03-07 (WidgetPopoverController calls jumper.jump(to:))
  - 03-09 (verifier asserts grep-gate + 4-prefix log filter)
  - v2 MTERM-01..04 (multi-terminal adapter seam — new conformers slot in)

tech-stack:
  added: []
  patterns:
    - "Thin orchestrator @MainActor final class — mirror of NotificationOrchestrator (Phase 2 02-06)"
    - "Self-documenting Pitfall #1 comment header (// NSApp.activate forbidden) — verifier grep filters comments via `grep -v '^[[:space:]]*//'`"
    - "Init-injected actor dependency with default = .shared — test-swappable, production-frictionless"

key-files:
  created:
    - "App/ITerm2Jumper.swift (66 lines)"
    - "ClaudeAlertBotTests/ITerm2JumperTests.swift (76 lines)"
  modified:
    - "ClaudeAlertBot.xcodeproj/project.pbxproj (xcodegen regenerated to register new sources)"

key-decisions:
  - "OSLog category = `widget` (not `applescript`) — single log filter shows full click-to-jump narrative including 03-06 row state changes (CONTEXT D3-13 / PATTERNS §ITerm2Jumper)"
  - "Defensive iTermSessionID.uuid(fromRaw:) + isValid() at ITerm2Jumper boundary even though 03-03 already normalizes — orphan-stop fallback and test fixtures may bypass ingestion"
  - "Envelope regression test asserts `XCTAssertNotEqual(result, .otherError(0))` instead of plan's `.permissionDenied` — environment-independent, preserves D3-04 intent (input passed isValid gate)"

patterns-established:
  - "TerminalJumper conformance pattern: @MainActor final class, init-injected helper, switch over JumpResult cases emitting D3-13 4-prefix logs — v2 multi-terminal conformers (MTERM-01..04) follow same shape"
  - "OSLog [bracket-prefix session=<uuid>] format, single privacy=.public field per call — log show filter compatible"

requirements-completed: [JUMP-01, JUMP-02]

# Metrics
duration: 13min
completed: 2026-05-08
---

# Phase 3 Plan 05: ITerm2Jumper — v1 single TerminalJumper adapter Summary

**Single-class @MainActor adapter that translates `CompletedSession` row clicks into `AppleScriptHelper.runJumpByUUID` calls, emits the D3-13 4-prefix OSLog contract, and guards Pitfall #1 (no `NSApp.activate` in jump paths).**

## Performance

- **Duration:** ~13 min
- **Started:** 2026-05-08T15:12 (worktree)
- **Completed:** 2026-05-08T15:25Z
- **Tasks:** 2
- **Files modified:** 2 source + 1 generated (project.pbxproj)

## Accomplishments

- `App/ITerm2Jumper.swift` (66 lines) — single `final class ITerm2Jumper: TerminalJumper`, `@MainActor`, init-injected `helper: AppleScriptHelper = .shared`. `jump(to:)` validates UUID via `iTermSessionID.uuid(fromRaw:)` + `isValid(_:)`, calls `helper.runJumpByUUID`, emits one of 4 `[jump*]` OSLog prefixes per `JumpResult` case.
- `ClaudeAlertBotTests/ITerm2JumperTests.swift` (76 lines) — 4-test unit matrix: nil iterm UUID, invalid UUID format, envelope-form (`w0t0p1:UUID`) strip regression, static `TerminalJumper` conformance check. All 4 tests pass in 3.1s; full suite 103 tests, 0 failures.
- Pitfall #1 regression guard: source-level comment header documents the prohibition; verifier-style grep gate (`grep -v '^[[:space:]]*//' App/ITerm2Jumper.swift App/AppleScriptHelper.swift | grep -c 'NSApp\.activate'`) returns **0** as required.
- D-ADAPTER seam complete — Phase 3 boundary ready for 03-07 (`WidgetPopoverController` calls `await jumper.jump(to: session)` with no AppleScript awareness).

## Task Commits

1. **Task 1: Create App/ITerm2Jumper.swift (v1 single TerminalJumper conformer)** — `786aad4` (feat)
2. **Task 2: Create ClaudeAlertBotTests/ITerm2JumperTests.swift (unit matrix)** — `caf960a` (test)

## Files Created/Modified

- `App/ITerm2Jumper.swift` (created) — Single v1 TerminalJumper conformer; thin orchestrator wrapping AppleScriptHelper.runJumpByUUID with D3-13 OSLog mapping.
- `ClaudeAlertBotTests/ITerm2JumperTests.swift` (created) — Unit tests covering nil/invalid UUID short-circuit, envelope-form strip regression, protocol conformance.
- `ClaudeAlertBot.xcodeproj/project.pbxproj` (modified) — xcodegen regenerated to register the two new source files.

## Decisions Made

- **OSLog category = `widget`** (CONTEXT D3-13). All click-to-jump logs share the widget category with `WidgetPopoverController` and the upcoming 03-06 row-state transitions, so a single `log show --predicate 'subsystem == "com.claudealert.bot.hook" AND category == "widget"'` filter reveals the full narrative.
- **Defensive UUID re-validation in `jump(to:)`** even though 03-03 ingestion normalizes `itermSessionID` to UUID-only. Justification: orphan-stop fallback paths and `CompletedSession.testFixture()` may bypass ingestion entirely. `iTermSessionID.uuid(fromRaw:)` is idempotent — colonless input passes through unchanged with no penalty.
- **Test seam: keep helper singleton, don't introduce a protocol over AppleScriptHelper.** Plan considered protocol-extracting AppleScriptHelper for full mocking; rejected to avoid Phase 2 surface drift. Live AppleScript paths covered by the 03-09 manual checkpoint instead.

## JumpResult ↔ OSLog Mapping (D3-13 4-prefix contract)

| `JumpResult` case | OSLog level | Format |
|-------------------|-------------|--------|
| `.ok` | `notice` | `[jumped session=<sessionID>]` |
| `.missing` | `notice` | `[jump-missed session=<sessionID>]` (also emitted on UUID validation short-circuit with suffix `(no iterm UUID)`) |
| `.permissionDenied` | `warning` | `[jump-denied session=<sessionID>]` |
| `.iTermNotRunning` | `warning` | `[jump-error session=<sessionID> reason=iterm-not-running]` |
| `.timeout` | `warning` | `[jump-error session=<sessionID> reason=timeout]` |
| `.otherError(code)` | `warning` | `[jump-error session=<sessionID> code=<code>]` |

`grep -cE '\[jumped|\[jump-missed|\[jump-denied|\[jump-error' App/ITerm2Jumper.swift` returns **13** (≥4 satisfied — all 4 D3-13 prefix literals present in source).

## Pitfall #1 Grep Gate Verification

```
$ grep -v '^[[:space:]]*//' App/ITerm2Jumper.swift App/AppleScriptHelper.swift | grep -c 'NSApp\.activate'
0
```

The self-documenting comment header in `ITerm2Jumper.swift` lines 5-9 references `NSApp.activate` in prose; the verifier's `grep -v '^\s*//'` prefilter strips comment lines, so the count is **0** as required by D3-10. iTerm2 activation lives entirely inside the AppleScript-side `tell application "iTerm2" to activate` (already in `AppleScriptHelper.jumpByUUIDTemplate` / `focusFrontmostSource`).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Plan's envelope-strip regression test asserted `.permissionDenied`, but `runJumpByUUID(_:)` does not consult `lastKnownPermission`**

- **Found during:** Task 2 (running `xcodebuild test -only-testing:.../ITerm2JumperTests`)
- **Issue:** Plan instructed the third test (`test_jump_envelopeFormatItermID_isStrippedAndValidated`) to call `await AppleScriptHelper.shared.markDeniedForTesting()` before invoking `jumper.jump(to:)`, expecting the helper to short-circuit and return `.permissionDenied`. In reality, `runJumpByUUID(_:)` (App/AppleScriptHelper.swift line 142-173) only branches on `lastKnownPermission` for state-mirror writes after the AppleScript executes — not as a guard before. Only `testConnection()` (line 181-196) reads `lastKnownPermission` to short-circuit. The actual observed result was `.timeout` (3s AppleScript-side timeout) because the test environment has no live iTerm2.
- **Fix:** Replaced the `XCTAssertEqual(result, .permissionDenied)` with `XCTAssertNotEqual(result, .otherError(0))`. This preserves the D3-04 regression intent — `.otherError(0)` is the helper's signature for "isValid(_:) rejected the input before substitution" (AppleScriptHelper.swift line 144), so any other JumpResult (`.ok / .missing / .permissionDenied / .timeout`) proves the envelope value was stripped, passed `isValid(_:)`, and reached AppleScript execution. Also removed the now-unused `markDeniedForTesting()` call and the trailing `markGrantedForTesting()` cleanup. Comment block rewritten to explain the environment-independent assertion strategy.
- **Files modified:** `ClaudeAlertBotTests/ITerm2JumperTests.swift` (test method body only, lines 38-66)
- **Verification:** All 4 ITerm2JumperTests pass in 3.1s. Full suite green (103 tests, 0 failures).
- **Committed in:** `caf960a` (Task 2 commit)
- **Advisor consultation:** Confirmed the assertion-rewrite preserves the D3-04 regression intent without binding to environment state. Advisor flagged the same misdiagnosis in plan and recommended the same `.otherError(0)` discriminator.

---

**Total deviations:** 1 auto-fixed (1 Rule 1 bug — incorrect helper-internals assumption in plan-supplied test).
**Impact on plan:** Plan's success criteria (4 ITerm2JumperTests pass) achieved; D3-04 regression guard intent fully preserved. Test no longer depends on permission state or live iTerm2, so it stays green across CI / local / granted / denied / unknown. No scope creep.

## Issues Encountered

- Initial test run failed because plan's helper-state assumption was wrong (see deviation 1 above). Resolved by replacing the assertion with an environment-independent discriminator after advisor consultation.

## Threat Flags

None — no new trust boundaries introduced. The two threats from the plan's `<threat_model>` (T-PITFALL-1, T-D3-13-DRIFT) are both `mitigate` dispositioned and verified inline (Pitfall #1 grep gate = 0; D3-13 4-prefix grep ≥ 4).

## Next Phase Readiness

- 03-06 (PopoverRowView state machine) — can now consume `JumpResult` returned from `jumper.jump(to:)` directly. State transitions `normal → jumping → missing → clearOne` map cleanly onto the 4 D3-13 prefix branches.
- 03-07 (WidgetPopoverController integration) — ready: `private let jumper: any TerminalJumper` injection point, `await jumper.jump(to: session)` call site, no AppleScript knowledge needed.
- 03-09 (verifier) — has the exact grep-gate commands referenced in the `<verification>` section above; running them on this commit returns 0/13/1 as required.

## Self-Check: PASSED

```
FOUND: App/ITerm2Jumper.swift
FOUND: ClaudeAlertBotTests/ITerm2JumperTests.swift
FOUND: 786aad4 (Task 1 commit)
FOUND: caf960a (Task 2 commit)
```

---
*Phase: 03-click-to-iterm2*
*Completed: 2026-05-08*
