---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-08T03:23:22.706Z"
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 19
  completed_plans: 9
  percent: 47
---

# State: Claude Alert Bot

**Last updated:** 2026-05-08 (Phase 02 Wave 0 — Plan 02-02 complete: D2-33 Korean copy + D2-36 PermissionDeepLink)

## Project Reference

- **What this is:** Native macOS app that turns Claude Code's `Stop` hook into a persistent floating widget that lands the user back on the exact iTerm2 tab where the work happened.
- **Core value:** "Claude Code 사용자가 자리를 비웠을 때, 길게 걸린 작업의 완료를 놓치지 않고 정확한 그 iTerm2 세션으로 즉시 복귀할 수 있다." — alert + correct-tab jump are the inseparable core; either failing destroys the value.
- **Current focus:** Phase 2 — alert-loop

## Current Position

Phase: 2 (alert-loop) — EXECUTING
Plan: 3 of 12 (next: 02-01)
Next: Continue Phase 02 — execute 02-01 (Wave 1 SwiftUI app shell pre-req for D2-29)

- **Milestone:** v1
- **Phase:** 02 — Alert Loop, Plans 02-00 + 02-02 complete (Wave 0). 10 plans remain.
- **Plan:** 02-02 complete (D2-33 Korean NSAppleEventsUsageDescription locked in Info.plist + project.yml; D2-36 PermissionDeepLink helper shipped with 2 passing regression tests; Phase 1 reclaimSocketIfStale double-leave race fixed as Rule 1).
- **Status:** Executing Phase 2
- **Progress:** [█████░░░░░] 47%

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
| Plan 02-02 metrics | 30 min duration · 2 tasks · 5 files (2 created, 3 modified) · 4 commits (RED + Rule-1 fix + GREEN + Korean copy) |

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
| ENABLE_TESTABILITY scoped to Debug only (Release untouched) | 02-00 | Plan 02-00 (T-TEST-01 disposition) |
| cab-test detection heuristic = `strings \| grep -- '--event='` literal (not symbol name; Swift inlines `private` funcs) | 02-00 | Plan 02-00 (verify-phase-2.sh row 2-00-02) |
| D2-33 Korean NSAppleEventsUsageDescription verbatim in App/Info.plist + project.yml (drift-proof via xcodegen anti-regression test) | 02-CONTEXT D2-33 | Plan 02-02 (T-PERM-01 mitigation) |
| D2-36 sequential System Settings deep-link URL list (Sequoia → Ventura → root) regression-guarded by PermissionDeepLinkTests | 02-CONTEXT D2-36 | Plan 02-02 (T-DEEP-LINK-01 mitigation) |
| reclaimSocketIfStale uses idempotent `leftOnce` guard against double dispatch_group_leave (NWConnection state handlers fire repeatedly on `.cancelled`/`.failed`) | 02-02 | Plan 02-02 (Rule 1 fix; supersedes 02-00 SUMMARY's operational SKIP workaround) |

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

- **Last action:** Completed Plan 02-02 (Phase 2 Wave 0 — D2-33 Korean copy + D2-36 PermissionDeepLink). 4 commits on master (sequential mode):
  - `c400a1f` test(02-02): add failing PermissionDeepLink URL list regression test (TDD RED)
  - `d5de896` fix(02-02): guard reclaimSocketIfStale against double dispatch_group_leave (Rule 1)
  - `dadf6c8` feat(02-02): ship PermissionDeepLink with sequential URL fallback (TDD GREEN)
  - `cf26d5f` feat(02-02): NSAppleEventsUsageDescription Korean copy per D2-33

  Final verifications: `xcodebuild test -only-testing:ClaudeAlertBotTests/PermissionDeepLinkTests` → ** TEST SUCCEEDED **, 2/2 passed (3 consecutive runs after Rule 1 fix landed). `plutil -lint App/Info.plist` → OK. `/usr/libexec/PlistBuddy -c "Print :NSAppleEventsUsageDescription" App/Info.plist` → Korean copy. `xcodegen generate` does not revert Korean copy (anti-regression evidence captured in SUMMARY).

  New decisions logged: 02-02-D1..D4 (urls as static let; verify-phase-2.sh ownership stays with 02-11; Rule 1 fix here vs deferred; idempotent Bool flag minimum surgery).

- **Files written this plan:**
  - `App/PermissionDeepLink.swift` (created — D2-36 helper)
  - `ClaudeAlertBotTests/PermissionDeepLinkTests.swift` (created — D2-36 regression guard)
  - `App/Info.plist` (modified — NSAppleEventsUsageDescription → Korean per D2-33)
  - `project.yml` (modified — same Korean string)
  - `App/AppDelegate.swift` (modified — Rule 1 idempotent leftOnce guard in reclaimSocketIfStale)
  - `ClaudeAlertBot.xcodeproj/project.pbxproj` (xcodegen-regenerated for new files)
  - `.planning/phases/02-alert-loop/02-02-SUMMARY.md` (created)
  - `.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md` (updated — plan progress + WIDG-02 marked complete)
- **Next action:** Execute Plan 02-01 (Wave 1 — SwiftUI app shell pre-req for D2-29 SettingsStore @AppStorage scene).

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
