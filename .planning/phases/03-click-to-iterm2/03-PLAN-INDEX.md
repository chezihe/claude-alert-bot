# Phase 3: Click-to-iTerm2 — Plan Index

**Created:** 2026-05-08
**Plans:** 10 plans across 7 waves
**Source documents:** `03-CONTEXT.md` (D-ADAPTER + D3-01..20), `03-RESEARCH.md` (Patterns 1-9), `03-PATTERNS.md` (12/12 components mapped)

This index mirrors Phase 2's wave-organized listing inside the phase dir. The orchestrator (`/gsd-execute-phase 03`) reads `wave` from each plan's frontmatter; this file is for human navigation + dependency-graph audit.

## Wave Structure

```
Wave 0  ──  03-00 (test scaffold)
            │
Wave 1  ──  03-01 (contracts: TerminalJumper + iTermSessionID)        ────┐
            03-02 (Reporter TERM_PROGRAM + HookEvent + CabTest)  [parallel]│
                                                                          │
Wave 2  ──  03-03 (HookListener UUID normalize + SessionStore migrate)  ←─┘
            03-04 (AppleScriptHelper extension: jump-by-uuid + focus-frontmost + testConnection)  ←─ depends 03-01
                  [parallel — different file from 03-03]
            │
Wave 3  ──  03-05 (ITerm2Jumper concrete adapter)  ←─ depends 03-01, 03-04
            │
Wave 4  ──  03-06 (PopoverRowView state machine + 도리도리/collapse)  ←─ depends 03-01
            │
Wave 5  ──  03-07 (WidgetPopoverController integration + ContentView state map)  ←─ depends 03-05, 03-06
            03-08 (SettingsStore.lastConnectionTestAt + SettingsView SET-05)  ←─ depends 03-04
                  [parallel — different files from 03-07]
            │
Wave 6  ──  03-09 (verify-phase-3.sh full population + 03-VERIFICATION.md + manual checkpoint)
```

## Plan Listing

| Plan | Wave | Depends On | Goal | Files (scope) | Active SC |
|------|------|------------|------|---------------|-----------|
| 03-00 | 0 | — | Test scaffold + verifier skeleton + MockTerminalJumper fixture + HookEventFactory.term_program param | `scripts/verify-phase-3.sh` (new), `ClaudeAlertBotTests/Fixtures/MockTerminalJumper.swift` (new), `ClaudeAlertBotTests/Fixtures/HookEventFactory.swift` (extend), `project.yml` (test target sources only) | — |
| 03-01 | 1 | 03-00 | Contracts: `TerminalJumper` protocol + `JumpResult` enum + `iTermSessionID.uuid(fromRaw:) / .isValid(_:)` extractor | `App/TerminalJumper.swift` (new), `App/iTermSessionID.swift` (new), `ClaudeAlertBotTests/iTermSessionIDTests.swift` (new), `project.yml` (sources) | — |
| 03-02 | 1 | 03-00 | Reporter `TERM_PROGRAM` envelope field + `HookEvent.term_program: String?` + CabTest mirror | `Reporter/cab-report.sh`, `App/HookEvent.swift`, `CabTest/main.swift`, `ClaudeAlertBotTests/Fixtures/HookEventFactory.swift` (already touched in 03-00; re-extend if needed for term_program param) | — |
| 03-03 | 2 | 03-01 | UUID normalization at HookListener decode + `SessionStore.load()` migration of `:`-prefixed IDs | `App/HookListener.swift`, `App/SessionStore.swift`, `ClaudeAlertBotTests/SessionStoreTests.swift` (extend) | — |
| 03-04 | 2 | 03-01 | `AppleScriptHelper` extension: jump-by-uuid (3s), focus-frontmost (3s), `testConnection()` actor method, `JumpResult` mapping inside ITerm2Jumper-callable surface | `App/AppleScriptHelper.swift`, `ClaudeAlertBotTests/AppleScriptHelperTests.swift` (extend) | SC#5 (3s timeout, background queue) |
| 03-05 | 3 | 03-01, 03-04 | `ITerm2Jumper` concrete `TerminalJumper` impl (thin orchestrator) + `NSApp.activate` regression guard | `App/ITerm2Jumper.swift` (new), `ClaudeAlertBotTests/ITerm2JumperTests.swift` (new) | — |
| 03-06 | 4 | 03-01 | `PopoverRowView` state machine: normal/jumping/missing + 도리도리(±12°)+collapse animation + `RowStateTests` regression guard | `App/PopoverRowView.swift`, `App/PopoverContentView.swift` (state map prop), `ClaudeAlertBotTests/PopoverRowStateTests.swift` (new) | — |
| 03-07 | 5 | 03-05, 03-06 | `WidgetPopoverController.onRowClick` integration with `TerminalJumper` + result-driven row state notification + OSLog `[jump*]` prefixes (`jumped` / `jump-missed` / `jump-denied` / `jump-error`) | `App/WidgetPopoverController.swift`, `App/AppDelegate.swift` (jumper retain via WidgetPopoverController init) | SC#1, SC#2, SC#4 |
| 03-08 | 5 | 03-04 | `SettingsStore.lastConnectionTestAt` + SettingsView SET-05 Section + verbatim copy lock (Korean button + minimal English status labels per D3-19) | `App/SettingsStore.swift`, `App/SettingsView.swift`, `ClaudeAlertBotTests/SettingsViewTests.swift` (extend) | SC#3 |
| 03-09 | 6 | all prior | verify-phase-3.sh full population + Phase 1+2 regression chain + 03-VERIFICATION.md + manual checkpoint for SC#1..5 + Phase 2 verifier `[would-jump]` deprecation note | `scripts/verify-phase-3.sh`, `.planning/phases/03-click-to-iterm2/03-VERIFICATION.md` (new), `scripts/verify-phase-2.sh` (deprecation comment only — no behavior change) | SC#1, SC#2, SC#3, SC#4, SC#5 |

