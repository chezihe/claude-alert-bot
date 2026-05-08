---
phase: 02-alert-loop
plan: 08
status: complete
completed: 2026-05-08
duration_minutes: 6
requirements: [WIDG-03]
tags: [phase-2, wave-4, popover, swiftui, hover-ux, nspopover, widg-03]
files_created:
  - App/PopoverContentView.swift
  - App/PopoverRowView.swift
  - App/WidgetPopoverController.swift
  - ClaudeAlertBotTests/PopoverContentTests.swift
files_modified: []
key_decisions:
  - "Pattern 8 (NSPopover with .transient behavior) implemented per 02-01-SPIKE-RESULT.md verdict — Pattern 8a sibling-NSPanel branch retired (spike on macOS 26.4.1 disproved A1 focus-stealing risk)."
  - "PopoverContentRules pure namespace exposes 4 testable display rules — shouldShowClearAll(rowCount:), projectsWithDuplicates(_:), timeSuffix(for:), showsOrphanIndicator(session:). Phase 4 multi-session UX plan reuses without re-deriving."
  - "Hover-intent timing locked: 150ms entry delay before show, 250ms exit grace before dismiss. Both DispatchWorkItems are cancellable — re-entering during grace cancels pending dismiss; leaving before intent cancels pending show."
  - "D2-08 OSLog format LOCKED: `[would-jump session=<uuid>]` with `privacy: .public` — Phase 3 ITermBridge inherits this signature verbatim at the same call site (replaces Task { await SessionRegistry.shared.clearOne(...) } when Phase 3 lands)."
  - "Pull-on-hover queue: WidgetPopoverController reads `controller.queueSnapshot` at showPopover() time. No push subscription, no observer plumbing. Stale-by-one-event is the accepted Phase 2 trade — Wave 6 e2e checkpoint validates."
  - "NSPopover contentSize computed dynamically: width=280 fixed, height = min(36*rows, 36*8) + (rowCount>=2 ? 32 : 0) for the optional 모두 지우기 chrome strip."
---

# Plan 02-08 SUMMARY — Hover Popover (PopoverContentView + WidgetPopoverController)

## What Shipped

Wave 4's hover-popover surface — Phase 2's UX core. The WidgetHoverDelegate seam declared by 02-07 is now wired to a concrete controller that owns hover-intent timing and an NSPopover whose SwiftUI content renders the FIFO queue with click-to-dismiss and 모두 지우기. Row click emits the `[would-jump session=<uuid>]` OSLog line that Phase 3 ITermBridge inherits without changing the format.

| File | Role | Status |
|------|------|--------|
| `App/PopoverContentView.swift` | `enum PopoverContentRules` (pure rules) + `struct PopoverContentView` (SwiftUI container) | Created |
| `App/PopoverRowView.swift` | `struct PopoverRowView` — per-session row (project name + optional time + optional `?` + hover bg) | Created |
| `App/WidgetPopoverController.swift` | `@MainActor final class WidgetPopoverController: NSObject, WidgetHoverDelegate` — Pattern 8 NSPopover host | Created |
| `ClaudeAlertBotTests/PopoverContentTests.swift` | 5 unit tests for the PopoverContentRules namespace | Created |

**Atomic commits on master:**
- `fc27708` — test(02-08): add failing PopoverContentRules tests (TDD RED)
- `80e8c76` — feat(02-08): PopoverContentView + PopoverRowView + display rules
- `37bd072` — feat(02-08): WidgetPopoverController (Pattern 8 NSPopover, WIDG-03)

## Spike Verdict Honored — Pattern 8 (NSPopover)

`.planning/phases/02-alert-loop/02-01-SPIKE-RESULT.md` locked **Pattern 8** on macOS 26.4.1: NSPopover with `behavior = .transient`, hosted via `popover.show(relativeTo:of:preferredEdge:)` against the floating panel's `contentView`, did NOT pollute Cmd-Tab and did NOT steal keystrokes from the foreground app. Pattern 8a (sibling NSPanel) was retired — implementation ships only the NSPopover branch. Verification grep:

