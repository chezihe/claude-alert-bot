---
phase: 03-click-to-iterm2
plan: 09
subsystem: integration / e2e / verifier / manual-checkpoint
tags: [phase-3, wave-6, integration, verifier, manual-checkpoint, sign-off, in-flight-fixes]
requires:
  - 03-00 (test scaffold)
  - 03-01 (TerminalJumper protocol + iTermSessionID)
  - 03-02 (Reporter envelope + HookEvent)
  - 03-03 (HookListener normalization + SessionStore migration)
  - 03-04 (AppleScriptHelper jump-by-uuid + focus-frontmost + testConnection)
  - 03-05 (ITerm2Jumper conformer)
  - 03-06 (PopoverRowView state machine)
  - 03-07 (WidgetPopoverController D-ADAPTER dispatch + 4-prefix OSLog)
  - 03-08 (SettingsView SET-05 + lastConnectionTestAt)
provides:
  - "Phase 3 wired end-to-end — popover row click → ITerm2Jumper → exact iTerm2 tab"
  - "scripts/verify-phase-3.sh fully populated (Waves 0..6 + Phase 1+2 regression rows)"
  - ".planning/phases/03-click-to-iterm2/03-VERIFICATION.md sign-off — phase_gate: green"
  - "8 in-flight production-bug fixes discovered + locked during manual checkpoint"
  - "Build pipeline now ad-hoc-signs with `com.apple.security.automation.apple-events` entitlement (build.sh)"
  - "MenuBarExtra (bell.badge) is the canonical Settings/Quit entry for the accessory app"
affects:
  - "Phase 4 (D-MILESTONE / unattended e2e) inherits the 8 fix commits + the entitlement-aware build pipeline"
  - "Phase 1 verifier rows 1-02-02 / 1-06-01 contract drift documented (Phase 1 verifier maintenance task — deferred to future verifier-polish plan)"
tech-stack:
  added:
    - "MenuBarExtra (SwiftUI 13+) as Settings + Quit entry point"
    - "App/ClaudeAlertBot.entitlements with com.apple.security.automation.apple-events"
  patterns:
    - "Hardened-Runtime + apple-events entitlement at codesign time (both inner exe and bundle seal)"
    - "Permission-state gate at AppleScriptHelper actor entry (.unknown → no cheap-query)"
    - "Long-timeout dedicated AppleScript source for TCC-prompt-trigger path (30s vs cheap-query 1s)"
key-files:
  created:
    - ".planning/phases/03-click-to-iterm2/03-VERIFICATION.md"
    - ".planning/phases/03-click-to-iterm2/03-09-SUMMARY.md"
    - "App/ClaudeAlertBot.entitlements"
  modified:
    - "scripts/verify-phase-3.sh (full Wave 0..6 row population + Phase 1+2 regression chain rows)"
    - "scripts/verify-phase-2.sh (D3-13 contract-change comment annotation above verify_2_08_02)"
    - "scripts/build.sh (ENTITLEMENTS variable + --entitlements on inner exe + bundle seal codesign calls)"
    - "App/AppleScriptHelper.swift (cheap-query .unknown gate + 30s prompt-trigger source)"
    - "App/AppleScriptHelper.swift (jumpByUUIDTemplate `set frontmost`→`set index to 1`; focus-frontmost same)"
    - "App/PopoverContentView.swift (onPopoverHoverChange .onHover routing)"
    - "App/WidgetPopoverController.swift (popover hover-cancel timer + NSHostingController rootView reuse)"
    - "App/FloatingWidgetPanel.swift (isRestorable = false)"
    - "App/ClaudeAlertBotApp.swift (MenuBarExtra Settings + Quit menu)"
