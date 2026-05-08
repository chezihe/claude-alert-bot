# 02-01 Spike Result — NSPopover composability with `.nonactivatingPanel`

**Spike date:** 2026-05-08
**macOS version:** 26.4.1 (Tahoe)
**Spike build:** Apple Swift version 6.2 (swiftlang-6.2.0.19.9 clang-1700.3.19.1)
**Observer:** user (dev machine, hands-on observation)
**Spike binary:** `/tmp/popover-spike` (ad-hoc signed Mach-O thin arm64, 125,040 bytes)

## Observations

### Pattern 8 — NSPopover

| Test | Result |
|------|--------|
| App appears in ⌘-Tab while popover open | NO |
| Keystrokes stolen from foreground app | NO |
| App still in ⌘-Tab after popover closes | NO |
| Notes | NSPopover with `.transient` behavior on a `.nonactivatingPanel` parent does NOT activate the parent app on macOS 26.4.1. Cmd-Tab pollution feared in RESEARCH §Pitfall #2 / advisor A1 risk did not materialize. |

### Pattern 8a — sibling NSPanel

| Test | Result |
|------|--------|
| App appears in ⌘-Tab while sibling panel visible | NO |
| Keystrokes stolen from foreground app | NO |
| App still in ⌘-Tab after sibling panel closes | NO |
| Notes | Sibling `.nonactivatingPanel` topology also clean — both topologies preserve LSUIElement invariant on macOS 26.4.1. Pattern 8a was not selected because Pattern 8 already passed. |

## Verdict

**Locked decision: Pattern 8**

**Rationale:** NSPopover with `behavior = .transient`, hosted via `popover.show(relativeTo:of:preferredEdge:)` on the contentView of a `.nonactivatingPanel`, did not pollute Cmd-Tab and did not steal keyboard focus from the foreground app. The A1 risk flagged in RESEARCH §Pitfall #2 + advisor's open question 3 was empirically disproven on macOS 26.4.1 (Tahoe) on the development Apple Silicon machine. We adopt Pattern 8 because it carries less code (no second NSPanel lifetime to manage), uses the AppKit-native popover machinery (auto positioning, pointer arrow, transient dismiss-on-outside-click), and matches the UI-SPEC §"Hover Popover" visual contract without extra positioning math.

## Downstream impact

- **Plan 02-07 (FloatingWidgetPanel + WindowController):** owns ONLY the widget panel. NSWindowController hosts the panel; popover is not its concern. No second NSPanel subclass introduced.
- **Plan 02-08 (Popover content):** an NSPopover whose `contentViewController` wraps a SwiftUI `NSHostingController(rootView: PopoverContentView())`. Triggered by mouseEntered on the widget panel's contentView; dismissed by `.transient` behavior or explicit `performClose(_:)`.
- **UI-SPEC §"Hover Popover" — `Implementation` row:** stays "NSPopover" — no change required. Visual contract (rounded card, divider, row layout) unaffected.

## Coverage caveat

The empirical run was performed on **macOS 26.4.1 only** (the developer's primary machine). Phase 6 (release) is the natural moment to re-verify on macOS 14 and macOS 15 if a tester is available; if NSPopover were to mis-behave on an earlier OS the fallback Pattern 8a topology is fully scoped here for reuse without re-running this spike.