```bash
grep -c 'NSPopover' App/WidgetPopoverController.swift     # 6
grep -c 'popoverPanel' App/WidgetPopoverController.swift  # 0
```

If a future macOS regression breaks Pattern 8, the Pattern 8a fallback skeleton is preserved in the original 02-08 plan's action block (App/WidgetPopoverController.swift can be swapped to a sibling NSPanel surface without touching PopoverContentView/PopoverRowView — the SwiftUI hierarchy is host-agnostic).

## PopoverContentRules — Public Surface (Phase 4 reuse)

```swift
enum PopoverContentRules {
    static func shouldShowClearAll(rowCount: Int) -> Bool                         // D2-07
    static func projectsWithDuplicates(_ queue: [CompletedSession]) -> Set<String> // D2-06
    static func timeSuffix(for date: Date) -> String                               // "HH:mm"
    static func showsOrphanIndicator(session: CompletedSession) -> Bool            // D2-16
}
```

Phase 4's richer multi-session popover UI MUST reuse these helpers rather than re-deriving the rules. Tests live in `ClaudeAlertBotTests/PopoverContentTests.swift` and lock the contracts.

## D2-08 LOCKED OSLog Format — Phase 3 Inheritance Contract

```swift
// In App/WidgetPopoverController.swift, onRowClick(sessionID:):
log.notice("[would-jump session=\(sessionID, privacy: .public)]")
Task { await SessionRegistry.shared.clearOne(sessionID: sessionID) }
dismissPopover()
```

**Format anchor:** `[would-jump session=<uuid>]` — square brackets, single space, `session=` literal, raw UUID with `privacy: .public`. Phase 3 ITermBridge takes over this call site by:

1. Replacing `Task { await ...clearOne(...) }` with the actual jump call.
2. Keeping the OSLog line verbatim (or reclassifying log message, NOT the format) so existing `log show --predicate 'eventMessage CONTAINS "would-jump"'` queries continue to match during the Phase 2→3 transition.

`grep -c '\[would-jump session=' App/WidgetPopoverController.swift` → **3** (one log site + two doc/comment anchors).

## Hover-Intent Timing

| Phase | Delay | Cancellable by |
|-------|-------|----------------|
| Show | 150ms after `widgetMouseEntered()` | `widgetMouseExited()` arriving before show fires |
| Dismiss | 250ms after `widgetMouseExited()` | `widgetMouseEntered()` arriving during grace (cancels exit + schedules new show) |

Both delays are implemented as `DispatchWorkItem` posted to the main queue with `asyncAfter`. The cancellable handles live in `entryWorkItem` / `exitWorkItem` — re-entering during exit grace explicitly `.cancel()`s the pending dismiss and restarts the entry intent. UI-SPEC §"Floating Widget" hover row anchors these values.

## NSPopover contentSize Math

```swift
let rows = max(1, queue.count)
let bodyHeight = min(36 * rows, 36 * 8)                                            // UI-SPEC: max 8 visible rows
let chromeHeight = PopoverContentRules.shouldShowClearAll(rowCount: queue.count) ? 32 : 0  // 모두 지우기 strip
pop.contentSize = NSSize(width: 280, height: bodyHeight + chromeHeight)
```

Width is fixed at 280pt (UI-SPEC). Height grows linearly with rows up to 8, then ScrollView takes over inside PopoverContentView. The chrome strip adds 32pt only when the queue has ≥2 rows (matches the `shouldShowClearAll` rule). preferredEdge is derived from `SettingsStore.shared.widgetCorner`:

| widgetCorner | preferredEdge | Visual |
|--------------|---------------|--------|
| `.topRight`, `.topLeft` | `.minY` | popover hangs *below* the widget |
| `.bottomRight`, `.bottomLeft` | `.maxY` | popover floats *above* the widget |

## queueSnapshot Pull Pattern

