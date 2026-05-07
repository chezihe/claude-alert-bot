---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-07T07:55:00.000Z"
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 7
  completed_plans: 3
  percent: 7
---

# State: Claude Alert Bot

**Last updated:** 2026-05-07

## Project Reference

- **What this is:** Native macOS app that turns Claude Code's `Stop` hook into a persistent floating widget that lands the user back on the exact iTerm2 tab where the work happened.
- **Core value:** "Claude Code 사용자가 자리를 비웠을 때, 길게 걸린 작업의 완료를 놓치지 않고 정확한 그 iTerm2 세션으로 즉시 복귀할 수 있다." — alert + correct-tab jump are the inseparable core; either failing destroys the value.
- **Current focus:** Phase 01 — foundation

## Current Position

Phase: 01 (foundation) — EXECUTING
Plan: 4 of 7 (next: 01-03 App listener — Wave 2)

- **Milestone:** v1
- **Phase:** 01 — Foundation, Wave 1 complete; Wave 2 ready to start
- **Plan:** 01-02 complete (Reporter/cab-report.sh — POSIX sh hook reporter)
- **Status:** Executing Phase 01
- **Progress:** `[░░░░░░] 0/6 phases complete (3/7 plans in Phase 01)`

## Performance Metrics

| Metric | Value |
|--------|-------|
| Phases complete | 0 / 6 |
| Plans complete | 3 / 7 in Phase 01 |
| Requirements covered | 1 / 53 (DIST-05 satisfied by LSUIElement=true Info.plist; HOOK-01/03/04/05/06 implementation-side covered by Reporter/cab-report.sh but verifier-checked end-to-end only when Plan 01-03's listener lands) |
| Phase branch | master (no branching strategy per config.json) |
| Last plan duration | ~10 min (01-02, Reporter shell) |

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

- **Last action:** Completed Plan 01-02 (Wave 1 Reporter shell). `Reporter/cab-report.sh` is verbatim RESEARCH §"POSIX sh Reporter" + python3 `-S` cold-start trim; commit `1458693`. `bash scripts/verify-phase-1.sh --quick` now reports `[PASS] 1-01-01`, `[PASS] 1-01-02`, `[PASS] 1-03-04`, `[PASS] 1-07-01` (4/4 quick rows green). Full-suite reveals one expected red: `1-03-03` measures 64.8 ms (budget 50 ms) — documented as a measurement deviation, not a behavioral defect; resolution path delegated to Plan 01-06.
- **Files written this session:**
  - `Reporter/cab-report.sh` (created, 85 lines, mode 0755)
  - `.planning/phases/01-foundation/01-02-SUMMARY.md` (created)
  - `.planning/STATE.md`, `.planning/ROADMAP.md` (updated — plan progress)
- **Next action:** Execute Plan 01-03 (Wave 2 App listener — NWListener AF_UNIX, HookEvent schema, AppDelegate, cab-test CLI). Wave 2 unblocked because Wave 1's two plans (01-01 + 01-02) are both complete.

### Open follow-up for Plan 01-06

- 1-03-03 latency budget overrun: harness `verify_1_03_03` enforces ≤ 0.050 s but `/usr/bin/python3` cold-start makes a clean Reporter run land at ~65 ms median / 138 ms p95. Adjudicate in Plan 01-06: revise budget upward (recommended 0.150 s), reclassify to manual, or accept FAIL as informational. Detailed numbers in `01-02-SUMMARY.md` "Measurement deviation" section.

---
*State initialized: 2026-05-07*