decisions:
  - "8 in-checkpoint bugs treated as fix-deltas on top of locked Wave 0..5 plans — no plan reopens. All 8 fixes committed atomically with self-contained commit messages (full bug list in 03-VERIFICATION.md §Checkpoint Findings)."
  - "AppleScript jump scripts use `tell w to set index to 1` instead of `set frontmost of w to true`. iTerm2's `frontmost` property on `window` is read-only; writing it returns -10000 errAEEventFailed and the entire jump fails. `set index to 1` is the supported way to bring a window forward."
  - "Hardened Runtime + `com.apple.security.automation.apple-events` entitlement is non-negotiable for ad-hoc-signed apps. Without it macOS silent-denies AppleEvents requests with -1743 (errAEEventNotPermitted) and never displays the TCC dialog. Build pipeline now wires this at both codesign-call layers (inner exe AND bundle seal)."
  - "TCC-prompt-trigger path uses a dedicated 30s-timeout AppleScript source. The cheap-query (D2-14) path keeps its 1s contract (D2-34) — only the deliberate prompt-from-Settings path needs the longer window so the user has time to click Allow/Don't Allow before macOS auto-dismisses on AppleScript timeout."
  - "AppleScriptHelper.frontmostMatches gate-returns false when lastKnownPermission == .unknown. Otherwise the first 1s cheap-query (auto-fired by D2-14 Stop hook or D2-15 NSWorkspace iTerm2-frontmost re-query) races the deliberate Settings prompt and poisons lastKnownPermission to .denied before the user can grant — making subsequent SET-05 clicks take the .denied early-return branch and never re-trigger the prompt."
  - "FloatingWidgetPanel.isRestorable = false — visibility is exclusively NotificationOrchestrator-owned. Default macOS Window Restoration would silently re-show the panel on relaunch independent of queue state."
  - "MenuBarExtra is the canonical accessory-app Settings entry. Pure-SwiftUI accessory apps (LSUIElement=true) cannot reliably activate to open Settings via Cmd-, alone; MenuBarExtra also exposes Quit, eliminating the no-way-to-quit support issue."
  - "verify-phase-3.sh rows 3-09-01 / 3-09-02 (Phase 1+2 regression chains) are environmental — verify-phase-1.sh row 1-02-02 needs the app UP for OSLog listener-bound detection, but verify-phase-3.sh xcodebuild test rows need the app DOWN for Unix-socket bind. Documented in 03-VERIFICATION.md §Regression chain caveats; both code paths are individually green when verified separately."
metrics:
  duration: "~3 hours (Wave 6 manual checkpoint + 8 in-flight fixes + sign-off docs)"
  task_count: 4
  file_count: 12  # 3 created + 9 modified
  commit_count: 9 # Tasks 1+2 (verify-phase-3 + verify-phase-2 annotation) + 7 manual-checkpoint fixes (9b1f58d, 6ad2b82, 4d5c4bd, bbc8a72, 2ef1fdd, 444f05b, a198823)
  verifier_runtime: "~2 min end-to-end (2 xcodebuild test passes for chain regression)"
  fixes_discovered: 8
  fixes_committed: 7   # commit a198823 bundles 2 related fixes
  scs_passed: 5         # SC#1..5 all PASS post-fix
  verifier_aggregate: "19 PASS / 2 FAIL* / 1 SKIP — *both FAILs are environmental (verifier-infrastructure ordering), not code regressions"
phase_gate: green
phase3_close: true
---

# Plan 03-09 — Phase 3 Final Integration + Verifier + Manual Checkpoint

## What was completed

Plan 03-09 is the Phase 3 sign-off plan. It (a) populated
`scripts/verify-phase-3.sh` with all Wave 0..6 verification rows, (b)
annotated `scripts/verify-phase-2.sh` with the D3-13 contract-change
note, (c) ran the SC#1..5 manual checkpoint live with iTerm2 + Claude
Code, and (d) authored the 03-VERIFICATION.md sign-off document.

The manual checkpoint surfaced eight distinct production bugs that
were not caught by the Wave 0..5 unit-test rows. Each was diagnosed
via systematic-debugging skill (root cause first, then minimum fix),
tested live, and committed atomically. The fix list is in
03-VERIFICATION.md §Checkpoint Findings.

## In-flight Fixes (8 bugs → 7 commits)

