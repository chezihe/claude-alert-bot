# State: Claude Alert Bot

**Last updated:** 2026-05-07

## Project Reference

- **What this is:** Native macOS app that turns Claude Code's `Stop` hook into a persistent floating widget that lands the user back on the exact iTerm2 tab where the work happened.
- **Core value:** "Claude Code 사용자가 자리를 비웠을 때, 길게 걸린 작업의 완료를 놓치지 않고 정확한 그 iTerm2 세션으로 즉시 복귀할 수 있다." — alert + correct-tab jump are the inseparable core; either failing destroys the value.
- **Current focus:** Roadmap defined. About to plan Phase 1 (Foundation).

## Current Position

- **Milestone:** v1
- **Phase:** Pre-Phase 1 (roadmap just created)
- **Plan:** None yet
- **Status:** Awaiting `/gsd-plan-phase 1`
- **Progress:** `[░░░░░░] 0/6 phases complete`

## Performance Metrics

| Metric | Value |
|--------|-------|
| Phases complete | 0 / 6 |
| Plans complete | 0 / 0 (none planned yet) |
| Requirements covered | 0 / 53 (mapped, not yet built) |
| Phase branch | none yet |

## Accumulated Context

### Locked Decisions (from research, ratified by roadmap)

| Decision | Source | Locked at |
|----------|--------|-----------|
| Hook script always exits 0 (never `exit 2`) | PITFALLS.md #1 | Roadmap (Phase 1 acceptance) |
| Two hooks installed: Stop + UserPromptSubmit | ARCHITECTURE.md Pattern 2 | Roadmap |
| Ad-hoc `codesign -s -` in build pipeline from day one | PITFALLS.md #2 | Roadmap (Phase 1 acceptance) |
| AppleScript lookup by `unique ID` UUID, never by index | ARCHITECTURE.md Pattern 3 / PITFALLS #4 | Roadmap (Phase 3 constraint) |
| Session match: UUID → TTY → friendly error (never wrong-jump) | ARCHITECTURE.md Session Identity | Roadmap (Phase 3 acceptance) |
| `NSPanel` subclass with `.nonactivatingPanel` + correct collectionBehavior | PITFALLS.md #1 / STACK.md | Roadmap (Phase 2 acceptance) |
| `NSAppleEventsUsageDescription` with specific user-trustworthy text | PITFALLS.md #3 | Roadmap (Phase 3 acceptance) |
| AppleScript on background queue + 3s hard timeout + click debounce | PITFALLS.md #10 | Roadmap (Phase 3 acceptance) |
| AF_UNIX socket via `Network.framework` for hook→app IPC | STACK.md / ARCHITECTURE.md | Roadmap (Phase 1) |
| Swift `actor` SessionRegistry; stress-test at Phase 4 | PITFALLS.md #9 / ARCHITECTURE.md | Roadmap |
| Min OS macOS 14 Sonoma | STACK.md | Roadmap |

### Open Questions (carried into planning)

- **Phase 3:** `ITERM_SESSION_ID` behavior under tmux/nix-shell/containers — to be characterized using Phase 1's `hook.log` data once real usage accrues. Phase 3 research-phase will run a tmux/venv/nested-shell test matrix.
- **Phase 3:** AppleScript `unique ID` lookup latency under typical pane counts — needs a 5-line probe script during Phase 3 planning.
- **Phase 6:** Exact macOS 14/15/26 Gatekeeper dialog wording for ad-hoc-signed-but-quarantined app. README must reflect what users actually see.
- **Pre-Phase 2 decision required:** Sound during Focus/DnD strategy — recommended (a) `UNNotificationSound` for audio + `NSPanel` for visual. Settle in Phase 2 plan.

### Todos / Follow-ups

- [ ] Update PROJECT.md "Constraints" section: replace "우클릭 → 열기" with macOS 14/15+ split (System Settings → Privacy & Security → Open Anyway) — done at Phase 6, but PROJECT.md text should be touched up at Phase 5/6 boundary.

### Blockers

None.

## Session Continuity

- **Last action:** Roadmap created (6 phases, 53/53 requirements mapped, 100% coverage).
- **Files written this session:**
  - `.planning/ROADMAP.md`
  - `.planning/STATE.md` (this file)
  - `.planning/REQUIREMENTS.md` (Traceability section updated)
- **Next action:** `/gsd-plan-phase 1` — plan Phase 1 (Foundation).

---
*State initialized: 2026-05-07*
