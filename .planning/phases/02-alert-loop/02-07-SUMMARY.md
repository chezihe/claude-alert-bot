---
phase: 02-alert-loop
plan: 07
status: complete
completed: 2026-05-08
duration_minutes: 8
requirements: [WIDG-01, WIDG-02, WIDG-03, WIDG-04, WIDG-06, WIDG-07]
tags: [phase-2, wave-3, widget, nspanel, swiftui, ui-spec, positioning]
files_created:
  - App/FloatingWidgetPanel.swift
  - App/FloatingWidgetWindowController.swift
  - App/WidgetIconView.swift
  - ClaudeAlertBotTests/FloatingWidgetPanelTests.swift
  - ClaudeAlertBotTests/PositioningTests.swift
files_modified: []
key_decisions:
  - "FloatingWidgetPanel locked at .borderless | .nonactivatingPanel + level=.floating + collectionBehavior=[canJoinAllSpaces, fullScreenAuxiliary, stationary] (Pattern 7) — 7 unit tests prevent regression."
  - "WidgetPositioning.origin extracted as a pure free function inside FloatingWidgetPanel.swift — pure-function tests own the WIDG-06/WIDG-07 contract; controller reposition() is a thin caller of this function with NSScreen.main."
  - "Pattern 8 verdict from 02-01-SPIKE-RESULT honored: panel + icon view only in this plan; popover lives with the controller in 02-08. WidgetHoverDelegate protocol is the 02-07 → 02-08 seam (mouseEntered/mouseExited dispatch only)."
  - "SettingsStore is read at reposition() call time (each showWidget) — picks up Settings changes immediately per SET-03 without observer plumbing."
  - "Reduced-motion accessibility branch (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) skips both enter and exit animations — UI-SPEC §Accessibility honored."
---

# Plan 02-07 SUMMARY — FloatingWidgetPanel + WidgetWindowController

## What Shipped

Wave 3's AppKit widget surface — the concrete `WidgetControllerProtocol` implementation that 02-06's NotificationOrchestrator drives. Single floating NSPanel pinned across Spaces, never steals focus, hosts a SwiftUI WidgetIconView for the SF Symbol + optional +N badge. Position is computed by a pure function so unit tests own the corner+offset+notch math.

| File | Role | Status |
|------|------|--------|
| `App/FloatingWidgetPanel.swift` | `final class FloatingWidgetPanel: NSPanel` + `enum WidgetPositioning` (pure positioning function) | Created |
| `App/FloatingWidgetWindowController.swift` | `@MainActor final class FloatingWidgetWindowController: NSWindowController, WidgetControllerProtocol` + `WidgetHoverDelegate` protocol | Created |
| `App/WidgetIconView.swift` | SwiftUI `WidgetIconView` — bell.badge.fill 36pt + conditional +N badge | Created |
| `ClaudeAlertBotTests/FloatingWidgetPanelTests.swift` | 7 tests locking styleMask, level, collectionBehavior, canBecomeKey/Main, becomesKeyOnlyIfNeeded, hasShadow, isOpaque | Created |
| `ClaudeAlertBotTests/PositioningTests.swift` | 5 pure-function tests — 4 corners + safe-area clamp (notch awareness) | Created |

**Atomic commits on master:**
- `43628a2` — test(02-07): add failing FloatingWidgetPanel + Positioning tests (TDD RED)
- `ef11889` — feat(02-07): FloatingWidgetPanel + WidgetPositioning (WIDG-01,02,06,07)
- `3768035` — feat(02-07): WidgetIconView + FloatingWidgetWindowController (WIDG-03,04,05)

## Locked NSPanel Configuration (for 02-08 / 02-11 — do not re-derive)

```swift
styleMask          = [.borderless, .nonactivatingPanel]
level              = .floating
collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
becomesKeyOnlyIfNeeded   = true
hidesOnDeactivate        = false   // WIDG-04 — survives app deactivate
isMovableByWindowBackground = false
hasShadow                = true
isOpaque                 = false
backgroundColor          = .clear
acceptsMouseMovedEvents  = true    // for NSTrackingArea hover
canBecomeKey  = false              // override
canBecomeMain = false              // override
```

