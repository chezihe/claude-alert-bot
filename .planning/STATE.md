---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-08T08:00:12.785Z"
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 19
  completed_plans: 14
  percent: 74
---

# State: Claude Alert Bot

**Last updated:** 2026-05-08 (Phase 02 Wave 3 first half — Plan 02-06 complete: NotificationOrchestrator @MainActor + SoundPlayer + WidgetControllerProtocol + SoundPlaying; AUD-01 / AUD-02 / WIDG-05 satisfied; Wave 3 parallel companion 02-07 next)

## Project Reference

- **What this is:** Native macOS app that turns Claude Code's `Stop` hook into a persistent floating widget that lands the user back on the exact iTerm2 tab where the work happened.
- **Core value:** "Claude Code 사용자가 자리를 비웠을 때, 길게 걸린 작업의 완료를 놓치지 않고 정확한 그 iTerm2 세션으로 즉시 복귀할 수 있다." — alert + correct-tab jump are the inseparable core; either failing destroys the value.
- **Current focus:** Phase 2 — alert-loop

## Current Position

Phase: 2 (alert-loop) — EXECUTING
Plan: 7 of 12 complete (Wave 0: 02-00 + 02-01 spike; Wave 1: 02-02 + 02-03; Wave 2: 02-04 + 02-05; Wave 3 first half: 02-06). Next executable: 02-07 (Wave 3 FloatingWidgetWindowController — parallel companion).
Next: Execute 02-07 — FloatingWidgetPanel + WindowController. Implements the `WidgetControllerProtocol` shape that 02-06 just locked. After 02-07 lands, Wave 4 (02-08 SettingsView + popover) unblocks; Wave 6 02-11 performs the AppDelegate boot wiring per the order documented in 02-04 / 02-06.

- **Milestone:** v1
- **Phase:** 02 — Alert Loop, 7/12 plans complete. 5 plans remain.
- **Plan:** 02-06 complete (NotificationOrchestrator @MainActor implementing NotifierProtocol + SoundPlayer wrapping AVAudioPlayer + WidgetControllerProtocol + SoundPlaying protocols). 4/4 SoundPlayerTests + 6/6 NotificationOrchestratorTests pass; full target 50/50 pass (was 40/40); production build SUCCEEDED. AUD-01 (sound playback path) + AUD-02 (sound toggle gating) + WIDG-05 (count==0 → hideWidget) all satisfied; orchestrator forwards AUD-01 dedupe verbatim from registry actor (single enforcement site).
- **Status:** Executing Phase 2
- **Progress:** [███████░░░] 74%

## Performance Metrics

| Metric | Value |
|--------|-------|
| Phases complete | 1 / 6 |
| Plans complete | 7 / 7 in Phase 01 + 7 / 12 in Phase 02 |
| Requirements covered | 19 / 53 (Phase 1: HOOK-01, HOOK-03, HOOK-04, HOOK-05, HOOK-06, IPC-01, IPC-02, IPC-03, DIST-01, DIST-05 + Phase 2: SESS-01..04, THR-01..02, AUD-01, AUD-02, WIDG-05) |
| Phase branch | master (no branching strategy per config.json) |
| Last plan duration | ~25 min (01-06, verifier sign-off — incl. inherited Task 1 from previous executor) |
| Phase 1 verifier runtime | ~35s end-to-end (incl. 16s build) |
| Reporter p95 latency | 232.6 ms (well within revised 250 ms budget) |
| hook.log lines at phase close | 114 |
| Real Claude Stop fires captured in checkpoint | 3 (real iTerm2 session UUID `w0t0p1:79C4699F-…`) |
| Plan 02-02 metrics | 30 min duration · 2 tasks · 5 files (2 created, 3 modified) · 4 commits (RED + Rule-1 fix + GREEN + Korean copy) |
| Plan 02-04 metrics | ~8 min duration · 2 TDD tasks · 5 files created · 4 commits (RED + GREEN ×2) · 18/18 unit tests pass · full target 31/31 pass · 0 regressions |
| Plan 02-05 metrics | ~7 min duration · 1 TDD task · 2 files created (App/AppleScriptHelper.swift, ClaudeAlertBotTests/AppleScriptHelperTests.swift) · 2 commits (RED + GREEN) · 9/9 unit tests pass · full target 40/40 pass · 0 regressions |
| Plan 02-06 metrics | ~12 min duration · 2 TDD tasks · 4 files created (App/SoundPlayer.swift, App/NotificationOrchestrator.swift, ClaudeAlertBotTests/SoundPlayerTests.swift, ClaudeAlertBotTests/NotificationOrchestratorTests.swift) · 4 commits (RED + GREEN ×2) · 4/4 SoundPlayerTests + 6/6 NotificationOrchestratorTests · full target 50/50 pass · 0 regressions |

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
| WidgetControllerProtocol shape locked: showWidget(pendingCount:latest:) / hideWidget() / updatePendingCount(_:latest:) / setQueue(_:) — consumed by 02-07 (concrete controller), 02-08 (popover), 02-11 (AppDelegate wiring) | 02-06 | Plan 02-06 |
| AUD-01 dedupe enforcement = SessionRegistry actor only. NotificationOrchestrator forwards playSoundOnce verbatim and AND-gates with SettingsStore.soundEnabled (AUD-02). No double-gating | 02-06 | Plan 02-06 |
| NotificationOrchestrator constructor uses non-defaulted `sound: any SoundPlaying` + `convenience init(widget:)` — strict-concurrency-safe pattern (default `SoundPlayer()` expression cannot be evaluated in nonisolated default-expression context) | 02-06 | Plan 02-06 (Rule 1 fix during Task 2 GREEN) |
| SoundPlaying protocol exists solely as @MainActor test seam; production path uses `SoundPlayer` directly via `convenience init(widget:)` — Settings "Test notification" walks the standard alert path via `SessionRegistry.injectTest()` per 02-04 contract | 02-06 | Plan 02-06 |

