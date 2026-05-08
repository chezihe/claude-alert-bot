---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-08T07:50:12.973Z"
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 19
  completed_plans: 13
  percent: 68
---

# State: Claude Alert Bot

**Last updated:** 2026-05-08 (Phase 02 Wave 2 closes — Plan 02-05 complete: AppleScriptHelper actor with compile-once NSAppleScript + 1s timeout + error classification + state mirror; provides production body for the `suppressIfFrontmost` closure on SessionRegistry.ingest())

## Project Reference

- **What this is:** Native macOS app that turns Claude Code's `Stop` hook into a persistent floating widget that lands the user back on the exact iTerm2 tab where the work happened.
- **Core value:** "Claude Code 사용자가 자리를 비웠을 때, 길게 걸린 작업의 완료를 놓치지 않고 정확한 그 iTerm2 세션으로 즉시 복귀할 수 있다." — alert + correct-tab jump are the inseparable core; either failing destroys the value.
- **Current focus:** Phase 2 — alert-loop

## Current Position

Phase: 2 (alert-loop) — EXECUTING
Plan: 6 of 12 complete (Wave 0: 02-00 + 02-01 spike; Wave 1: 02-02 + 02-03; Wave 2: 02-04 + 02-05). Next executable: 02-06 (Wave 3 NotificationOrchestrator).
Next: Execute 02-06 — NotificationOrchestrator (concrete `NotifierProtocol` impl). Both Wave 2 plans now landed: SessionRegistry actor (frozen API) + AppleScriptHelper actor (suppress closure body) → Wave 3 has both seams it needs.

- **Milestone:** v1
- **Phase:** 02 — Alert Loop, 6/12 plans complete. 6 plans remain.
- **Plan:** 02-05 complete (AppleScriptHelper actor: compile-once + 1s timeout + error classification + MainActor state mirror). 9/9 unit tests pass; full target 40/40; production build SUCCEEDED. AppleScriptHelper is leaf-level — no further consumers in Wave 3; Wave 6 02-11 wires it into HookListener dispatch.
- **Status:** Executing Phase 2
- **Progress:** [██████░░░░] 68%

## Performance Metrics

| Metric | Value |
|--------|-------|
| Phases complete | 1 / 6 |
| Plans complete | 7 / 7 in Phase 01 + 6 / 12 in Phase 02 |
| Requirements covered | 16 / 53 (Phase 1: HOOK-01, HOOK-03, HOOK-04, HOOK-05, HOOK-06, IPC-01, IPC-02, IPC-03, DIST-01, DIST-05 + Phase 2: SESS-01..04, THR-01..02; AUD-01 partial — actual sound playback in 02-06) |
| Phase branch | master (no branching strategy per config.json) |
| Last plan duration | ~25 min (01-06, verifier sign-off — incl. inherited Task 1 from previous executor) |
| Phase 1 verifier runtime | ~35s end-to-end (incl. 16s build) |
| Reporter p95 latency | 232.6 ms (well within revised 250 ms budget) |
| hook.log lines at phase close | 114 |
| Real Claude Stop fires captured in checkpoint | 3 (real iTerm2 session UUID `w0t0p1:79C4699F-…`) |
| Plan 02-02 metrics | 30 min duration · 2 tasks · 5 files (2 created, 3 modified) · 4 commits (RED + Rule-1 fix + GREEN + Korean copy) |
| Plan 02-04 metrics | ~8 min duration · 2 TDD tasks · 5 files created · 4 commits (RED + GREEN ×2) · 18/18 unit tests pass · full target 31/31 pass · 0 regressions |
| Plan 02-05 metrics | ~7 min duration · 1 TDD task · 2 files created (App/AppleScriptHelper.swift, ClaudeAlertBotTests/AppleScriptHelperTests.swift) · 2 commits (RED + GREEN) · 9/9 unit tests pass · full target 40/40 pass · 0 regressions |

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
| AppleScriptHelper.scriptSource is a static String constant — target match performed in Swift after the script returns (T-INJECTION-01 mitigation; never interpolate target into AppleScript source) | 02-05 | Plan 02-05 |
| AppleScript-side `with timeout of 1 second` block + Swift `withCheckedContinuation` on dedicated serial queue → main thread never blocked even on hung iTerm2 (Pitfall 3 closure) | 02-05 | Plan 02-05 |
| AppleScriptHelper writes SettingsStore.applescriptPermission via `await MainActor.run { ... }` — actor-isolated helper never touches @Published from background (Pitfall 9 closure) | 02-05 | Plan 02-05 |
| ScriptResult mapping LOCKED: -1743 → .denied, -1712 → .timeout, other non-nil → .otherError(code), nil → .success(value). Wave 5 banner triggers on .denied only — single contract for downstream consumers | 02-05 | Plan 02-05 |

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