These values are anchored by `FloatingWidgetPanelTests`. Future plans (especially 02-08's NSPopover work and 02-11's AppDelegate boot) MUST NOT mutate these post-construction. If 02-08 needs the popover to receive transient mouse events independently, it should use `NSPopover.show(relativeTo:of:preferredEdge:)` against the panel's `contentView` per the spike verdict.

## WidgetHoverDelegate — Seam for 02-08

```swift
@MainActor protocol WidgetHoverDelegate: AnyObject {
    func widgetMouseEntered()
    func widgetMouseExited()
}
```

Declared at the top of `App/FloatingWidgetWindowController.swift`. The controller exposes a `weak var hoverDelegate: WidgetHoverDelegate?` property that 02-08 will set to its NSPopover-managing delegate. The controller installs `NSTrackingArea(options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect])` on the contentView and forwards `mouseEntered/mouseExited` to the delegate. **02-08 owns the hover-intent timing (150ms open / 250ms close grace).**

## queueSnapshot Getter

```swift
extension FloatingWidgetWindowController {
    var queueSnapshot: [CompletedSession] { currentQueue }
}
```

`setQueue(_:)` stores the latest queue array. 02-08 reads `controller.queueSnapshot` when building the popover's row list. The controller does NOT push the queue to the popover — pull-on-hover keeps coupling minimal and avoids re-render churn during background queue updates.

## Pattern 8 (NSPopover) — Downstream Plumbing for 02-08

Per `02-01-SPIKE-RESULT.md` (Locked decision: Pattern 8), 02-08 will:
1. Construct an `NSPopover` with `behavior = .transient`.
2. Set `contentViewController = NSHostingController(rootView: PopoverContentView(queue:onClick:onClearAll:))`.
3. Implement `WidgetHoverDelegate`:
   - `widgetMouseEntered()` → schedule 150ms `popover.show(relativeTo: hostingView.bounds, of: hostingView, preferredEdge: <derived from corner>)`
   - `widgetMouseExited()` → schedule 250ms `popover.performClose(nil)` (cancellable on re-enter).
4. Read `controller.queueSnapshot` at popover open time — no push subscription.

**No second sibling NSPanel is needed** (Pattern 8a was retired by the spike).

## NSPanel content view

`panel.contentView` is set to `NSHostingView(rootView: WidgetIconView(pendingCount: 0))` at controller init. `updateRootView(pendingCount:)` re-assigns `hostingView.rootView` on every show/update — SwiftUI diff handles the +N badge appearance. The hosting view's frame matches `panel.frame` (44×44pt). The NSTrackingArea is registered on the hosting view (not the panel directly) so it follows the SwiftUI hit area exactly.

If 02-08 ever needs to swap the content (e.g. for a richer hover state), the swap is `controller.window?.contentView = newHostingView` followed by `installTrackingArea(on: newHostingView)` — the tracking area is per-view, so re-registration is required.

## Reposition Behavior

```swift
private func reposition() {
    guard let screen = NSScreen.main else { return }
    let store = SettingsStore.shared
    let origin = WidgetPositioning.origin(
        visibleFrame: screen.visibleFrame,
        safeAreaInsets: screen.safeAreaInsets,
        corner: store.widgetCorner,
        offsetX: store.offsetX,
        offsetY: store.offsetY,
        panelSize: panel.frame.size
    )
    panel.setFrameOrigin(origin)
}
```

