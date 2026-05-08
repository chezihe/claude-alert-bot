---
phase: 03-click-to-iterm2
plan: 07
subsystem: widget-popover-controller / jump dispatch + row state orchestration
tags: [phase-3, wave-5, d3-13, d-adapter, integration, jump-dispatch, rowstate]

requires:
  - phase: 03-click-to-iterm2/03-05
    provides: ITerm2Jumper (TerminalJumper conformer; @MainActor; OSLog [jump*] 4-prefix contract)
  - phase: 03-click-to-iterm2/03-06
    provides: PopoverContentView rowStates dict + onRowMissingComplete callback; PopoverRowView state machine
  - phase: 02-alert-loop/02-08
    provides: WidgetPopoverController scaffold (NSPopover + hover-intent + showPopover/dismissPopover)
  - phase: 02-alert-loop/02-11
    provides: Pitfall #11 boot order — AppDelegate is the explicit retain owner of WidgetPopoverController

provides:
  - "App/WidgetPopoverController.swift Phase 3 jump-dispatch surface — onRowClick now drives the full click-to-jump narrative"
  - "Convenience-init pattern unblocking @MainActor TerminalJumper injection (mirrors 02-06 NotificationOrchestrator)"
  - "Per-session rowStates orchestration with reloadPopoverContent() helper — popover re-renders on state mutation"
  - "PermissionDeepLink hook on .permissionDenied (ONB-03 satisfied at the click site)"

affects:
  - 03-09 (verifier checkpoint exercises the full click-to-jump path live in iTerm2)
  - v2 multi-terminal (jumper substitution at boot — already auditable at AppDelegate line 58)

tech-stack:
  added: []
  patterns:
    - "Designated init + convenience init split for @MainActor dependency injection (02-06 carry-over)"
    - "NSHostingController(rootView:) reassignment as popover re-render primitive (02-08 carry-over)"
    - "Closure-literal duplication tolerated in showPopover() + reloadPopoverContent() per CLAUDE.md `preserve original code` (see Decisions)"
    - "Task { ... } + await MainActor.run { ... } switch-on-result pattern (mirrors NotificationOrchestrator.present)"

key-files:
  created: []
  modified:
    - App/WidgetPopoverController.swift (D2-08 placeholder removed; +86/-8 lines)
    - App/AppDelegate.swift (one-line edit; +1/-1)

decisions:
  - "Closure-literal duplication accepted — showPopover() and reloadPopoverContent() each construct their own PopoverContentView with the same 4 closure params (onRowClick / onClearAll / rowStates / onRowMissingComplete). Plan §Step 4 explicitly chose this trade-off; extracting a helper would have to either (a) capture self for mutation, complicating closure semantics, or (b) accept rowStates as an inout/snapshot, fighting Swift value-type semantics. CLAUDE.md `minimum modification` favors duplication over a contortion."
  - "Default-arg `jumper: any TerminalJumper = ITerm2Jumper()` from the plan was rejected by the Swift 6 concurrency checker — both `WidgetPopoverController` and `ITerm2Jumper` are `@MainActor`, but a default-argument expression is evaluated in a nonisolated context. Resolved by splitting into a designated init (`jumper:` required) + a `convenience init(widgetController:)` that supplies `ITerm2Jumper()` from inside the @MainActor-isolated init body. This mirrors verbatim the 02-06 `NotificationOrchestrator` pattern (Phase 2 SUMMARY §convenience init for SoundPlayer)."
  - "AppDelegate edit is the explicit construction style required by Pitfall #11: line 58 now reads `WidgetPopoverController(widgetController: widget, jumper: ITerm2Jumper())` rather than relying on the convenience initializer. Makes the dependency auditable at the boot site and trivially substitutable in tests."

metrics:
  duration_minutes: ~12
  tasks_completed: 2
  files_modified: 2
  files_created: 0
  commits: 2
  tests_status: 103/103 pass (no regressions across Phase 1 / 2 / 3-pre-07 suites)
  build_status: BUILD SUCCEEDED (xcodebuild -scheme ClaudeAlertBot -destination platform=macOS)
  completed_at: "2026-05-09"
---

# Phase 3 Plan 07: Wire WidgetPopoverController to TerminalJumper Summary

Replaces the Phase 2 D2-08 `[would-jump session=<uuid>]` log-only placeholder with the actual click-to-jump dispatch + per-row state orchestration. Phase 3's gravitational core: SC#1 (3 sessions / 3 tabs jump) and SC#2 (closed tab → friendly missing animation) pass-or-fail moments live here.

## What Changed

### `App/WidgetPopoverController.swift` (modified — +86 / -8)

1. **File header** — D2-08 placeholder note replaced with Phase 3 (03-07) note documenting the [jump*] 4-prefix contract is owned by `ITerm2Jumper`, not this file (D3-13).

