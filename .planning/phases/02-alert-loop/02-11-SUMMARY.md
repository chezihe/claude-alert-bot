---
phase: 02-alert-loop
plan: 11
subsystem: integration / e2e / verifier
tags: [phase-2, wave-6, integration, app-delegate, e2e, verifier, manual-checkpoint, lifecycle, d2-29, pitfall-11]
requires:
  - 02-04 (SessionRegistry actor — Pitfall #11 contract)
  - 02-05 (AppleScriptHelper — D2-35 Path B suppress closure)
  - 02-06 (NotificationOrchestrator + SoundPlayer)
  - 02-07 (FloatingWidgetWindowController + WidgetControllerProtocol)
  - 02-08 (WidgetPopoverController — D2-08 anchor)
  - 02-09 (WakeObserver + WorkspaceFrontmostObserver + SessionGCTimer)
  - 02-10 (SettingsView — wired by Settings { SettingsView() } scene here)
provides:
  - "Phase 2 wired end-to-end — Stop event → SessionRegistry.ingest → NotificationOrchestrator → FloatingWidget + WidgetPopover"
  - "Pitfall #11 boot order locked: SessionRegistry.restore precedes listener.start (closes Phase 1 V-2 race)"
  - "@main SwiftUI App entry (D2-29 compliance) — 외부 의존성 0 invariant preserved"
  - "scripts/verify-phase-2.sh fully populated (Waves 0..6 + Phase 1 regression row)"
  - ".planning/phases/02-alert-loop/02-VERIFICATION.md sign-off — phase_gate: green"
affects:
  - "Phase 3 ITermBridge inherits HookListener.handle dispatch verbatim; replaces [would-jump session=<uuid>] in WidgetPopoverController.onRowClick"
  - "Phase 3 AppDelegate boot order extends steps 6-12 (ITermBridge construction slots before listener.start)"
tech-stack:
  added:
    - "SwiftUI Settings scene (`Settings { SettingsView() }`) — OS-managed ⌘,"
    - "@NSApplicationDelegateAdaptor (App lifecycle bridge)"
  patterns:
    - "Pitfall #11 boot order: restore() before listener.start()"
    - "MainActor dispatch wrapper around HookListener.handle for SettingsStore reads"
    - "D2-35 Path B trigger inside HookListener (first Stop with permission=.unknown)"
key-files:
  created:
    - ".planning/phases/02-alert-loop/02-VERIFICATION.md"
  modified:
    - "App/AppDelegate.swift (boot steps 6-12 wiring + applicationWillFinishLaunching for .accessory)"
    - "App/HookListener.swift (handle(buffer:) dispatches to SessionRegistry.ingest)"
    - "App/ClaudeAlertBotApp.swift (renamed from main.swift — @main SwiftUI App per D2-29)"
    - "scripts/verify-phase-2.sh (Wave 0-5 rows lifted from upstream SUMMARYs + Wave 6 SC#1..6 + 2-11-99 Phase 1 regression)"
decisions:
  - "Pitfall #11 boot order locked in `applicationDidFinishLaunching`: SessionRegistry.shared.restore() awaits BEFORE listener.start(). The Task wraps both in same MainActor block so listener.start cannot run concurrently with restore. Closes Phase 1 V-2 race in steady state."
  - "main.swift renamed to ClaudeAlertBotApp.swift to host `@main struct ClaudeAlertBotApp: App` per D2-29. Xcode auto-derives entry from `@main`; no `-parse-as-library` flag needed."
  - "AppDelegate `applicationWillFinishLaunching` sets NSApp.setActivationPolicy(.accessory) BEFORE SwiftUI realizes any scene. Belt-and-suspenders alongside LSUIElement=true (Info.plist)."
  - "Zero `NSApp.activate(...)` calls anywhere in UI/lifecycle code — D2-29 + Settings scene + LSUIElement do the right thing without any hand-rolled activation."
  - "HookListener.handle dispatch wraps SettingsStore reads (threshold, sound, perm) in `Task { @MainActor in ... }` since SettingsStore is @MainActor; suppressIfFrontmost closure invokes AppleScriptHelper only when permission == .granted (D2-14 + D2-35 trade-off)."
  - "verify-phase-2.sh row 2-11-99 (Phase 1 regression) uses `VERIFY_NONINTERACTIVE=1 bash scripts/verify-phase-1.sh` so phase-1's verify_1_06_01 manual visual row defers instead of hanging on `read -r` with no controlling stdin."
  - "Verifier row 2-11-02 (SC#2) FAIL is a documented cab-test tooling artifact (UUID-per-invocation cannot pair user_prompt_submit + stop in shell-driven e2e). Underlying THR-01 logic is locked by SessionRegistryTests (row 2-04-01 PASS). New follow-up V-7 logged for cab-test --session-id=<uuid> argv extension in Phase 3+ verifier-tooling polish."
metrics:
  duration: "~45 min (across 2 executor sessions: original Tasks 1-2 + checkpoint resume Task 4)"
  task_count: 4
  file_count: 5  # 4 modified + 1 created (02-VERIFICATION.md)
  completed_date: "2026-05-08"
---

# Phase 2 Plan 11: Wave 6 Integration + Phase 2 Sign-Off Summary

Wave 6 integration plan — wires every parallel Phase 2 component (SessionRegistry, AppleScriptHelper, NotificationOrchestrator, FloatingWidget, WidgetPopover, WakeObserver, SessionGCTimer, SettingsView) into AppDelegate's boot sequence in Pitfall #11 order, hooks HookListener.handle up to SessionRegistry.ingest dispatch (the missing piece from Phase 1's logger-only emit), converts the entry point to a `@main` SwiftUI App per D2-29, lifts every upstream `verify_2_*_*` row body into `scripts/verify-phase-2.sh`, adds SC#1..6 e2e rows + Phase 1 regression, and produces `02-VERIFICATION.md` sign-off declaring **phase_gate: green**.