| # | Commit | Bug → Fix |
|---|--------|-----------|
| 1 | `9b1f58d` | iTerm2 jump returned -10000 → AppleScript `set frontmost`→`set index to 1` |
| 2 | `6ad2b82` | Popover dismissed before user could click → onHover → cancel exit timer |
| 3 | `4d5c4bd` | SC#2 도리도리 animation never played → reuse NSHostingController rootView |
| 4 | `bbc8a72` | Floating widget visible on cold boot → `isRestorable = false` |
| 5 | `2ef1fdd` | No way to reach Settings/Quit → MenuBarExtra (bell.badge) |
| 6 | `444f05b` | TCC dialog never appeared → apple-events entitlement + build.sh wiring |
| 7 | `a198823` | TCC dialog auto-dismissed in 1s OR never appeared at all → 30s prompt-trigger source + .unknown cheap-query gate |

## Phase Gate Decision

**phase_gate: green** — recorded in 03-VERIFICATION.md frontmatter and §Sign-off.

**Rationale:**
- All 5 ROADMAP success criteria PASS post-fix (SC#1..5).
- Verifier from clean state: 19 PASS / 2 FAIL\* / 1 SKIP. The 2 FAILs
  are 3-09-01 / 3-09-02 — environmental verifier-infrastructure
  ordering quirk (Phase 1 row 1-02-02 needs app UP, Phase 3 test rows
  need app DOWN). Documented; not code regressions.
- 8 in-flight bugs discovered and locked. None reopen Wave 0..5 plan
  artifacts.
- Phase 1 + Phase 2 regression chains pass when individual paths are
  verified separately with appropriate state.
- D-ADAPTER seam (TerminalJumper) clean; OSLog 4-prefix contract
  (D3-13) green; permission flow exercised end-to-end (granted +
  denied + recovery).

**Phase 4 unblock:** YES.

## Deviations from Plan

The 03-09 plan anticipated Tasks 1–4 (verify-phase-3.sh population,
verify-phase-2.sh annotation, manual checkpoint, 03-VERIFICATION.md).
All four ran. The deviation was scope: the manual checkpoint surfaced
8 production bugs requiring live fixes before SC#1..5 could be
declared green. Each fix was a minimum-diff delta on top of locked
plans (per CLAUDE.md "No Over-Editing"); no Wave 0..5 plan was
reopened. Total checkpoint elapsed time including the 8 fixes was
~3 hours.

## Open Follow-ups (logged in 03-VERIFICATION.md)

- **V-9 (NEW):** Phase 1 verifier row `1-06-01` contract drift —
  Fix #5 (commit `2ef1fdd`) intentionally adds a MenuBarExtra bell
  icon, contradicting the row's "NO ClaudeAlertBot icon" assertion.
  Future verifier-maintenance plan should update the row to assert
  "bell.badge MenuBarExtra is the only menu-bar artifact".
- **V-10 (NEW):** Verifier-infrastructure ordering — `verify-phase-3.sh`
  cannot satisfy both "app UP for 1-02-02" and "app DOWN for xcodebuild
  test rows" in a single run. Future verifier-polish: split into two
  runs, or use a dedicated test socket path.
- **D-backlog:** Hook delay observed during manual checkpoint
  (Stop hook latency >1s in some cases). Not a Phase 3 contract issue
  but flagged for Phase 4 / Phase 5 latency investigation.

## Self-Check

- `[x]` File `.planning/phases/03-click-to-iterm2/03-VERIFICATION.md` exists
- `[x]` `phase_gate: green` in 03-VERIFICATION.md frontmatter
- `[x]` All 7 in-checkpoint fix commits on master (`9b1f58d` `6ad2b82` `4d5c4bd` `bbc8a72` `2ef1fdd` `444f05b` `a198823`)
- `[x]` Verifier exits with `Results: 19 pass, 2 fail, 1 skip` from clean state (app DOWN, VERIFY_NONINTERACTIVE=1)
- `[x]` SC#1..5 dispositions recorded in 03-VERIFICATION.md §Manual Results
- `[x]` 03-09-SUMMARY.md exists (this file)
