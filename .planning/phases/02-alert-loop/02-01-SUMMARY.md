---
phase: 02-alert-loop
plan: 01
status: complete
completed: 2026-05-08
requirements: [WIDG-02]
---

# Plan 02-01 SUMMARY — NSPopover Composability Spike

## What Shipped

A throwaway LSUIElement spike that demonstrated both Pattern 8 (NSPopover) and Pattern 8a (sibling NSPanel) topologies in a single binary, hands-on observation by the user on the dev machine, and a locked verdict consumed by Wave 3.

| Artifact | Status |
|----------|--------|
| `Spike/PopoverSpike/main.swift` + `SpikeAppDelegate.swift` | Created, used, **deleted** (throwaway) |
| `/tmp/popover-spike` (ad-hoc signed binary) | Built, run, deleted |
| `.planning/phases/02-alert-loop/02-01-SPIKE-RESULT.md` | Created — load-bearing artifact for Wave 3 |

## Build Commands Used

```bash
swiftc Spike/PopoverSpike/main.swift Spike/PopoverSpike/SpikeAppDelegate.swift \
  -o /tmp/popover-spike -framework AppKit
codesign --force --sign - /tmp/popover-spike
```

Output: Mach-O thin arm64, 125,040 bytes, ad-hoc signed (`Signature=adhoc`), Identifier `popover-spike-55554944548775decd033f439277216019206da4`.

## Locked Verdict

**Pattern 8 (NSPopover)** — observed safe on **macOS 26.4.1 (Tahoe)**.

NSPopover with `.transient` behavior, hosted on a `.nonactivatingPanel` parent, did NOT activate the parent app:
- No Cmd-Tab pollution
- No keyboard focus theft from foreground app
- Same negative result observed in both Pattern 8 (popover) and Pattern 8a (sibling NSPanel) → Pattern 8 wins on simplicity (no second panel lifetime to manage).

The A1 risk flagged by RESEARCH §Pitfall #2 + advisor was empirically disproven on this OS.

## Pointer for Wave 3

> **Wave 3 plans 02-07 (FloatingWidgetPanel + WindowController) and 02-08 (Popover content) MUST read `.planning/phases/02-alert-loop/02-01-SPIKE-RESULT.md` §Verdict + §Downstream impact before starting tasks.** The verdict is grounded in observed Cmd-Tab + keyboard-focus behavior recorded there, not theoretical reasoning.

## Coverage Caveat

Verified on macOS 26.4.1 only. Phase 6 (release) is the natural re-verify point for macOS 14 + 15 compatibility. If Pattern 8 were to mis-behave there, Pattern 8a's full topology is scoped in SPIKE-RESULT.md ready for swap-in without re-running this spike.

## Notes on Cleanup

`Spike/PopoverSpike/` directory was deleted post-observation per the plan's contract ("the spike was throwaway by definition; only SPIKE-RESULT.md outlives it"). Verified: `ls Spike/` → No such file or directory. The `/tmp/popover-spike` binary was also removed.

## Self-Check: PASSED

- [x] Spike binary built and ad-hoc signed (Apple Silicon launchable invariant)
- [x] User-observed Cmd-Tab + keyboard-focus behavior captured in SPIKE-RESULT.md
- [x] Verdict line `**Locked decision: Pattern 8**` present in SPIKE-RESULT.md
- [x] Wave 3 downstream impact section populated (02-07 + 02-08 + UI-SPEC notes)
- [x] `Spike/PopoverSpike/` directory does NOT exist (cleanup confirmed)
- [x] Verdict is `pattern-8` (not `inconclusive`)