## What Was Built

### Task 1: AppDelegate boot wiring + HookListener dispatch + @main SwiftUI App (D2-29)

Committed in `46ed6c9 feat(02-11): wire Phase 2 boot order + HookListener dispatch + @main SwiftUI App`.

**`App/ClaudeAlertBotApp.swift`** (renamed from `App/main.swift`) — `@main` SwiftUI App entry hosting `Settings { SettingsView() }` scene with `@NSApplicationDelegateAdaptor(AppDelegate.self)`. Zero external dependencies. The OS handles ⌘, automatically.

**`App/AppDelegate.swift`** — Phase 1 steps 1-5 preserved verbatim. New `applicationWillFinishLaunching` sets `.accessory` activation policy before SwiftUI realizes any scene. New steps 6-12 in `applicationDidFinishLaunching` wire all Phase 2 components in Pitfall #11 order:

```
applicationWillFinishLaunching:
  1. NSApp.setActivationPolicy(.accessory)            # before any scene realizes

applicationDidFinishLaunching:
  2. SocketPaths.validateSocketPathLength()           # Pitfall #6 — Phase 1 step 1
  3. ensureDirectories()                              # Phase 1 step 2
  4. reclaimSocketIfStale(...)                        # Phase 1 step 3
  5. installSignalHandler(SIGTERM); installSignalHandler(SIGINT)   # Phase 1 step 5

  Task { @MainActor in:
    6. await SessionRegistry.shared.restore()         # MUST be first (Pitfall #11)
    7. construct FloatingWidgetWindowController + WidgetPopoverController + NotificationOrchestrator
       widget.hoverDelegate = popoverController       # WidgetHoverDelegate wire
    8. await SessionRegistry.shared.bind(notifier: orchestrator)
    9. orchestrator.refreshQueueState(...)            # restore-broadcast (registry replayed at restore time when notifier was nil)
   10. install WakeObserver, WorkspaceFrontmostObserver, SessionGCTimer (all retained as stored properties; CRITICAL: retain comments preserved per 02-09 contract)
   11. _ = AppleScriptHelper.shared                   # eager compile (no permission trigger here — D2-35 Path A in SettingsView.onAppear, Path B implicit via first Stop ingest's suppressIfFrontmost closure)
   12. listener.start()                               # AFTER all wiring — the missing piece from Phase 1
  }
```

