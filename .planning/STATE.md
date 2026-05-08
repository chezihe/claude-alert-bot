---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-08T07:34:58Z"
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 19
  completed_plans: 10
  percent: 53
---

# State: Claude Alert Bot

**Last updated:** 2026-05-08 (Phase 02 Wave 2 — Plan 02-04 complete: SessionRegistry actor + SessionStore atomic persistence; SESS-01..04, THR-01/02 satisfied; AUD-01 partial)

## Project Reference

- **What this is:** Native macOS app that turns Claude Code's `Stop` hook into a persistent floating widget that lands the user back on the exact iTerm2 tab where the work happened.
- **Core value:** "Claude Code 사용자가 자리를 비웠을 때, 길게 걸린 작업의 완료를 놓치지 않고 정확한 그 iTerm2 세션으로 즉시 복귀할 수 있다." — alert + correct-tab jump are the inseparable core; either failing destroys the value.
- **Current focus:** Phase 2 — alert-loop

## Current Position

Phase: 2 (alert-loop) — EXECUTING
Plan: 5 of 12 complete (Wave 0: 02-00 + 02-01 spike; Wave 1: 02-02 + 02-03; Wave 2: 02-04). Next executable: 02-05 (Wave 2 AppleScriptHelper actor).
Next: Execute 02-05 — AppleScriptHelper actor (compile-once, 1s timeout, error classification, state mirror) — provides the `suppressIfFrontmost` closure body that 02-04's ingest() exposes.

- **Milestone:** v1
- **Phase:** 02 — Alert Loop, 5/12 plans complete. 7 plans remain.
- **Plan:** 02-04 complete (SessionRegistry actor + SessionStore atomic persistence). Public API frozen for downstream consumers (Wave 3 NotificationOrchestrator, Wave 4 observers, Wave 5 SettingsView injectTest, Wave 6 AppDelegate restore-then-listener boot order).
- **Status:** Executing Phase 2
- **Progress:** [█████░░░░░] 53%

## Performance Metrics

| Metric | Value |
|--------|-------|
| Phases complete | 1 / 6 |
| Plans complete | 7 / 7 in Phase 01 + 5 / 12 in Phase 02 |
| Requirements covered | 16 / 53 (Phase 1: HOOK-01, HOOK-03, HOOK-04, HOOK-05, HOOK-06, IPC-01, IPC-02, IPC-03, DIST-01, DIST-05 + Phase 2: SESS-01..04, THR-01..02; AUD-01 partial — actual sound playback in 02-06) |
| Phase branch | master (no branching strategy per config.json) |
| Last plan duration | ~25 min (01-06, verifier sign-off — incl. inherited Task 1 from previous executor) |
| Phase 1 verifier runtime | ~35s end-to-end (incl. 16s build) |
| Reporter p95 latency | 232.6 ms (well within revised 250 ms budget) |
| hook.log lines at phase close | 114 |
| Real Claude Stop fires captured in checkpoint | 3 (real iTerm2 session UUID `w0t0p1:79C4699F-…`) |
| Plan 02-02 metrics | 30 min duration · 2 tasks · 5 files (2 created, 3 modified) · 4 commits (RED + Rule-1 fix + GREEN + Korean copy) |
| Plan 02-04 metrics | ~8 min duration · 2 TDD tasks · 5 files created · 4 commits (RED + GREEN ×2) · 18/18 unit tests pass · full target 31/31 pass · 0 regressions |

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
| AUD-01 dedupe scope = sound only (completed queue appends unconditionally; only `playSoundOnce` gated by DedupeKey) — Phase 4 may broaden by extending DedupeKey | 02-04 | Plan 02-04 (RESEARCH Pattern 2 lines 408-410) |
| Pitfall #11 anchor: `await SessionRegistry.shared.restore()` MUST run before `await listener.start()` in Wave 6 AppDelegate boot order | 02-04 | Plan 02-04 (api surface frozen; Wave 6 02-11 enforces) |
| NotifierProtocol declared inline in App/SessionRegistry.swift (not in a separate file) — Wave 0's MockNotifier.swift extended via fixture-only file MockNotifier+NotifierProtocol.swift | 02-04 | Plan 02-04 (file-ownership invariant preserved) |

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

- **Last action:** Completed Plan 02-04 (Phase 2 Wave 2 — SessionRegistry actor + SessionStore atomic persistence). 4 commits on master (sequential mode, TDD):
  - `169d5a0` test(02-04): add failing SessionStoreTests (TDD RED)
  - `74c0bf7` feat(02-04): SessionStore actor with atomic save + corrupt-file recovery
  - `efefcf6` test(02-04): add failing SessionRegistryTests + NotifierProtocol extension (TDD RED)
  - `35a2be1` feat(02-04): SessionRegistry actor with ingest/threshold/dedupe/GC/restore/injectTest

  Final verifications: SessionStoreTests 5/5 pass, SessionRegistryTests 13/13 pass, full test target 31/31 pass (no regressions in Phase 1 / 02-00 / 02-02 / 02-03), `xcodebuild build` succeeds. `grep -c 'await persist()' App/SessionRegistry.swift` returns 7 (≥4 required). `git diff` confirms ClaudeAlertBotTests/Fixtures/MockNotifier.swift unchanged byte-for-byte (file-ownership invariant preserved).

  Public API frozen and documented in 02-04-SUMMARY.md for Wave 3+ consumers. AUD-01 dedupe scope narrowed to sound-only (Phase 4 may broaden via DedupeKey extension). Pitfall #11 anchor: SessionRegistry.restore() must precede HookListener.start() in Wave 6 AppDelegate.

  Auto-fixed test bug (Rule 1): Tests C/D used historical 1_700_000_000 epoch which lazy GC at top of ingest() evicted (>6h old vs Date()). Plus ISO8601 default formatter strips fractional seconds → off-by-one duration. Final fix anchors fixtures at `Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))`. Documented in SUMMARY Deviations section.

- **Files written this plan:**
  - `App/SessionRegistry.swift` (created — actor SessionRegistry + NotifierProtocol + Clock)
  - `App/SessionStore.swift` (created — actor SessionStore atomic persistence + corrupt-rename)
  - `ClaudeAlertBotTests/SessionRegistryTests.swift` (created — 13 unit tests A–M)
  - `ClaudeAlertBotTests/SessionStoreTests.swift` (created — 5 unit tests for SESS-03)
  - `ClaudeAlertBotTests/Fixtures/MockNotifier+NotifierProtocol.swift` (created — extension-only conformance)
  - `ClaudeAlertBot.xcodeproj/project.pbxproj` (xcodegen-regenerated for new files)
  - `.planning/phases/02-alert-loop/02-04-SUMMARY.md` (created)
  - `.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md` (updated — plan progress + 6 requirements satisfied + AUD-01 partial)
- **Next action:** Execute Plan 02-05 — AppleScriptHelper actor (compile-once NSAppleScript, 1s hard timeout, error classification, state mirror). Provides the body for the `suppressIfFrontmost: @Sendable (String?) async -> Bool` closure that 02-04's ingest() exposes as a parameter (D2-14 cheap-query). Parallel companion to 02-04 in Wave 2; together they unblock Wave 3 (02-06 NotificationOrchestrator).

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