Called from `showWidget(...)` only. `updatePendingCount(...)` does NOT reposition (count change shouldn't move the widget). If the user changes corner/offset in Settings while the widget is hidden, the next `showWidget` picks it up. If the user changes them while visible, the widget's position becomes stale until the next showWidget — Phase 2 accepts this (Settings changes during a visible alert are a rare edge case; user can hover-dismiss-rehover to refresh).

`NSScreen.main` returns the screen of the currently active window — per D2-28 we lock the widget to "the main display at the moment it appears". Multi-display dynamic tracking is deferred to Phase 4+.

## Animation Contract

| Event | Behavior | Reduced-motion behavior |
|-------|----------|--------------------------|
| Enter (showWidget on hidden panel) | 200ms ease-in-out: alpha 0→1 + setFrameOrigin from y+4 → y | alpha = 1.0 instantly; no slide |
| Exit (hideWidget on visible panel) | 200ms ease-in-out: alpha 1→0 + setFrameOrigin from y → y+4, then orderOut on completion | alpha = 0.0 instantly; orderOut immediately |
| updatePendingCount | No animation (SwiftUI handles +N badge re-render) | Same |

`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` is read at every animation entry — runtime System Settings toggle takes effect on the next show/hide.

## Verification Run Results

| Verification | Command | Result |
|--------------|---------|--------|
| `verify_2_07_01` | `xcodebuild test -only-testing:ClaudeAlertBotTests/FloatingWidgetPanelTests -only-testing:ClaudeAlertBotTests/PositioningTests` | 12/12 pass (0.041s) |
| `verify_2_07_02` | `xcodebuild build -scheme ClaudeAlertBot` | BUILD SUCCEEDED |
| Full test target (regression) | `xcodebuild test -scheme ClaudeAlertBot` | 62/62 pass (was 50/50; +12 from this plan) |
| Protocol conformance grep | `grep -c 'class FloatingWidgetWindowController.*WidgetControllerProtocol' App/FloatingWidgetWindowController.swift` | 1 |
| LSUIElement invariant guard | `grep -c 'NSApp.activate' App/FloatingWidgetWindowController.swift App/FloatingWidgetPanel.swift App/WidgetIconView.swift` | 0 / 0 / 0 |
| Reduced-motion honor | `grep -c 'NSWorkspace.shared.accessibilityDisplayShouldReduceMotion' App/FloatingWidgetWindowController.swift` | 1 |

## Verifier Row Bodies (for 02-11 to graft into scripts/verify-phase-2.sh)

```bash
verify_2_07_01() {
    local id="2-07-01" name="FloatingWidgetPanel + Positioning (WIDG-01,02,06,07)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/FloatingWidgetPanelTests \
        -only-testing:ClaudeAlertBotTests/PositioningTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

verify_2_07_02() {
    local id="2-07-02" name="FloatingWidgetWindowController compiles + protocol conformance"
    if xcodebuild build -scheme ClaudeAlertBot -destination 'platform=macOS' > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "build failed — see /tmp/cab-test-out.log"
    fi
}
```

## Threat Model Closure

| Threat ID | Disposition | Closure |
|-----------|-------------|---------|
| T-FOCUS-01 | mitigate | `.nonactivatingPanel` styleMask + `canBecomeKey`/`canBecomeMain` overrides + `becomesKeyOnlyIfNeeded`. Tests 1, 4, 5 lock these. WidgetIconView is read-only — no Button/TextField in Phase 2. |
| T-MULTI-DISPLAY-01 | mitigate | reposition() called on every showWidget; uses NSScreen.main at call time. D2-28 locked: "위젯이 등장한 시점의 main display 기준 고정". Reconfig observer deferred to Phase 4+. |
| T-NOTCH-01 | mitigate | safeAreaInsets clamp via `max(ox, safe.right)` etc. PositioningTests `test_topRight_safeAreaWiderThanOffset` verifies notch top=38pt clamp; `test_topLeft_safeAreaApplied` + `test_bottomRight_safeAreaApplied` cover the other 3 corners. |
| T-LIFECYCLE-02 | accept | Both animations use NSAnimationContext groups; orderOut after exit is gated on the completion handler. Concurrent show/hide can produce a momentary flicker — accepted as Phase 2 polish item. Wave 6 e2e checkpoint may flag. |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — anti-pattern grep guard] Comment text triggered LSUIElement regression guard**
- **Found during:** Task 2 verification — `grep -c 'NSApp.activate' App/FloatingWidgetWindowController.swift` returned 1
- **Issue:** Source comment read `// LSUIElement invariant: NEVER call NSApp.activate(ignoringOtherApps:) (anti-pattern from RESEARCH).` — the literal symbol was present in the comment, which the plan's verification step requires to be 0 (regression guard against ever introducing the call).
- **Fix:** Rephrased the comment to `NEVER call activate(ignoringOtherApps:) on NSApp` so the literal `NSApp.activate` token does not appear in the file. Added a second comment line explaining why the literal symbol is intentionally absent (so a future maintainer doesn't "fix" the comment back).
- **Files modified:** `App/FloatingWidgetWindowController.swift` (comment text only)
- **Commit:** `3768035` (Task 2 GREEN — same atomic unit; no separate fix-up commit)

No production code deviations. Plan executed verbatim otherwise.

## TDD Gate Compliance

| Gate | Commit | Type |
|------|--------|------|
| RED (Task 1) | `43628a2` | `test(02-07)` |
| GREEN (Task 1) | `ef11889` | `feat(02-07)` |
| GREEN (Task 2) | `3768035` | `feat(02-07)` |

Task 2 has no RED gate per the plan's pragmatic carve-out (animation + AppKit lifecycle are best validated end-to-end at the 02-11 manual checkpoint; protocol conformance is checked at compile time; positioning math is already covered by Task 1's PositioningTests).