OSLog confirmation observed live: `[lifecycle] Phase 2 components wired (orchestrator, widget, popover, observers, GC timer)` precedes `[lifecycle] listener bound (Phase 2 wiring complete)` in every boot.

**`App/HookListener.swift`** — Phase 1 lines preserved verbatim including `ingressLog.notice(...)` (Phase 1 verifier row 1-04-01 still greps for it). After the ingress log line, `handle(buffer:)` now dispatches the decoded HookEvent to `SessionRegistry.shared.ingest` via a `Task { @MainActor in ... }` wrapper that reads SettingsStore.shared (threshold, sound, perm) on the MainActor and constructs the `suppressIfFrontmost` closure honoring D2-14 (frontmost suppress) + D2-35 Path B (first-Stop permission trigger when perm == .unknown).

### Task 2: verify-phase-2.sh fully populated

Committed in `02fb8ed feat(02-11): populate verify-phase-2.sh with all Wave 0-6 rows`.

Lifted every `verify_2_*_*` row body from upstream plan SUMMARYs (Waves 0-5) and added Wave 6 SC#1..6 e2e rows + 2-11-00 build row + 2-11-99 Phase 1 regression row:

| Wave | Rows | Source |
|------|------|--------|
| 0 (02-00) | 2-00-01, 2-00-02 | Already in skeleton |
| 1 (02-02) | 2-02-01 (PermissionDeepLink), 2-02-02 (NSAppleEventsUsageDescription D2-33) | 02-02 SUMMARY |
| 1 (02-03) | 2-03-01 (SessionRecord), 2-03-02 (ProjectName) | 02-03 SUMMARY |
| 2 (02-04) | 2-04-01 (SessionRegistry), 2-04-02 (SessionStore) | 02-04 SUMMARY |
| 2 (02-05) | 2-05-01 (AppleScriptHelper) | 02-05 SUMMARY |
| 3 (02-06) | 2-06-01 (SoundPlayer), 2-06-02 (NotificationOrchestrator) | 02-06 SUMMARY |
| 3 (02-07) | 2-07-01 (FloatingWidgetPanel + Positioning), 2-07-02 (WindowController build + protocol conformance) | 02-07 SUMMARY |
| 4 (02-08) | 2-08-01 (PopoverContent), 2-08-02 (WidgetPopoverController build + D2-08 anchor) | 02-08 SUMMARY |
| 4 (02-09) | 2-09-01 (Observer build + retention pattern), 2-09-02 (SessionGCTimer interval test) | 02-09 SUMMARY |
| 5 (02-10) | 2-10-01 (SettingsView + PermissionBanner copy regression) | 02-10 SUMMARY |
| 6 (02-11) | 2-11-00 (build), 2-11-01..06 (SC#1..6 e2e), 2-11-99 (Phase 1 regression) | THIS plan |

Phase 1 regression row uses `VERIFY_NONINTERACTIVE=1 bash scripts/verify-phase-1.sh` so phase-1's `verify_1_06_01` manual visual row defers instead of hanging on `read -r` with no controlling stdin.

### Task 3: SC#3 manual checkpoint — APPROVED

Resume signal `approved` received 2026-05-08. All 11 sub-checks observed and recorded in 02-VERIFICATION.md §"Manual Results":

1. App boot + `pgrep -fl ClaudeAlertBot` → APPROVED
2. Trigger alert (cab-test 31s) → widget appears top-right → APPROVED
3. Multi-Space test (Mission Control / Ctrl-Right) → widget follows → APPROVED (`.canJoinAllSpaces`)
4. Full-screen test (Safari ⌃⌘F) → widget appears ABOVE → APPROVED (`.fullScreenAuxiliary`)
5. Stage Manager test → widget remains visible → APPROVED (`.stationary + .fullScreenAuxiliary`)
6. Sleep/wake test (30s sleep) → widget still present → APPROVED
7. Lid close/open test → widget still present → APPROVED
8. No focus steal — keystrokes land in foreground app, not widget → APPROVED (`.nonactivatingPanel`)
9. Click widget → widget disappears → APPROVED (D2-08 `[would-jump session=<uuid>]` OSLog)
10. Hover popover (150ms entry delay → popover appears) → APPROVED (Pattern 8 spike verdict confirmed live)
11. Settings scene (D2-29) — ⌘, opens SettingsView reliably → APPROVED

No focus-steal anomalies. Cmd-Tab pollution feared in RESEARCH §Pitfall #2 / advisor A1 risk did not materialize on macOS 26.4.1 — reconfirmed under full Phase 2 wiring (the 02-01 spike already ruled this out, but SC#3 is the e2e re-verification with all components active).

### Task 4: 02-VERIFICATION.md sign-off + STATE.md + ROADMAP.md update

This task. Wrote `.planning/phases/02-alert-loop/02-VERIFICATION.md` (frontmatter `phase_gate: green`); updated `.planning/STATE.md` to reflect Phase 2 closure (12/12 plans done, 19/19 cumulative); ran `node $HOME/.claude/get-shit-done/bin/gsd-tools.cjs roadmap update-plan-progress 2 02-11 complete` to update ROADMAP.md.

## Verifier Run Tally (final)

`VERIFY_NONINTERACTIVE=1 bash scripts/verify-phase-2.sh` from clean state (no live ClaudeAlertBot, fresh socket, fresh sessions.json):

```
Results: 23 pass, 1 fail, 2 skip
```

26 total rows. Single FAIL is `2-11-02` (SC#2 5s turn → no THR-01 below-threshold log) — a documented cab-test UUID-per-invocation tooling artifact, NOT a code regression. The underlying THR-01 below-threshold logic is locked by `SessionRegistryTests` (row 2-04-01 PASS), which exercises paired-session_id below-threshold paths exhaustively. Detailed analysis in 02-VERIFICATION.md §"SC#2 caveat".

Two SKIPs: `2-00-02` (cab-test predates `--event=` argv on a stale build — superseded by `2-11-00` which builds the current binary), `2-11-03` (SC#3 manual checkpoint — recorded as `approved` in §"Manual Results").

## Phase 1 Regression

Row `2-11-99` PASS. `VERIFY_NONINTERACTIVE=1 bash scripts/verify-phase-1.sh` exits 0; Phase 1 invariants (HOOK-01, IPC-01..03, DIST-01, DIST-05) preserved. As a side benefit, Pitfall #11 boot ordering closes the V-2 listener-uptime polish gap in steady state — the listener now reliably binds AFTER restore, eliminating the timing-window race that previously dropped real-Claude OSLog ingress lines.

## ROADMAP SC Verdicts

| # | Criterion | Verdict |
|---|-----------|---------|
| 1 | 31s turn → widget + project name + multi-Space + no focus steal | **green** |
| 2 | 5s turn → no widget, no sound (threshold filter) | **green** (locked by 2-04-01 unit; 2-11-02 verifier-tooling artifact) |
| 3 | Widget persists across Space/sleep/lid until click | **green** (Task 3 manual checkpoint approved, 11/11 sub-checks) |
| 4 | Settings change immediate + persist across restart + Test notification | **green** |
| 5 | Kill+restart restores pending alert; in-flight >6h GC'd | **green** |
| 6 | Orphan stop → fallback `?` alert (never silently dropped) | **green** |

## D2-29 Compliance Trace

| Aspect | Evidence |
|--------|----------|
| `@main` SwiftUI App entry | `App/ClaudeAlertBotApp.swift` (renamed from `main.swift`) — `grep -E '@main'` returns 1 |
| `Settings { SettingsView() }` scene | `grep -E 'Settings\s*\{' App/ClaudeAlertBotApp.swift` returns the scene |
| `@NSApplicationDelegateAdaptor(AppDelegate.self)` | `grep 'NSApplicationDelegateAdaptor' App/ClaudeAlertBotApp.swift` returns 1 |
| `@AppStorage` used for SettingsStore | `grep '@AppStorage' App/SettingsStore.swift` returns property wrappers |
| 외부 의존성 0 | No `Package.swift`; no SwiftPM dependencies; xcodebuild build succeeds |
| ⌘, opens Settings | Task 3 sub-check 11 APPROVED |
| No NSWindow-based settings UI | `grep -E 'presentSettings\|settingsWindow\|installSettingsMenuBinding' App/AppDelegate.swift` returns 0 |
| No `NSApp.activate(...)` in UI/lifecycle | LSUIElement preserved; OS handles activation |
| `.accessory` policy in `applicationWillFinishLaunching` | Belt-and-suspenders alongside `LSUIElement=true` |

## Phase Gate Decision

**phase_gate: green** — recorded in 02-VERIFICATION.md frontmatter and §"Phase Gate Decision".

**Rationale:** All 6 ROADMAP success criteria are green. The single verifier FAIL (`2-11-02`) is a documented `cab-test` UUID-per-invocation tooling artifact, not a code regression — the underlying THR-01 logic is locked by passing unit tests. SC#3 manual checkpoint approved with all 11 sub-checks observed. D2-29 compliance gates all hold. Pitfall #11 boot order verified live via OSLog. Phase 1 regression PASSes.

**Phase 3 unblock:** YES.

## Deviations from Plan

None. Tasks 1, 2, 4 executed verbatim per plan; Task 3 returned a clean `approved` signal with no observations requiring follow-up beyond the carry-overs already captured in 02-VERIFICATION.md §"Open Follow-ups".

## Open Follow-ups (logged in 02-VERIFICATION.md)

- **V-7 (NEW):** `cab-test --session-id=<uuid>` argv extension so verifier row 2-11-02 (SC#2) can drive the THR-01 below-threshold path end-to-end at the shell level. Phase 3+ verifier-tooling polish.
- **V-8 (NEW):** REQUIREMENTS.md `WIDG-02 [x]` premature mark hygiene — future verifier should grep-assert `.nonactivatingPanel` + `canBecomeKey=false` anchors at phase-gate to catch similar premature marks. See `.planning/phases/02-alert-loop/deferred-items.md`.
- **V-2:** Phase 1 verifier row 1-02-02 transient FAIL on cold-cache verifier runs (listener-uptime / log-show timing-window). Closed in steady state by Pitfall #11 wiring; cold-cache OSLog flush race is the remaining edge. NOT a Phase 2 regression. Phase 5+ verifier polish.

## Self-Check: PASSED

- `[ ]` File `.planning/phases/02-alert-loop/02-VERIFICATION.md` exists → FOUND
- `[ ]` `phase_gate: green` in 02-VERIFICATION.md frontmatter → FOUND
- `[ ]` Commit `46ed6c9` (Task 1: boot wiring) in `git log --oneline --all` → FOUND
- `[ ]` Commit `02fb8ed` (Task 2: verify-phase-2.sh population) in `git log --oneline --all` → FOUND
- `[ ]` Verifier exits with `Results: 23 pass, 1 fail, 2 skip` from clean state → CONFIRMED 2026-05-08
- `[ ]` Phase 1 regression row 2-11-99 PASS → CONFIRMED
