---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-08T02:27:45.979Z"
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 19
  completed_plans: 7
  percent: 37
---

# State: Claude Alert Bot

**Last updated:** 2026-05-07 (Phase 01 complete — phase_gate: green)

## Project Reference

- **What this is:** Native macOS app that turns Claude Code's `Stop` hook into a persistent floating widget that lands the user back on the exact iTerm2 tab where the work happened.
- **Core value:** "Claude Code 사용자가 자리를 비웠을 때, 길게 걸린 작업의 완료를 놓치지 않고 정확한 그 iTerm2 세션으로 즉시 복귀할 수 있다." — alert + correct-tab jump are the inseparable core; either failing destroys the value.
- **Current focus:** Phase 2 — alert-loop

## Current Position

Phase: 2 (alert-loop) — EXECUTING
Plan: 1 of 12
Next: Phase 02 (Alert Loop) — `/gsd-context-phase 2` to begin

- **Milestone:** v1
- **Phase:** 01 — Foundation, **all 7 plans complete**, Wave 3 closed, sign-off in `.planning/phases/01-foundation/01-VERIFICATION.md`
- **Plan:** 01-06 complete (e2e verifier wiring + 01-VERIFICATION.md sign-off — `phase_gate: green`, 14/14 verifier PASS, DIST-05 manual checkpoint approved with real Claude Code hook.log evidence)
- **Status:** Executing Phase 2
- **Progress:** `[█░░░░░] 1/6 phases complete (7/7 plans in Phase 01)`

## Performance Metrics

| Metric | Value |
|--------|-------|
| Phases complete | 1 / 6 |
| Plans complete | 7 / 7 in Phase 01 |
| Requirements covered | 10 / 53 (HOOK-01, HOOK-03, HOOK-04, HOOK-05, HOOK-06, IPC-01, IPC-02, IPC-03, DIST-01, DIST-05 — all Phase 1 requirements verified end-to-end with real Claude Code traffic) |
| Phase branch | master (no branching strategy per config.json) |
| Last plan duration | ~25 min (01-06, verifier sign-off — incl. inherited Task 1 from previous executor) |
| Phase 1 verifier runtime | ~35s end-to-end (incl. 16s build) |
| Reporter p95 latency | 232.6 ms (well within revised 250 ms budget) |
| hook.log lines at phase close | 114 |
| Real Claude Stop fires captured in checkpoint | 3 (real iTerm2 session UUID `w0t0p1:79C4699F-…`) |

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

- **Last action:** Completed Plan 01-06 (Wave 3 final — verify-phase-1.sh wiring + 01-VERIFICATION.md sign-off). 3 commits across 2 executor sessions:
  - `460b620` feat(01-06): wire verify-phase-1.sh against real Plan 01-05 artifacts (Task 1, previous executor)
  - `f3ab6e6` docs(01-06): record DIST-05 manual checkpoint result inline in verify-phase-1.sh (Task 2, this session)
  - `52b3af6` docs(01-06): add 01-VERIFICATION.md — Phase 1 sign-off (phase_gate: green) (Task 3, this session)

  Final verifier run: 14 pass, 0 fail, exit 0. DIST-05 manual checkpoint approved by user (`approved-A-with-observation`); both Part A (visual invisibility) and Part B (real Claude Code e2e — three real-Claude `event:stop` entries in hook.log carrying real iTerm2 session UUID `w0t0p1:79C4699F-7C77-4B92-B46A-10F818C00F8D` and `ppid_chain` proving real Claude origin) accepted. **Phase 01 closed: phase_gate green; Phase 02 unblocked.**

- **Files written this session:**
  - `scripts/verify-phase-1.sh` (modified — inline checkpoint result documentation in `verify_1_06_01`)
  - `.planning/phases/01-foundation/01-VERIFICATION.md` (created — Phase 1 sign-off, 142 lines)
  - `.planning/phases/01-foundation/01-06-SUMMARY.md` (created)
  - `.planning/STATE.md`, `.planning/ROADMAP.md` (updated — phase + plan progress)
- **Next action:** `/gsd-context-phase 2` (Phase 2 — Alert Loop). Phase 2 prerequisites surfaced in 01-06-SUMMARY: icon assets blocker (WIDG-03), sound-during-Focus/DnD strategy decision, threshold-default ratification.

### Open follow-ups (carried into later phases)

| ID | Description | Owner |
|----|-------------|-------|
| V-1 | `1-03-03` latency budget — already revised 50ms→250ms; verifier passes at 0.2326s | RESOLVED in Plan 02 |
| V-2 | Real-Claude OSLog grep listener-uptime polish — wrap real-Claude smoke test to keep listener up across the window so `event=stop` ingress lines are observable in real time | Phase-2-prep |
| V-3 | `dev-install-hook.sh --apply` JSON5 tolerance limit (trailing commas, single quotes, unquoted keys) | Phase 5 INST-04 |
| V-4 | `schema_version=2` envelopes silently dropped with warning — Phase 5 may surface to user | Phase 5 |
| V-5 | dev-install-hook.sh stopgap → in-app onboarding wizard | Phase 5 INST-01..04 + ONB-01 |
| V-6 | `--deep` regression guard preservation when swapping ad-hoc → Developer ID identity | Phase 6 release.sh |

### Phase 2 Pre-Entry Checklist

- [ ] Icon artwork (Anthropic-trademark-safe original) — STATE.md "Open Questions" / Phase 2 WIDG-03 prerequisite
- [ ] Sound-during-Focus/DnD strategy — recommended `UNNotificationSound` + `NSPanel` split; settle in Phase 2 plan decisions block
- [ ] Threshold default value (THR-01: 30s) ratified — Phase 1's measured Reporter latency (sub-250ms) confirms threshold operates on application-level elapsed time, not hook latency

---
*State initialized: 2026-05-07*
*Phase 01 closed: 2026-05-07 (phase_gate: green)*