### Open Questions (carried into planning)

- **Phase 3:** `ITERM_SESSION_ID` behavior under tmux/nix-shell/containers — to be characterized using Phase 1's `hook.log` data once real usage accrues. Phase 3 research-phase will run a tmux/venv/nested-shell test matrix.
- **Phase 3:** AppleScript `unique ID` lookup latency under typical pane counts — needs a 5-line probe script during Phase 3 planning.
- **Phase 6:** Exact macOS 14/15/26 Gatekeeper dialog wording for ad-hoc-signed-but-quarantined app. README must reflect what users actually see.
- **Pre-Phase 2 decision RESOLVED (D2-18 RETRACTED, D2-19 LOCKED):** `NSWorkspace.shared.focusStatus` is not in public macOS SDK; Focus/DnD auto-mute is impossible without private API. SettingsStore.soundEnabled toggle is the single source of truth — verified live in 02-06 NotificationOrchestratorTests `test_present_skipsSound_whenSoundDisabled_AUD_02`. UNNotificationSound channel rejected (banner auto-dismiss risk per UI-SPEC). AVAudioPlayer direct.

### Todos / Follow-ups

- [ ] Update PROJECT.md "Constraints" section: replace "우클릭 → 열기" with macOS 14/15+ split (System Settings → Privacy & Security → Open Anyway) — done at Phase 6, but PROJECT.md text should be touched up at Phase 5/6 boundary.

### Blockers

None.

## Session Continuity

- **Last action:** Completed Plan 02-06 (Phase 2 Wave 3 first half — NotificationOrchestrator + SoundPlayer). 4 commits on master (sequential mode, TDD ×2):
  - `aa45848` test(02-06): add failing SoundPlayerTests (TDD RED)
  - `154b46e` feat(02-06): SoundPlayer wrapping AVAudioPlayer (AUD-01)
  - `af40594` test(02-06): add failing NotificationOrchestratorTests (TDD RED)
  - `4bf184d` feat(02-06): NotificationOrchestrator @MainActor — NotifierProtocol impl

  Final verifications: SoundPlayerTests 4/4 pass (0.54s), NotificationOrchestratorTests 6/6 pass (0.85s), full test target 50/50 pass (no regressions across Phase 1 / 02-00 / 02-02..06), `xcodebuild build` succeeds (no new warnings). Source-string anchors verified: `grep -c 'final class NotificationOrchestrator: NotifierProtocol' = 1`, `grep -c 'WidgetControllerProtocol' = 6`, `grep -c 'soundEnabled' = 4`, `grep -c 'protocol SoundPlaying' = 1`, `grep -c 'extension SoundPlayer: SoundPlaying' = 1`.

  Public API frozen for Wave 3+ wiring: **WidgetControllerProtocol** (showWidget / hideWidget / updatePendingCount / setQueue) — implemented by 02-07 concretely; consumed by 02-08 popover and 02-11 AppDelegate. **SoundPlaying** is internal test seam only — production callers use `NotificationOrchestrator.init(widget:)` convenience init that allocates `SoundPlayer()` automatically. **AUD-01 dedupe is enforced solely by SessionRegistry actor** (Wave 2); orchestrator forwards `playSoundOnce` and AND-gates with `SettingsStore.soundEnabled` only.

  Auto-fixed (Rule 1): Strict-concurrency rejected `sound: any SoundPlaying = SoundPlayer()` default expression ("main actor-isolated initializer in synchronous nonisolated context"). Resolved by removing default and adding `convenience init(widget:)` that constructs `SoundPlayer()` from inside @MainActor body. Public surface preserved for AppDelegate. Documented in SUMMARY Deviations section.

- **Files written this plan:**
  - `App/SoundPlayer.swift` (created — @MainActor final class wrapping AVAudioPlayer)
  - `App/NotificationOrchestrator.swift` (created — @MainActor final class implementing NotifierProtocol + WidgetControllerProtocol declaration + SoundPlaying protocol + extension SoundPlayer)
  - `ClaudeAlertBotTests/SoundPlayerTests.swift` (created — 4 unit tests)
  - `ClaudeAlertBotTests/NotificationOrchestratorTests.swift` (created — 6 unit tests + SpyWidget + SpySoundPlayer fixtures)
  - `ClaudeAlertBot.xcodeproj/project.pbxproj` (xcodegen-regenerated)
  - `.planning/phases/02-alert-loop/02-06-SUMMARY.md` (created — public API + WidgetControllerProtocol contract for 02-07/02-08/02-11 + verifier row bodies)
  - `.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md` (updated — plan progress + 3 new requirements complete: AUD-01, AUD-02, WIDG-05)
- **Next action:** Execute Plan 02-07 — FloatingWidgetPanel + WindowController (Wave 3 parallel companion). Implements concrete `WidgetControllerProtocol` against the shape 02-06 just locked. Pattern: `NSPanel` subclass with `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded` + `level=.floating` + `collectionBehavior=[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` per RESEARCH Pitfall #1 / WIDG-02. After 02-07 lands, Wave 4 unblocks (02-08 SettingsView + popover).

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