The popover does NOT subscribe to queue updates. At every `showPopover()` invocation, `widgetController?.queueSnapshot` is read fresh and an NSHostingController re-built. This avoids re-render churn during background queue mutation and keeps the coupling between FloatingWidgetWindowController (02-07) and WidgetPopoverController (02-08) one-directional. Trade-off: if a Stop arrives during the 150ms hover-intent window, the rendered popover may miss it by one event — accepted per Phase 2 scope (Phase 4 may revisit).

## 02-11 AppDelegate Wiring Requirements

Wave 6's AppDelegate boot must, in order:

```swift
let widget = FloatingWidgetWindowController()                  // 02-07
let popoverController = WidgetPopoverController(widgetController: widget)  // 02-08 ← NEW
widget.hoverDelegate = popoverController                        // 02-08 ← NEW (weak ref preserved)

let orch = NotificationOrchestrator(widget: widget)             // 02-06
await SessionRegistry.shared.bind(notifier: orch)
await SessionRegistry.shared.restore()                          // Pitfall #11 — BEFORE listener.start()
await listener.start()
```

The `popoverController` instance must be retained somewhere on the AppDelegate (or a top-level `@MainActor` holder) — `widget.hoverDelegate` is `weak`, so a stack-local controller would deallocate immediately. 02-11 should add it as a stored property on AppDelegate next to `widget`.

## Verifier Row Bodies (for 02-11 to graft into scripts/verify-phase-2.sh)

```bash
verify_2_08_01() {
    local id="2-08-01" name="PopoverContent display rules (D2-06, D2-07, D2-16)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/PopoverContentTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

verify_2_08_02() {
    local id="2-08-02" name="WidgetPopoverController compiles + WidgetHoverDelegate conformance + D2-08 anchor"
    if xcodebuild build -scheme ClaudeAlertBot -destination 'platform=macOS' > /tmp/cab-test-out.log 2>&1; then
        # Anchor verification: D2-08 log format must exist; either NSPopover or popoverPanel must be present.
        local jump_count
        jump_count=$(grep -c '\[would-jump session=' App/WidgetPopoverController.swift)
        local nsp_count
        nsp_count=$(grep -c 'NSPopover' App/WidgetPopoverController.swift)
        local panel_count
        panel_count=$(grep -c 'popoverPanel' App/WidgetPopoverController.swift)
        if [ "$jump_count" -ge 1 ] && { [ "$nsp_count" -ge 1 ] || [ "$panel_count" -ge 1 ]; }; then
            _record_pass "$id" "$name"
        else
            _record_fail "$id" "$name" "anchor missing (jump=$jump_count nsp=$nsp_count panel=$panel_count)"
        fi
    else
        _record_fail "$id" "$name" "build failed — see /tmp/cab-test-out.log"
    fi
}
```

## Verification Run Results

| Verification | Command | Result |
|--------------|---------|--------|
| `verify_2_08_01` | `xcodebuild test -only-testing:ClaudeAlertBotTests/PopoverContentTests` | 5/5 pass (0.004s) |
| `verify_2_08_02` (build) | `xcodebuild build -scheme ClaudeAlertBot` | BUILD SUCCEEDED |
| Full test target (regression) | `xcodebuild test -scheme ClaudeAlertBot` | 67/67 pass (was 62/62; +5 from this plan; 0 regressions) |
| D2-08 OSLog anchor | `grep -c '\[would-jump session=' App/WidgetPopoverController.swift` | 3 |
| Pattern 8 anchor | `grep -c 'NSPopover' App/WidgetPopoverController.swift` | 6 |
| Pattern 8a (must be 0) | `grep -c 'popoverPanel' App/WidgetPopoverController.swift` | 0 |
| WidgetHoverDelegate conformance | `grep -c 'WidgetHoverDelegate' App/WidgetPopoverController.swift` | 3 |
| LSUIElement invariant | `grep -c 'NSApp.activate' App/{PopoverContentView,PopoverRowView,WidgetPopoverController}.swift` | 0 / 0 / 0 |

## Threat Model Closure