## Decision → Plan Coverage Audit

Every locked decision in `03-CONTEXT.md` maps to at least one plan task:

| Decision | Plan(s) | Coverage |
|----------|---------|----------|
| **D-ADAPTER** | 03-01 (proto), 03-05 (impl), 03-07 (consumer init) | full |
| **D3-01** (`iTermSessionID.uuid(fromRaw:)`) | 03-01 | full |
| **D3-02** (UUID-only semantic re-definition) | 03-01 (validator), 03-03 (apply at decode), 03-04 (compare in scripts) | full |
| **D3-03** (`sessions.json` migration) | 03-03 | full |
| **D3-04** (Phase 2 silent-failure auto-fix + regression guard) | 03-03 (apply), 03-04 (regression test in `AppleScriptHelperTests`) | full |
| **D3-05** (Reporter `TERM_PROGRAM`) | 03-02 | full |
| **D3-06** (UUID single-strategy match) | 03-04 (script), 03-05 (caller) | full |
| **D3-07** (no TTY fallback) | 03-05 (early-return on `.missing`) | full |
| **D3-08** (TokenEater excluded; README CREDIT v6) | n/a in v1 — out of scope reminder in 03-VERIFICATION.md | deferred |
| **D3-09** (3s timeout, compile, queue) | 03-04 | full |
| **D3-10** (Pitfall #1 grep gate) | 03-05 (impl), 03-09 (verifier row) | full |
| **D3-11** (도리도리 + collapse state machine) | 03-06 | full |
| **D3-12** (no text/sound/notification on missing) | 03-06 (no copy added), 03-07 (no UNNotificationCenter call) | full |
| **D3-13** (OSLog `[jump*]` 4-prefix contract) | 03-07 (emit), 03-09 (grep verifier rows) | full |
| **D3-14** (row-state-transition regression guard) | 03-06 (`PopoverRowStateTests`) | full |
| **D3-15** (SET-05 Korean button label `iTerm2 연결 테스트`) | 03-08 (verbatim assert) | full |
| **D3-16** (permission-state branch in SET-05) | 03-04 (`testConnection` perm dispatch), 03-08 (caller branch) | full |
| **D3-17** (3 compiled scripts in actor) | 03-04 | full |
| **D3-18** (`lastConnectionTestAt` `@AppStorage`-equivalent persistence) | 03-08 | full |
| **D3-19** (minimal English status labels: `Connected at %@` / `iTerm2 is not running` / `Automation permission denied`) | 03-08 (verbatim assert) | full |
| **D3-20** (SET-05 verbatim verbatim test + branch unit test) | 03-04 (`testConnection` branches), 03-08 (SettingsView verbatim) | full |

## Requirement → Plan Coverage Audit

| REQ-ID | Plan(s) | Coverage |
|--------|---------|----------|
| **JUMP-01** (click → iTerm2 focus) | 03-05, 03-07 | full |
| **JUMP-02** (UUID-only + friendly fail) | 03-04, 03-05, 03-06, 03-07 | full |
| **JUMP-03** (compile + background queue) | 03-04 | full |
| **JUMP-04** (3s hard timeout) | 03-04 | full |
| **JUMP-05** (debounce — same session no double-call) | 03-06 (row state self-debounce), 03-07 (jumping-state guard) | full |
| **SET-05** (iTerm2 연결 테스트 button) | 03-04 (`testConnection`), 03-08 (UI) | full |
| **ONB-02** (deterministic permission prompt — Phase 2 inheritance) | 03-08 SET-05 documented as exercising existing PermissionDeepLink/triggerPermissionPrompt | inherited from Phase 2 |
| **ONB-03** (-1743 recovery deep-link) | 03-07 (jump-denied path), 03-08 (test-connection denied path) | full |

## Active Success Criteria → Verifier Row Coverage

ROADMAP §"Phase 3" SC#1..5 (SC#6 struck through):

| SC | Plan(s) covering | Verifier rows in 03-09 |
|----|------------------|------------------------|
| SC#1 (3 concurrent sessions, click any → exact tab) | 03-04, 03-05, 03-07 | `verify_3_07_01` (full e2e via 3 cab-test envelopes + manual checkpoint) |
| SC#2 (closed tab → friendly missing UX, queue clears) | 03-06, 03-07 | `verify_3_06_01` (state transition unit test) + `verify_3_07_02` (manual checkpoint) |
| SC#3 (SET-05 button: 1st press triggers TCC; subsequent press focuses tab) | 03-04, 03-08 | `verify_3_08_01` (test-connection branch unit) + `verify_3_08_02` (manual checkpoint) |
| SC#4 (denied → recovery banner with deep-link) | 03-07, 03-08 | `verify_3_07_03` (denied unit) + manual checkpoint reusing Phase 2 PermissionBannerView verifier |
| SC#5 (3s timeout, background queue, 500ms debounce, no beachball) | 03-04, 03-06, 03-07 | `verify_3_04_01` (timeout in source), `verify_3_06_02` (state self-debounce), `verify_3_05_01` (Pitfall #1 grep gate) |

## Cross-Cutting Invariants

Every plan must thread these. The plan body cites the IDs in task `<action>` blocks; 03-09 verifies them as grep gates.

- **D2-29** zero external Swift dependencies — no SwiftPM additions in any Phase 3 plan
- **T-INJECTION-01** static or whitelist-validated AppleScript source — Option C (per-call `NSAppleScript(source: String(format: template, uuid))` with `UUID(uuidString:) != nil` guard) is locked by RESEARCH; alternatives (B/C in CONTEXT terminology, D `2-step` in RESEARCH terminology) are explicitly rejected
- **T-COPY-DRIFT-01** `static let` constants + `SettingsViewTests` verbatim assertions — applied to Korean button label AND English status labels in 03-08
- **Pitfall #1 NSApp.activate regression guard** — verifier grep in 03-09 uses comment-stripped form: `grep -v '^[[:space:]]*//' App/ITerm2Jumper.swift App/AppleScriptHelper.swift | grep -c 'NSApp\.activate'` MUST be 0 (raw `grep -c` would count anti-pattern comments and self-invalidate)
- **Pitfall #11 AppDelegate boot order** — `ITerm2Jumper` is constructed inside `WidgetPopoverController.init` (existing `AppDelegate` line 58 site, single-line edit); no AppDelegate restructure
- **D3-13 OSLog `[jump*]` 4-prefix contract** — 03-07 emits exactly 4 prefixes (`[jumped`, `[jump-missed`, `[jump-denied`, `[jump-error`); 03-09 verifier asserts each
- **Phase 2 D2-08 hook site call signature** — `onRowClick(sessionID: String)` keeps signature in 03-07; body changes only

## Phase 2 Verifier Cross-Phase Touch

Phase 2's `verify-phase-2.sh` row 2-08-01 greps for `[would-jump session=...]` (the literal D2-08 hook). Phase 3 03-07 deletes that literal in favor of `[jumped]`/`[jump-missed]`/`[jump-denied]`/`[jump-error]`. Disposition (decided in this plan-phase, executed in 03-09):

- **Add an explicit comment in `scripts/verify-phase-2.sh`** noting the row is superseded by `[jumped` / `[jump-missed`. Do NOT delete or modify the row's grep — Phase 2 is locked-green; this is a documentation-only touch.
- **03-VERIFICATION.md records the contract change** so any future Phase 2 re-run knows the row is expected to fail post-Phase 3 (and that's correct behavior, not a regression).

This is the *only* cross-phase touch in Phase 3.

---
*Phase 3 plan index*
*Phase: 03-click-to-iterm2*
*Plans: 10*
*Waves: 7 (0..6)*