- **Last action:** Completed Plan 02-05 (Phase 2 Wave 2 — AppleScriptHelper actor). 2 commits on master (sequential mode, TDD):
  - `26c735f` test(02-05): add failing AppleScriptHelperTests (TDD RED)
  - `09863e0` feat(02-05): AppleScriptHelper actor — compile-once, 1s timeout, error classification, state mirror

  Final verifications: AppleScriptHelperTests 9/9 pass (0.57s), full test target 40/40 pass (no regressions across Phase 1 / 02-00 / 02-02 / 02-03 / 02-04 / 02-05), `xcodebuild build` succeeds (no new warnings). Source-string anchors verified: `grep -c 'with timeout of 1 second' = 3`, `grep -c 'com\.claudealert\.bot\.applescript' = 1`, `grep -c 'subsystem: "com.claudealert.bot.hook"' = 1` (Phase 1 OSLog invariant preserved).

  Public API frozen for Wave 6 wiring: `frontmostMatches(itermSessionID:) -> Bool`, `triggerPermissionPrompt()`, static `classify(error:result:) -> ScriptResult`. Wave 5 SettingsView uses `triggerPermissionPrompt()` (D2-35 Path A); Wave 6 02-11 HookListener dispatch passes a closure that calls `frontmostMatches` (D2-35 Path B + D2-14 suppress).

  Auto-fixed test bug (Rule 1): `test_queueLabel_isSerial_byConvention` initially used a CWD-relative path (`String(contentsOfFile: "App/AppleScriptHelper.swift")`); xcodebuild test runner CWD is the DerivedData bundle path, not the project root. Resolved with `URL(fileURLWithPath: #filePath)` walked up two dirs. Production code unchanged. Documented in SUMMARY Deviations section.

  Auto-flagged planning bug (Rule 1, deferred): The plan's frontmatter listed `requirements: [WIDG-02]`, but WIDG-02 (NSPanel `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded`) has zero overlap with this plan's AppleScriptHelper actor. Investigation showed REQUIREMENTS.md already had `[x] WIDG-02 Complete` as a false-complete from commit `666c3e2` (02-04's metadata commit), even though 02-04's frontmatter did NOT list WIDG-02 either. SUMMARY frontmatter corrected to `requirements: []`; pre-existing false `[x] WIDG-02` in REQUIREMENTS.md NOT reverted by 02-05 (out of scope per CLAUDE.md "No Over-Editing"). Logged to `.planning/phases/02-alert-loop/deferred-items.md` as `REQ-WIDG-02-FALSE-COMPLETE` for the future widget plan / Phase 2 verifier to close.

- **Files written this plan:**
  - `App/AppleScriptHelper.swift` (created — actor AppleScriptHelper + ScriptResult enum)
  - `ClaudeAlertBotTests/AppleScriptHelperTests.swift` (created — 9 unit tests)
  - `ClaudeAlertBot.xcodeproj/project.pbxproj` (xcodegen-regenerated)
  - `.planning/phases/02-alert-loop/02-05-SUMMARY.md` (created — public API + script source verbatim + error mapping table + trigger path reservations)
  - `.planning/phases/02-alert-loop/deferred-items.md` (created — REQ-WIDG-02-FALSE-COMPLETE finding)
  - `.planning/STATE.md`, `.planning/ROADMAP.md` (updated — plan progress + 4 new locked decisions)
- **Next action:** Execute Plan 02-06 — NotificationOrchestrator (Wave 3). Implements `NotifierProtocol` concretely (@MainActor final class) against the API surface 02-04 froze. Wave 2 fully landed (both plans complete + their public APIs locked). 02-06 unblocks 02-07 (FloatingWidgetWindowController) and 02-08 (SettingsView).

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