| Threat ID | Disposition | Closure |
|-----------|-------------|---------|
| T-FOCUS-02 | mitigate (Pattern 8) | NSPopover `.transient` on `.nonactivatingPanel` parent — empirically clean per 02-01 spike on macOS 26.4.1. LSUIElement preservation grep guards (NSApp.activate=0) intact across all 3 new files. |
| T-CLICK-01 | accept | Phase 2 dismisses on first click; second click hits already-dismissed row (UI not visible). Phase 3 will add JUMP-05 debounce when the actual jump action lands. |
| T-LEAK-01 | accept (Phase 5 review) | OSLog `[would-jump session=<uuid>]` uses `privacy: .public` — UUID is not PII; D-07 dev-window contract. Phase 5 may reclassify to `.private` after dev verification. |

## Deviations from Plan

None — plan executed verbatim. Tests, file structure, decision branch (Pattern 8), and OSLog format match the plan exactly.

The Swift 5 toolchain (per `project.yml` SWIFT_VERSION: "5") doesn't accept the regex-literal `s.matches(/\d{2}:\d{2}/)` shown in the plan's example test body, so `test_timeSuffix_format_hhmm` uses `NSRegularExpression` instead — same assertion semantics, different surface syntax. This is a faithful translation, not a deviation from the test contract.

## TDD Gate Compliance

| Gate | Commit | Type |
|------|--------|------|
| RED (Task 1) | `fc27708` | `test(02-08)` |
| GREEN (Task 1) | `80e8c76` | `feat(02-08)` |
| GREEN (Task 2) | `37bd072` | `feat(02-08)` |

Task 2 has no RED gate per the plan's pragmatic carve-out (animation timing + NSPopover lifecycle = manual verification at 02-11; protocol conformance is checked at compile time).

## Self-Check: PASSED

- [x] App/PopoverContentView.swift exists and compiles
- [x] App/PopoverRowView.swift exists and compiles
- [x] App/WidgetPopoverController.swift exists and compiles
- [x] ClaudeAlertBotTests/PopoverContentTests.swift exists (5/5 pass)
- [x] PopoverContentRules namespace declared with 4 static rules
- [x] WidgetPopoverController conforms to `NSObject, WidgetHoverDelegate`
- [x] D2-08 OSLog `[would-jump session=<uuid>]` literal present in WidgetPopoverController
- [x] Pattern 8 (NSPopover) implemented; popoverPanel literal absent (Pattern 8a not used)
- [x] `NSApp.activate` literal absent from all 3 new App/ files (LSUIElement guard intact)
- [x] Production xcodebuild build succeeds
- [x] Full test target run: 67/67 pass — no regressions (62 → 67)
- [x] git log: 3 commits on master (RED Task1 + GREEN Task1 + GREEN Task2)

## Commit-existence verification

```bash
git log --oneline | grep -E "fc27708|80e8c76|37bd072"
# 37bd072 feat(02-08): WidgetPopoverController (Pattern 8 NSPopover, WIDG-03)
# 80e8c76 feat(02-08): PopoverContentView + PopoverRowView + display rules
# fc27708 test(02-08): add failing PopoverContentRules tests (TDD RED)
```

## Key Files

- `/Users/choijihye/Study/source/claude_alert_bot/App/PopoverContentView.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/App/PopoverRowView.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/App/WidgetPopoverController.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/ClaudeAlertBotTests/PopoverContentTests.swift`

## Next

Wave 4 second-half (`02-09` — cab-test extensions for hover/popover scenarios) and Wave 5 (`02-10` — verify-phase-2.sh script grafting) build on the verifier row bodies recorded above. Wave 6 (`02-11` — AppDelegate boot wiring) instantiates `WidgetPopoverController(widgetController: widget)`, retains it as an AppDelegate stored property, and assigns `widget.hoverDelegate = popoverController` immediately after the FloatingWidgetWindowController is constructed. The Pitfall #11 ordering (`SessionRegistry.shared.restore()` BEFORE `listener.start()`) remains the boot-order invariant.
