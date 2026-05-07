---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-07T08:00:00.000Z"
progress:
  total_phases: 6
  completed_phases: 0
  total_plans: 7
  completed_plans: 6
  percent: 14
---

# State: Claude Alert Bot

**Last updated:** 2026-05-07 (Plan 01-05 complete)

## Project Reference

- **What this is:** Native macOS app that turns Claude Code's `Stop` hook into a persistent floating widget that lands the user back on the exact iTerm2 tab where the work happened.
- **Core value:** "Claude Code 사용자가 자리를 비웠을 때, 길게 걸린 작업의 완료를 놓치지 않고 정확한 그 iTerm2 세션으로 즉시 복귀할 수 있다." — alert + correct-tab jump are the inseparable core; either failing destroys the value.
- **Current focus:** Phase 01 — foundation

## Current Position

Phase: 01 (foundation) — EXECUTING
Plan: 7 of 7 (next: 01-06 e2e verifier wiring — Wave 3 final)

- **Milestone:** v1
- **Phase:** 01 — Foundation, Wave 3 in progress (build.sh complete; 01-06 e2e verifier remaining)
- **Plan:** 01-05 complete (scripts/build.sh — xcodebuild archive + per-Mach-O ad-hoc codesign + verify; canonical output build/export/ClaudeAlertBot.app)
- **Status:** Executing Phase 01
- **Progress:** `[░░░░░░] 0/6 phases complete (6/7 plans in Phase 01)`

## Performance Metrics

| Metric | Value |
|--------|-------|
| Phases complete | 0 / 6 |
| Plans complete | 6 / 7 in Phase 01 |
| Requirements covered | 6 / 53 (DIST-05 + IPC-01 + IPC-02 + IPC-03 + HOOK-01 + DIST-01 e2e — Reporter→Listener confirmed; ad-hoc-signed .app launches on Apple Silicon with no cs_invalid_page; HOOK-03/04/05/06 implementation-side covered by Reporter/cab-report.sh and now verifier-checked end-to-end). |
| Phase branch | master (no branching strategy per config.json) |
| Last plan duration | ~5 min (01-05, scripts/build.sh — build itself takes ~16s) |

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

- **Last action:** Completed Plan 01-05 (Wave 3 scripts/build.sh). 1 commit: `97de952` (feat(01-05): add build.sh — xcodebuild archive + per-Mach-O ad-hoc codesign + verify). Live build: ~16s end-to-end; bundle/main/cab-test all `Signature=adhoc`; canonical output at `build/export/ClaudeAlertBot.app` (412KB). RESEARCH Success #3 verified: direct binary launch on Apple Silicon binds AF_UNIX socket, emits `listener bound` OSLog, no `cs_invalid_page` faults; SIGTERM clean shutdown. Plan 03's "Open Issue 4" (build path inconsistency) resolved — `build/export/` is the canonical, single output path.
- **Files written this session:**
  - `scripts/build.sh` (created, 71 lines, mode 0755)
  - `.planning/phases/01-foundation/01-05-SUMMARY.md` (created)
  - `.planning/STATE.md`, `.planning/ROADMAP.md` (updated — plan progress)
- **Next action:** Execute Plan 01-06 (Wave 3 e2e verifier wiring + 01-VERIFICATION.md sign-off). This is the final plan in Phase 1.

### Open follow-ups for Plan 01-06

- **1-03-03 latency budget overrun** (carried from Plan 02): harness `verify_1_03_03` enforces ≤ 0.050 s but `/usr/bin/python3` cold-start makes Reporter land at ~65 ms median / 138 ms p95. Recommendation: revise budget to 0.150 s.
- **1-04-01 / 1-02-01 cold-run sequencing** (NEW from Plan 03): the two rows depend on the app being already running, but verify-phase-1.sh's verify_1_05_01 launches and tears down the app via its own trap. When the suite is run cold, 1-02-01 and 1-04-01 always FAIL because no app is up. Recommended fix: launch the app once in a setup_ipc_tier function and tear down once in teardown_ipc_tier.
- **1-05-01 `pgrep -fc` unsupported** (NEW from Plan 03): BSD `pgrep` does not implement `-c` (count). The harness reads `count=$(pgrep -fc ClaudeAlertBot 2>/dev/null || echo 0)` which silently fails. Replace with `count=$(pgrep -f ClaudeAlertBot | wc -l | tr -d ' ')`.
- **JSON5 tolerance for --apply** (NEW from Plan 04): the dev-install-hook.sh JSON5 stripper is regex-based (handles `//` and `/* */` only). Trailing commas, single quotes, and unquoted keys cause refuse-to-mutate. Phase 5 INST-04 owns the proper fix; tracked here as a known dev-tool limitation.

---
*State initialized: 2026-05-07*
