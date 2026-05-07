---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-07T08:30:00.000Z"
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 7
  completed_plans: 5
  percent: 12
---

# State: Claude Alert Bot

**Last updated:** 2026-05-07 (Plan 01-04 complete)

## Project Reference

- **What this is:** Native macOS app that turns Claude Code's `Stop` hook into a persistent floating widget that lands the user back on the exact iTerm2 tab where the work happened.
- **Core value:** "Claude Code 사용자가 자리를 비웠을 때, 길게 걸린 작업의 완료를 놓치지 않고 정확한 그 iTerm2 세션으로 즉시 복귀할 수 있다." — alert + correct-tab jump are the inseparable core; either failing destroys the value.
- **Current focus:** Phase 01 — foundation

## Current Position

Phase: 01 (foundation) — EXECUTING
Plan: 6 of 7 (next: 01-05 build.sh — Wave 3)

- **Milestone:** v1
- **Phase:** 01 — Foundation, Wave 2 complete (App listener + dev-install-hook.sh)
- **Plan:** 01-04 complete (scripts/dev-install-hook.sh — D-04 user-data copy + idempotent ~/.claude/settings.json merge)
- **Status:** Executing Phase 01
- **Progress:** `[░░░░░░] 0/6 phases complete (5/7 plans in Phase 01)`

## Performance Metrics

| Metric | Value |
|--------|-------|
| Phases complete | 0 / 6 |
| Plans complete | 5 / 7 in Phase 01 |
| Requirements covered | 5 / 53 (DIST-05 + IPC-01 + IPC-02 + IPC-03 + HOOK-01 e2e — Reporter→Listener confirmed; HOOK-03/04/05/06 implementation-side covered by Reporter/cab-report.sh and now verifier-checked end-to-end). Plan 01-04 unblocks but does not satisfy any v1 REQ — its content is fully under Phase 5 INST-01..04 (deferred per D-05). |
| Phase branch | master (no branching strategy per config.json) |
| Last plan duration | ~5 min (01-04, dev-install-hook.sh) |

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

- **Last action:** Completed Plan 01-04 (Wave 2 dev-install-hook.sh). 1 commit: `baaf33e` (feat(01-04): add dev-install-hook.sh for hook registration). Three modes verified live: default-print, --apply (idempotent), --check. Idempotency proven via two-fire test on tempdir HOME — Stop=1 + UserPromptSubmit=1 cab-report registrations after re-run; unrelated `Stop /usr/bin/true` entry preserved; top-level `model: sonnet` key untouched.
- **Files written this session:**
  - `scripts/dev-install-hook.sh` (created, 151 lines, mode 0755)
  - `.planning/phases/01-foundation/01-04-SUMMARY.md` (created)
  - `.planning/STATE.md`, `.planning/ROADMAP.md` (updated — plan progress)
- **Next action:** Execute Plan 01-05 (Wave 3 scripts/build.sh — xcodebuild archive + per-Mach-O ad-hoc codesign + verification). Wave 2 is now complete and Wave 3 unblocked.

### Open follow-ups for Plan 01-06

- **1-03-03 latency budget overrun** (carried from Plan 02): harness `verify_1_03_03` enforces ≤ 0.050 s but `/usr/bin/python3` cold-start makes Reporter land at ~65 ms median / 138 ms p95. Recommendation: revise budget to 0.150 s.
- **1-04-01 / 1-02-01 cold-run sequencing** (NEW from Plan 03): the two rows depend on the app being already running, but verify-phase-1.sh's verify_1_05_01 launches and tears down the app via its own trap. When the suite is run cold, 1-02-01 and 1-04-01 always FAIL because no app is up. Recommended fix: launch the app once in a setup_ipc_tier function and tear down once in teardown_ipc_tier.
- **1-05-01 `pgrep -fc` unsupported** (NEW from Plan 03): BSD `pgrep` does not implement `-c` (count). The harness reads `count=$(pgrep -fc ClaudeAlertBot 2>/dev/null || echo 0)` which silently fails. Replace with `count=$(pgrep -f ClaudeAlertBot | wc -l | tr -d ' ')`.
- **JSON5 tolerance for --apply** (NEW from Plan 04): the dev-install-hook.sh JSON5 stripper is regex-based (handles `//` and `/* */` only). Trailing commas, single quotes, and unquoted keys cause refuse-to-mutate. Phase 5 INST-04 owns the proper fix; tracked here as a known dev-tool limitation.

---
*State initialized: 2026-05-07*