2. **New private properties:**
   - `private let jumper: any TerminalJumper` — D-ADAPTER seam.
   - `private var rowStates: [String: RowState] = [:]` — D3-11 per-session state map.

3. **Init split** — designated `init(widgetController:jumper:)` (test-substitutable) + `convenience init(widgetController:)` for production (defaults to `ITerm2Jumper()`). See Deviations §1 for the why.

4. **`showPopover()`** — `PopoverContentView` constructor now forwards `rowStates` + `onRowMissingComplete` callback. The callback dispatches `SessionRegistry.shared.clearOne` + removes the row's state entry + reloads.

5. **New `reloadPopoverContent()` helper** — guards on `popover?.isShown` and rebuilds `NSHostingController(rootView: PopoverContentView(...))`. Existing reload primitive from 02-08 line 67 (just lifted into a named method).

6. **`onRowClick(sessionID:)` rewritten:**
   - Looks up `session` in `widgetController.queueSnapshot`. If gone (clearAll race), logs `[jump-missed session=...] (no longer in queue)` and returns.
   - JUMP-05 self-debounce — short-circuits if `rowStates[sessionID]` is non-nil and not `.normal`.
   - Sets state to `.jumping`, reloads popover.
   - `Task { ... }` awaits `jumper.jump(to: session)`. After result, hops to MainActor and switches:
     - `.ok` → remove state, fire `clearOne`, dismiss popover.
     - `.missing` / `.iTermNotRunning` / `.timeout` / `.otherError(_)` → set state to `.missing`, reload (row's collapse animation + onMissingComplete callback handles cleanup).
     - `.permissionDenied` → set state to `.missing`, reload, AND call `PermissionDeepLink.openAutomationPreferences()` (ONB-03).

7. **No new OSLog emissions in this file** — all `[jump*]` 4-prefix lines are emitted by `ITerm2Jumper.jump(to:)` per D3-13. WPC only logs the queue-race fallback (`[jump-missed session=... (no longer in queue)]`) and the existing `popover shown` / `popover dismissed`.

### `App/AppDelegate.swift` (modified — +1 / -1)

Line 58 changed from:

```swift
let popover = WidgetPopoverController(widgetController: widget)
```

to:

```swift
let popover = WidgetPopoverController(widgetController: widget, jumper: ITerm2Jumper())
```

Pitfall #11 explicit-construction principle. Convenience init still works for tests that don't need to substitute the jumper.

## Verification Status

All seven plan verification gates green:

| # | Check | Expected | Actual |
|---|-------|----------|--------|
| 1 | xcodebuild build | BUILD SUCCEEDED | BUILD SUCCEEDED |
| 2 | xcodebuild test (full suite) | green | 103/103 pass, 0 failures |
| 3 | `grep -c '\[would-jump' App/WidgetPopoverController.swift` | 0 | 0 |
| 4 | `grep -c 'jumper.jump' App/WidgetPopoverController.swift` | 1 | 1 |
| 5 | `grep -c 'PermissionDeepLink.openAutomationPreferences' App/WidgetPopoverController.swift` | 1 | 1 |
| 6 | `grep -c 'ITerm2Jumper' App/AppDelegate.swift` | 1 | 1 |
| 7 | `grep -c 'rowStates' App/WidgetPopoverController.swift` | ≥3 | 11 |

Phase 2 D2-08 `[would-jump session=...]` literal verifiably gone — was at line 97 (`log.notice("[would-jump session=\(sessionID, privacy: .public)]")`) in the pre-07 file; the entire `onRowClick` body is replaced. The new `[jump-missed session=... (no longer in queue)]` literal is a different prefix (queue-race log, not the D2-08 placeholder).

AppDelegate edit confirmed minimal — `git diff --stat` reports 1 changed file, 1 insertion, 1 deletion. No other AppDelegate code touched.

## Deviations from Plan

### 1. [Rule 3 - Blocking] Default-arg `jumper: ... = ITerm2Jumper()` rejected by compiler

- **Found during:** Task 1, first xcodebuild attempt
- **Issue:** Plan §Step 2 specified `init(widgetController:..., jumper: any TerminalJumper = ITerm2Jumper())`. Compiler error:
  ```
  App/WidgetPopoverController.swift:32:39: error: call to main actor-isolated initializer 'init(helper:)' in a synchronous nonisolated context
  ```
  Both `WidgetPopoverController` and `ITerm2Jumper` are `@MainActor`, but Swift evaluates default-argument expressions in a nonisolated context. Same root cause as the 02-06 `NotificationOrchestrator` issue (which the plan's parenthetical at §Step 2 explicitly cited as a precedent).
- **Fix:** Split into a designated init `init(widgetController:jumper:)` (no default, both required) + `convenience init(widgetController:)` that calls `self.init(widgetController:, jumper: ITerm2Jumper())` from inside the @MainActor-isolated init body. The convenience initializer is what backward-compatible call sites get; the designated initializer is what AppDelegate now uses (Pitfall #11) and what tests will use to substitute.
- **Files modified:** `App/WidgetPopoverController.swift` only.
- **Commit:** `0060adf`
- **Why this is Rule 3 (blocking) not Rule 4 (architectural):** The plan documented the convenience-init pattern as a known fallback (§Step 2 explicitly noted "the default-arg keeps any existing test or call site working — Phase 2 tests still pass"). The pattern is identical to the 02-06 lock and adds zero new architectural surface. No user decision needed.

### 2. [Plan recorded trade-off] Closure-literal duplication

Not technically a deviation — plan §Step 4 explicitly accepted this and asked SUMMARY to document.

- `showPopover()` and `reloadPopoverContent()` each construct a `PopoverContentView` literal with the same 4 closure params. ~12 lines duplicated.
- **Why not extract:** Per CLAUDE.md `preserve original code`, an extracted helper would have to either capture `self` for `rowStates` mutation (tightening retain semantics) or take an `inout` snapshot (fighting value-type semantics). Both options expand the diff for marginal benefit. Decision: keep the duplication, document it.
- **If a future plan needs to break this:** the right factor is a `private func makeContent() -> PopoverContentView` method on `WidgetPopoverController` — `self` is already retained by `widgetController?` weak chain, and `rowStates` reads can be a snapshot at call time. Out of scope for 03-07.

## Threat Mitigation Status

All three threats from the plan's threat register are mitigated by the implemented code:

| Threat ID | Status | Where Mitigated |
|-----------|--------|-----------------|
| T-PITFALL-1 (carry) | mitigated | No `NSApp.activate(...)` introduced. Pre-existing rule still holds — `grep -c 'NSApp.activate' App/WidgetPopoverController.swift` → 0. |
| T-DOUBLE-CLEAROne | mitigated | `.ok` branch removes state from `rowStates` BEFORE calling `clearOne` + dismisses popover. Row's missing animation cannot fire because (a) the row's state map entry is gone, (b) the popover is closed. The two clearOne paths (`.ok` direct, `.missing` via animation) are mutually exclusive by state. |
| T-PERM-DENIED-RECOVERY | mitigated | `.permissionDenied` branch calls `PermissionDeepLink.openAutomationPreferences()` synchronously after the MainActor hop. Verified by grep #5 (count = 1 in this file). |

## Authentication Gates

None encountered.

## Known Stubs

None. All click paths now produce real, observable behavior:
- `.ok` jumps to iTerm2 via AppleScript (03-05) and clears the row.
- `.missing` collapses the row visually (03-06) and clears it.
- `.permissionDenied` jumps the user to System Settings → Privacy & Security → Automation.

## Self-Check: PASSED

Files written and verified to exist:
- `App/WidgetPopoverController.swift` — FOUND (modified, has jumper + rowStates + reloadPopoverContent + new onRowClick body; D2-08 [would-jump] literal removed)
- `App/AppDelegate.swift` — FOUND (modified, single-line edit at construction site)
- `.planning/phases/03-click-to-iterm2/03-07-SUMMARY.md` — FOUND (this file)

Commits verified to exist on `worktree-agent-a2f77f116202e80ef`:
- `0060adf` feat(03-07): wire jumper.jump + RowState orchestration in WidgetPopoverController — FOUND
- `837ce14` feat(03-07): pass ITerm2Jumper explicitly at WidgetPopoverController boot site — FOUND

## Notes for Downstream (03-08, 03-09, 03-10)

- **03-08 (SET-05 connection test button):** SettingsView reuses `AppleScriptHelper` — does NOT need a `TerminalJumper` instance. The `WidgetPopoverController.jumper` injection is purely for the popover row-click path.
- **03-09 (verifier):** Add a row asserting `grep -c '\[would-jump' App/WidgetPopoverController.swift` is 0, plus the `[jumped]`/`[jump-missed]`/`[jump-denied]`/`[jump-error]` 4-prefix scan from `App/ITerm2Jumper.swift` (live-OSLog filter).
- **03-10 (manual checkpoint):** SC#1 = open 3 iTerm2 tabs → fire 3 hooks → click each row → all 3 tabs surface; queue empties. SC#2 = open 1 iTerm2 tab → fire hook → close the tab → click the row → 도리도리+collapse animation runs → row vanishes; permission banner does NOT appear. SC#3 = revoke Automation perm in System Settings → fire hook → click row → 도리도리+collapse + System Settings opens to Privacy & Security → Automation.
