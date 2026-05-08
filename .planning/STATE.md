---
gsd_state_version: 1.0
milestone: v1.0
milestone_name: milestone
status: executing
last_updated: "2026-05-08T08:22:08.641Z"
progress:
  total_phases: 6
  completed_phases: 1
  total_plans: 19
  completed_plans: 17
  percent: 89
---

# State: Claude Alert Bot

**Last updated:** 2026-05-08 (Phase 02 Wave 4 second half complete — Plan 02-09 complete: WakeObserver + WorkspaceFrontmostObserver + SessionGCTimer (Pattern 6 SESS-04 triple-trigger). All three carry verbatim "CRITICAL: retain" comment + [weak self] capture + retained-token/source per PATTERNS.md. WorkspaceFrontmostObserver bundle-ID-filters to `com.googlecode.iterm2` (T-FRONTMOST-SPAM-01). 4/4 SessionGCTimerTests pass; full target 71/71 pass; Wave 5/6 plans 02-10 / 02-11 next)

## Project Reference

- **What this is:** Native macOS app that turns Claude Code's `Stop` hook into a persistent floating widget that lands the user back on the exact iTerm2 tab where the work happened.
- **Core value:** "Claude Code 사용자가 자리를 비웠을 때, 길게 걸린 작업의 완료를 놓치지 않고 정확한 그 iTerm2 세션으로 즉시 복귀할 수 있다." — alert + correct-tab jump are the inseparable core; either failing destroys the value.
- **Current focus:** Phase 2 — alert-loop

## Current Position