## Self-Check: PASSED

- [x] App/FloatingWidgetPanel.swift exists and compiles
- [x] App/FloatingWidgetWindowController.swift exists and compiles
- [x] App/WidgetIconView.swift exists and compiles
- [x] ClaudeAlertBotTests/FloatingWidgetPanelTests.swift exists (7/7 pass)
- [x] ClaudeAlertBotTests/PositioningTests.swift exists (5/5 pass)
- [x] `class FloatingWidgetWindowController.*WidgetControllerProtocol` — verified by grep (1)
- [x] `WidgetHoverDelegate` protocol declared in FloatingWidgetWindowController.swift
- [x] `NSApp.activate` literal absent from all 3 plan files (regression guard intact)
- [x] `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion` referenced (UI-SPEC §Accessibility)
- [x] WidgetPositioning.origin pure function in App/FloatingWidgetPanel.swift
- [x] Production xcodebuild build succeeds
- [x] Full test target run: 62/62 pass — no regressions (50 → 62)
- [x] git log: 3 commits on master (RED Task1 + GREEN Task1 + GREEN Task2)

## Commit-existence verification

```bash
git log --oneline | grep -E "43628a2|ef11889|3768035"
# 3768035 feat(02-07): WidgetIconView + FloatingWidgetWindowController (WIDG-03,04,05)
# ef11889 feat(02-07): FloatingWidgetPanel + WidgetPositioning (WIDG-01,02,06,07)
# 43628a2 test(02-07): add failing FloatingWidgetPanel + Positioning tests (TDD RED)
```

## Key Files

- `/Users/choijihye/Study/source/claude_alert_bot/App/FloatingWidgetPanel.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/App/FloatingWidgetWindowController.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/App/WidgetIconView.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/ClaudeAlertBotTests/FloatingWidgetPanelTests.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/ClaudeAlertBotTests/PositioningTests.swift`

## Next

Wave 4 unblocks: **02-08 (SettingsView + popover)** can now wire NSPopover content against `controller.queueSnapshot` and implement `WidgetHoverDelegate` (150ms open / 250ms close hover-intent). Wave 6 (02-11 AppDelegate wiring) follows the boot order documented in 02-06's SUMMARY:

```swift
let widget = FloatingWidgetWindowController()    // 02-07 — this plan
let orch = NotificationOrchestrator(widget: widget)  // 02-06
await SessionRegistry.shared.bind(notifier: orch)
await SessionRegistry.shared.restore()           // Pitfall #11 — BEFORE listener.start()
await listener.start()
```
