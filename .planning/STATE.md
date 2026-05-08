---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-08T09:30:00.000Z"
progress:
  total_phases: 6
  completed_phases: 2
  total_plans: 19
  completed_plans: 19
  percent: 100
---

# State: Claude Alert Bot

**Last updated:** 2026-05-08 (Phase 02 Wave 6 complete — Plan 02-11 complete: AppDelegate Pitfall #11 boot wiring + HookListener.ingest dispatch + @main SwiftUI App per D2-29 + scripts/verify-phase-2.sh fully populated. SC#3 manual checkpoint APPROVED with all 11 sub-checks. Verifier from clean state: 23 PASS / 1 FAIL\* / 2 SKIP (\*2-11-02 cab-test UUID-per-invocation tooling artifact, not regression — V-7 logged). Phase 1 regression PASS. **Phase 2 closed: phase_gate: green** — see `.planning/phases/02-alert-loop/02-VERIFICATION.md`. Phase 3 unblocked.)

## Project Reference

- **What this is:** Native macOS app that turns Claude Code's `Stop` hook into a persistent floating widget that lands the user back on the exact iTerm2 tab where the work happened.
- **Core value:** "Claude Code 사용자가 자리를 비웠을 때, 길게 걸린 작업의 완료를 놓치지 않고 정확한 그 iTerm2 세션으로 즉시 복귀할 수 있다." — alert + correct-tab jump are the inseparable core; either failing destroys the value.
- **Current focus:** Phase 2 — alert-loop

## Current Position

Phase: 2 (alert-loop) — **COMPLETE (phase_gate: green)**
Plan: 12 of 12 complete (Wave 0: 02-00 + 02-01 spike; Wave 1: 02-02 + 02-03; Wave 2: 02-04 + 02-05; Wave 3: 02-06 + 02-07; Wave 4: 02-08 + 02-09; Wave 5: 02-10; Wave 6: 02-11). Phase 2 closed by 02-11 sign-off — see `.planning/phases/02-alert-loop/02-VERIFICATION.md`.
Next: `/gsd-progress` to report, or `/gsd-context-phase 3` to begin Phase 3 (Click-to-iTerm2). Phase 3 prerequisites in ROADMAP §"Research Flags": (a) `ITERM_SESSION_ID` reliability under tmux/screen/nix-shell/zellij/containerized shells; (b) AppleScript `unique ID` lookup latency probe under typical pane counts; (c) `errAEEventNotPermitted (-1743)` deep-link reliability across macOS 14/15/26.

- **Milestone:** v1
- **Phase:** 02 — Alert Loop, **12/12 plans complete; phase_gate: green** (verified 2026-05-08).
- **Plan:** 02-11 complete (AppDelegate boot wiring per Pitfall #11 + HookListener.ingest dispatch + @main SwiftUI App per D2-29 + verify-phase-2.sh fully populated + 02-VERIFICATION.md sign-off). SC#3 manual checkpoint APPROVED (11/11 sub-checks); verifier 23 PASS / 1 FAIL (verifier-tooling artifact V-7) / 2 SKIP from clean state; Phase 1 regression PASS. Pitfall #11 boot order locked: `await SessionRegistry.shared.restore()` precedes `listener.start()`; closes Phase 1 V-2 race in steady state.
- **Status:** Phase 2 complete; Phase 3 unblocked.
- **Progress:** [██████████] 100%

## Performance Metrics

| Metric | Value |
|--------|-------|
| Phases complete | 2 / 6 |
| Plans complete | 7 / 7 in Phase 01 + 12 / 12 in Phase 02 |
| Requirements covered | 30 / 53 (Phase 1: HOOK-01, HOOK-03, HOOK-04, HOOK-05, HOOK-06, IPC-01, IPC-02, IPC-03, DIST-01, DIST-05 + Phase 2: HOOK-02, SESS-01..04, THR-01..02, AUD-01, AUD-02, WIDG-01..07, SET-01..04) |
| Plan 02-11 metrics | ~45 min duration (across 2 executor sessions) · 4 tasks (Tasks 1+2 auto, Task 3 human-verify, Task 4 auto) · 4 files modified (AppDelegate.swift, HookListener.swift, ClaudeAlertBotApp.swift renamed, verify-phase-2.sh) + 1 file created (02-VERIFICATION.md) · 3 commits (Tasks 1+2+4) · verifier 23 PASS/1 FAIL/2 SKIP from clean state · Phase 1 regression PASS · phase_gate: green |
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
| Plan 02-07 metrics | ~8 min duration · 2 tasks (Task 1 TDD, Task 2 build-only per plan carve-out) · 5 files created (App/FloatingWidgetPanel.swift, App/FloatingWidgetWindowController.swift, App/WidgetIconView.swift, ClaudeAlertBotTests/FloatingWidgetPanelTests.swift, ClaudeAlertBotTests/PositioningTests.swift) · 3 commits (RED Task1 + GREEN Task1 + GREEN Task2) · 7/7 FloatingWidgetPanelTests + 5/5 PositioningTests · full target 62/62 pass · 0 regressions |
| Plan 02-08 metrics | ~6 min duration · 2 tasks (Task 1 TDD, Task 2 build-only per plan carve-out) · 4 files created (App/PopoverContentView.swift, App/PopoverRowView.swift, App/WidgetPopoverController.swift, ClaudeAlertBotTests/PopoverContentTests.swift) · 3 commits (RED Task1 + GREEN Task1 + GREEN Task2) · 5/5 PopoverContentTests · full target 67/67 pass · 0 regressions |
| Plan 02-09 metrics | ~6 min duration · 2 tasks (Task 1 build-only per plan carve-out, Task 2 TDD) · 4 files created (App/WakeObserver.swift, App/WorkspaceFrontmostObserver.swift, App/SessionGCTimer.swift, ClaudeAlertBotTests/SessionGCTimerTests.swift) · 3 commits (Task 1 + RED Task 2 + GREEN Task 2) · 4/4 SessionGCTimerTests · full target 71/71 pass · 0 regressions |
| Plan 02-10 metrics | ~3 min duration · 2 TDD tasks · 3 files created (App/PermissionBannerView.swift, App/SettingsView.swift, ClaudeAlertBotTests/SettingsViewTests.swift) · 4 commits (RED + GREEN ×2) · 8/8 SettingsViewTests pass (3 banner-copy + 5 settings-copy/corner) · full target 79/79 pass (was 71 + 8 new) · 0 regressions · zero new external dependencies (D2-29 preserved) |

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
| FloatingWidgetPanel locked: `.borderless | .nonactivatingPanel` styleMask + `level=.floating` + `collectionBehavior=[canJoinAllSpaces, fullScreenAuxiliary, stationary]` + canBecomeKey/Main false — 7 panel tests prevent regression | 02-07 | Plan 02-07 |
| WidgetPositioning.origin pure free function in App/FloatingWidgetPanel.swift owns WIDG-06/07 contract — controller's reposition() is a thin caller passing NSScreen.main.visibleFrame + safeAreaInsets; SettingsStore read at call time (SET-03) | 02-07 | Plan 02-07 |
| Pattern 8 verdict from 02-01-SPIKE-RESULT honored: 02-07 ships panel + icon view + WidgetHoverDelegate stub only; NSPopover lives with controller in 02-08. No second sibling NSPanel | 02-07 | Plan 02-07 |
| WidgetHoverDelegate protocol shape locked: `widgetMouseEntered()` / `widgetMouseExited()` (both @MainActor); 02-08 owns hover-intent timing (150ms open / 250ms close grace) | 02-07 | Plan 02-07 |
| LSUIElement regression guard: `grep -c 'NSApp.activate' App/FloatingWidget*.swift App/WidgetIconView.swift` MUST be 0 at all times — comment text intentionally avoids the literal symbol so the guard stays clean | 02-07 | Plan 02-07 |
| Pattern 8 NSPopover ratified by spike + shipped in 02-08: WidgetPopoverController hosts NSPopover with `.transient` behavior, contentViewController = NSHostingController(rootView: PopoverContentView). Pattern 8a sibling-NSPanel branch retired (popoverPanel literal MUST stay 0 in App/WidgetPopoverController.swift) | 02-08 | Plan 02-08 |
| D2-08 OSLog format LOCKED: `[would-jump session=<uuid>]` (square brackets, single space, `session=` literal, `privacy: .public` UUID) emitted in App/WidgetPopoverController.swift onRowClick(sessionID:). Phase 3 ITermBridge inherits the call site verbatim — replaces `Task { await SessionRegistry.shared.clearOne(...) }` with the jump call but preserves the OSLog format so existing log-show predicates keep matching across the Phase 2→3 transition | 02-08 | Plan 02-08 |
| Hover-intent timing LOCKED for popover: 150ms entry delay before show, 250ms exit grace before dismiss; both DispatchWorkItems are cancellable — re-entering during exit grace cancels pending dismiss, leaving before entry intent cancels pending show | 02-08 | Plan 02-08 |
| PopoverContentRules pure namespace owns the 4 popover display rules (shouldShowClearAll, projectsWithDuplicates, timeSuffix, showsOrphanIndicator) — Phase 4 multi-session UX plan reuses these helpers rather than re-deriving | 02-08 | Plan 02-08 |
| 02-11 AppDelegate boot order extended: instantiate `WidgetPopoverController(widgetController: widget)` immediately after FloatingWidgetWindowController, retain as a stored property (hoverDelegate is `weak`), and assign `widget.hoverDelegate = popoverController` BEFORE `await SessionRegistry.shared.restore()` and `await listener.start()` | 02-08 | Plan 02-08 |
| SESS-04 Pattern 6 triple-trigger LOCKED: lazy ingest GC at top of SessionRegistry.ingest() (Wave 2) + WakeObserver.didWakeNotification firing onWake() (02-09) + SessionGCTimer DispatchSourceTimer 30-min repeating (02-09). All three call SessionRegistry.shared.runGC() — wake observer + timer via injected closure wired by 02-11 AppDelegate | 02-09 | Plan 02-09 |
| 02-09 retention contract LOCKED for all observers/timers: `[weak self]` capture in handlers + retained `private var token`/`private var source` on the class instance + verbatim `// CRITICAL: retain` comment per file (PATTERNS.md institutional anchor inherited from Phase 1 AppDelegate.signalSources). Wave 6 02-11 mirrors this by retaining WakeObserver / WorkspaceFrontmostObserver / SessionGCTimer as stored properties on AppDelegate | 02-09 | Plan 02-09 |
| WorkspaceFrontmostObserver gates on `app?.bundleIdentifier == "com.googlecode.iterm2"` BEFORE invoking AppleScriptHelper (T-FRONTMOST-SPAM-01) — prevents AppleScript spam on every Cmd-Tab. `grep -c 'com.googlecode.iterm2' App/WorkspaceFrontmostObserver.swift` MUST stay ≥1 | 02-09 | Plan 02-09 |
| 02-11 AppDelegate boot order extended (Wave 4 lifecycle additions): retain `WakeObserver`, `WorkspaceFrontmostObserver`, `SessionGCTimer` as stored properties on AppDelegate. WakeObserver and SessionGCTimer take `{ Task { await SessionRegistry.shared.runGC() } }` as their callback. WorkspaceFrontmostObserver is self-contained (no callback). All three may be created before or after `restore()` — they only fire on async events | 02-09 | Plan 02-09 |
| Settings UI copy lockdown contract: 13 static-let Korean copy constants (3 on PermissionBannerView + 10 on SettingsView) + WidgetCorner.localizedLabel order are asserted verbatim by 8 SettingsViewTests. Future translation pass MUST update both the constant and the matching test assertion in lockstep — drift = test fails on next CI run (T-COPY-DRIFT-01 mitigation) | 02-10 | Plan 02-10 |
| D2-35 Path A trigger anchor LOCKED in `App/SettingsView.swift` `.onAppear`: `if store.applescriptPermission == .unknown { Task { await AppleScriptHelper.shared.triggerPermissionPrompt() } }`. `grep -c 'triggerPermissionPrompt' App/SettingsView.swift` MUST stay = 1. Path B (first Stop) lives in SessionRegistry — both paths converge on the same dialog (macOS shows once per (app, target) pair) | 02-10 | Plan 02-10 |
| Settings { SettingsView() } scene mounting is owned by 02-11 (Wave 6) — 02-10 ships only the view itself. The view wires its own dependencies via singletons (SettingsStore.shared, SessionRegistry.shared, AppleScriptHelper.shared, PermissionDeepLink). The standard ⌘, shortcut is automatic via SwiftUI's Settings scene; zero `KeyboardShortcuts` dep (D2-29 invariant preserved) | 02-10 | Plan 02-10 |

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

- **Last action:** Completed Plan 02-11 (Phase 2 Wave 6 — AppDelegate boot wiring + HookListener dispatch + @main SwiftUI App + Phase 2 sign-off). 2 commits on master from previous executor session + 1 docs commit this session:
  - `46ed6c9` feat(02-11): wire Phase 2 boot order + HookListener dispatch + @main SwiftUI App
  - `02fb8ed` feat(02-11): populate verify-phase-2.sh with all Wave 0-6 rows
  - (this session) docs(02-11): close Phase 2 — phase_gate green (SC#3 approved)

  Final verifications (clean state, no live ClaudeAlertBot, fresh socket + sessions.json):
  - `VERIFY_NONINTERACTIVE=1 bash scripts/verify-phase-2.sh` → 23 PASS / 1 FAIL\* / 2 SKIP. \*Single FAIL is `2-11-02` (cab-test UUID-per-invocation tooling artifact — V-7 follow-up logged). Underlying THR-01 logic locked by `SessionRegistryTests` (row 2-04-01 PASS).
  - Phase 1 regression `2-11-99` PASS (`VERIFY_NONINTERACTIVE=1 bash scripts/verify-phase-1.sh` exits 0).
  - SC#3 manual checkpoint Task 3 APPROVED with all 11 sub-checks observed (multi-Space, full-screen, Stage Manager, sleep/wake, lid, no focus steal, click-dismiss, hover popover, ⌘, Settings, idle invisibility).
  - OSLog confirmed Pitfall #11 boot ordering live: `Phase 2 components wired (orchestrator, widget, popover, observers, GC timer)` precedes `listener bound (Phase 2 wiring complete)` in every boot.
  - D2-29 compliance: `@main` + `Settings { SettingsView() }` + `@NSApplicationDelegateAdaptor` + zero external deps + zero `NSApp.activate(...)` in UI/lifecycle code, all confirmed.

  **phase_gate: green** — recorded in `.planning/phases/02-alert-loop/02-VERIFICATION.md`. Phase 3 unblocked.

  Deviations: None — Tasks 1, 2, 4 executed verbatim per plan; Task 3 returned a clean `approved` signal with no observations beyond the carry-overs already captured (V-2, V-7, V-8).

- **Files written this plan (02-11):**
  - `App/AppDelegate.swift` (modified — Pitfall #11 boot steps 6-12 wiring + applicationWillFinishLaunching `.accessory` policy)
  - `App/HookListener.swift` (modified — `handle(buffer:)` dispatches to SessionRegistry.ingest with MainActor wrapper)
  - `App/ClaudeAlertBotApp.swift` (renamed from `App/main.swift` — `@main struct ClaudeAlertBotApp: App` per D2-29)
  - `scripts/verify-phase-2.sh` (modified — all upstream verifier rows + SC#1..6 + Phase 1 regression with `VERIFY_NONINTERACTIVE=1`)
  - `.planning/phases/02-alert-loop/02-VERIFICATION.md` (created — phase_gate: green sign-off + all 6 SC verdicts + manual checkpoint record + D2-29 compliance trace + V-7/V-8 follow-ups)
  - `.planning/phases/02-alert-loop/02-11-SUMMARY.md` (created — full plan summary with Pitfall #11 boot order documented for Phase 3 inheritance)
  - `.planning/STATE.md`, `.planning/ROADMAP.md` (updated — Phase 2 closure)

- **Next action:** `/gsd-progress` to report Phase 2 closure, or `/gsd-context-phase 3` to begin Phase 3 (Click-to-iTerm2). Phase 3 prerequisites in ROADMAP §"Research Flags".

### Previous action (02-10 — superseded above):

- Completed Plan 02-10 (Phase 2 Wave 5 — Settings UI + Permission Banner). 4 commits on master (sequential mode):
  - `6b7a716` test(02-10): add failing PermissionBannerView copy tests (TDD RED)
  - `99b64e7` feat(02-10): PermissionBannerView SwiftUI denied-state banner (D2-36)
  - `40aa803` test(02-10): add failing SettingsView copy + corner-label tests (TDD RED)
  - `f44a27b` feat(02-10): SettingsView Form + D2-35 Path A trigger + Test button (SET-01..04)

  Final verifications: SettingsViewTests 8/8 pass (3 banner-copy + 5 settings-copy/corner; ~0.004s), full test target 79/79 pass (was 71 + 8 new = 79; zero regressions across Phase 1 / 02-00 / 02-02..09), `xcodebuild build -scheme ClaudeAlertBot` SUCCEEDED. Verification grep guards: `grep -c '자동화 권한이 꺼져 있어요' App/PermissionBannerView.swift` → 1, `grep -c '테스트 알림 보내기' App/SettingsView.swift` → 1, `grep -c 'triggerPermissionPrompt' App/SettingsView.swift` → 1 (D2-35 Path A anchor), `grep -c 'SessionRegistry.shared.injectTest' App/SettingsView.swift` → 2 (doc comment + call site). All ≥ 1 per plan §verification.

  Public surface frozen for Wave 6 wiring: **SettingsView** is a parameterless SwiftUI View; reads `SettingsStore.shared` via `@StateObject`, calls `SessionRegistry.shared.injectTest`, `AppleScriptHelper.shared.triggerPermissionPrompt`, `PermissionDeepLink.openAutomationPreferences` directly via singletons. 02-11 mounts it via `Settings { SettingsView() }` (zero arguments needed). **PermissionBannerView** is also parameterless — composes inside `SettingsView` only when `store.applescriptPermission == .denied`. The `⌘,` keyboard shortcut is automatic via SwiftUI's `Settings` scene — no `KeyboardShortcuts` import needed (D2-29 zero-deps invariant preserved).

  Locked-copy contract: 13 static-let Korean strings (3 on PermissionBannerView + 10 on SettingsView) + WidgetCorner.localizedLabel order are asserted verbatim by 8 SettingsViewTests (T-COPY-DRIFT-01 mitigation). Future translation passes MUST update constant + test in lockstep.

  Deviations: None. Plan executed verbatim across both tasks. Action templates copy-pasted into the corresponding files with zero structural edits.

- **Files written this plan:**
  - `App/PermissionBannerView.swift` (created — SwiftUI yellow-tint banner; 3 static-let copy strings; CTA → PermissionDeepLink.openAutomationPreferences)
  - `App/SettingsView.swift` (created — SwiftUI Form { Section ×4 + conditional Permission Section }; @StateObject SettingsStore.shared; D2-35 Path A `.onAppear` trigger; D2-21 Test button → SessionRegistry.injectTest; 10 static-let copy strings)
  - `ClaudeAlertBotTests/SettingsViewTests.swift` (created — 8 unit tests: 3 banner-copy + 4 settings-copy + 1 corner-label-Korean-order)
  - `ClaudeAlertBot.xcodeproj/project.pbxproj` (xcodegen-regenerated)
  - `.planning/phases/02-alert-loop/02-10-SUMMARY.md` (created — locked-copy contract + Wave 6 wiring requirement + verifier row body + threat mitigations)
  - `.planning/STATE.md`, `.planning/ROADMAP.md`, `.planning/REQUIREMENTS.md` (updated — plan progress 10→11 of 12 in Phase 2; 89% → 95%; SET-01..04 marked complete)
- **Next action:** Execute Plan 02-11 — Wave 6 AppDelegate boot wiring. Mount `Settings { SettingsView() }` scene in main.swift (or App body); retain WidgetPopoverController + WakeObserver + WorkspaceFrontmostObserver + SessionGCTimer as stored properties on AppDelegate; HookListener.ingest dispatch into SessionRegistry.shared.ingest; Pitfall #11 boot order — `await SessionRegistry.shared.restore()` MUST run before `await listener.start()`; assign WidgetPopoverController as widget.hoverDelegate before listener.start; ship `scripts/verify-phase-2.sh` with all per-plan verifier rows grafted (incl. `verify_2_10_01` covering all SettingsViewTests). After 02-11, Phase 2 closes.

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
*Phase 02 closed: 2026-05-08 (phase_gate: green) — see `.planning/phases/02-alert-loop/02-VERIFICATION.md`*