Phase: 2 (alert-loop) — EXECUTING
Plan: 10 of 12 complete (Wave 0: 02-00 + 02-01 spike; Wave 1: 02-02 + 02-03; Wave 2: 02-04 + 02-05; Wave 3: 02-06 + 02-07; Wave 4: 02-08 + 02-09). Next executable: 02-10 (Settings + permission banner) → 02-11 (AppDelegate wiring).
Next: Execute 02-10 — SettingsView Form + PermissionBannerView + D2-35 Path A trigger; then 02-11 AppDelegate boot wiring (Pitfall #11 — `restore()` before `listener.start()`; retain WidgetPopoverController, WakeObserver, WorkspaceFrontmostObserver, SessionGCTimer as stored properties).

- **Milestone:** v1
- **Phase:** 02 — Alert Loop, 10/12 plans complete. 2 plans remain.
- **Plan:** 02-09 complete (WakeObserver — NSWorkspace.didWakeNotification observer with retained NSObjectProtocol token, [weak self] capture, deinit cleanup; takes injected `onWake()` closure for Wave 6 wiring; WorkspaceFrontmostObserver — NSWorkspace.didActivateApplicationNotification observer filtered by bundle ID `com.googlecode.iterm2` (T-FRONTMOST-SPAM-01), iterates SessionRegistry.peekPending() and calls AppleScriptHelper.frontmostMatches → clearOne for D2-15 auto-clear; SessionGCTimer — DispatchSourceTimer wrapper, default 30 min interval, retained source). All three carry verbatim "CRITICAL: retain" comment per PATTERNS.md. 4/4 SessionGCTimerTests pass (construction, fires-at-interval, cancel-stops, retention contract); full target 71/71 pass (was 67/67 + 4 new = 71); production build SUCCEEDED. SESS-04 Pattern 6 triple-trigger now complete (lazy ingest GC + WakeObserver + SessionGCTimer); D2-15 auto-clear in place.
- **Status:** Executing Phase 2
- **Progress:** [█████████░] 89%

## Performance Metrics

| Metric | Value |
|--------|-------|
| Phases complete | 1 / 6 |
| Plans complete | 7 / 7 in Phase 01 + 9 / 12 in Phase 02 |
| Requirements covered | 24 / 53 (Phase 1: HOOK-01, HOOK-03, HOOK-04, HOOK-05, HOOK-06, IPC-01, IPC-02, IPC-03, DIST-01, DIST-05 + Phase 2: SESS-01..04, THR-01..02, AUD-01, AUD-02, WIDG-01, WIDG-02, WIDG-03, WIDG-04, WIDG-05, WIDG-06, WIDG-07) |
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

- **Last action:** Completed Plan 02-09 (Phase 2 Wave 4 second half — Wake / Frontmost observers + GC timer). 3 commits on master (sequential mode):
  - `116cdb9` feat(02-09): WakeObserver + WorkspaceFrontmostObserver (SESS-04 + D2-15)
  - `d53931c` test(02-09): add failing SessionGCTimerTests (TDD RED)
  - `bd7bdc0` feat(02-09): SessionGCTimer DispatchSourceTimer wrapper (SESS-04)

  Final verifications: SessionGCTimerTests 4/4 pass (1.384s incl. real-time timer waits), full test target 71/71 pass (was 67/67 + 4 new = 71; zero regressions across Phase 1 / 02-00 / 02-02..09), `xcodebuild build -scheme ClaudeAlertBot` succeeds. Pattern anchors verified: `grep -c 'CRITICAL: retain' App/{WakeObserver,WorkspaceFrontmostObserver,SessionGCTimer}.swift` → 1/1/1 (PATTERNS.md institutional retention pattern), `grep -c '\[weak self\]' …` → 1/1/1, `grep -c 'com.googlecode.iterm2' App/WorkspaceFrontmostObserver.swift` → 1 (T-FRONTMOST-SPAM-01 mitigation).

  Public API frozen for Wave 6 wiring: **WakeObserver(onWake:)** — Wave 6 passes `{ Task { await SessionRegistry.shared.runGC() } }`. **WorkspaceFrontmostObserver()** — self-contained, reads SessionRegistry.peekPending() + AppleScriptHelper.shared. **SessionGCTimer(interval: 30*60, onTick:)** — must call `.start()` after construction; first fire is at `.now() + interval`, NOT immediate. All three MUST be retained as stored properties on AppDelegate (mirrors `signalSources` lineage). SESS-04 Pattern 6 triple-trigger now complete.

  Deviations: None. Plan executed verbatim across both tasks. The plan's must_haves stated WakeObserver "fires `Task { await SessionRegistry.shared.runGC() }`"; the action template (executable contract) shipped that behavior via an injected `onWake` closure that Wave 6 wires to that exact expression — preserves testability and matches AppDelegate's `signalSources` injection style.

- **Files written this plan:**
  - `App/WakeObserver.swift` (created — @MainActor final class; didWakeNotification observer with retained NSObjectProtocol token; injected onWake closure)
  - `App/WorkspaceFrontmostObserver.swift` (created — @MainActor final class; didActivateApplicationNotification observer; bundle-ID iTerm2 filter; D2-15 auto-clear via peekPending + frontmostMatches + clearOne)
  - `App/SessionGCTimer.swift` (created — @MainActor final class; DispatchSourceTimer wrapper; default 30-min repeating; retained source; cancel + deinit symmetric)
  - `ClaudeAlertBotTests/SessionGCTimerTests.swift` (created — 4 unit tests: construction, fires-at-interval, cancel-stops, retention contract)
  - `ClaudeAlertBot.xcodeproj/project.pbxproj` (xcodegen-regenerated)
  - `.planning/phases/02-alert-loop/02-09-SUMMARY.md` (created — Wave 4 closure + Wave 6 wiring template + verifier row bodies + threat dispositions)
  - `.planning/STATE.md`, `.planning/ROADMAP.md` (updated — plan progress 9→10 of 12 in Phase 2; 84% → 89%)
- **Next action:** Execute Plan 02-10 — SettingsView Form + PermissionBannerView + D2-35 Path A trigger (.onAppear → triggerPermissionPrompt). Then Plan 02-11 (Wave 6 AppDelegate boot wiring — retain WidgetPopoverController + WakeObserver + WorkspaceFrontmostObserver + SessionGCTimer as stored properties; HookListener.ingest dispatch; verify-phase-2.sh; Pitfall #11 boot order — `restore()` before `listener.start()`).

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
