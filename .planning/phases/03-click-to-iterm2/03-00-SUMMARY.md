---
phase: 03-click-to-iterm2
plan: 00
subsystem: testing
tags: [phase-3, wave-0, test-scaffold, nyquist, verifier, fixtures, iterm2, jump]

# Dependency graph
requires:
  - phase: 02-alert-loop
    provides: "scripts/verify-phase-2.sh harness pattern; ClaudeAlertBotTests/Fixtures/HookEventFactory + MockNotifier; sentinel test_targetCompilesAndLinks"
provides:
  - "scripts/verify-phase-3.sh skeleton (smoke row 3-00-01 + downstream-row placeholders for 03-01..03-09)"
  - "ClaudeAlertBotTests/Fixtures/MockTerminalJumper.swift (compile-gated until 03-01 lands TerminalJumper / JumpResult / CompletedSession)"
  - "HookEventFactory.stop() and userPromptSubmit() with optional termProgram parameter (default = nil; preserves all Phase 2 call sites)"
affects: [03-01-protocols, 03-02-envelope, 03-03-listener-decode, 03-04-applescript-extension, 03-05-iterm2-jumper, 03-06-popover-row, 03-07-popover-controller, 03-08-settings-set05, 03-09-e2e]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Wave 0 / Wave 1 sequencing: ship test fixture in Wave 0 wrapped in `#if false`, remove the gate + add conformance line in Wave 1 (mirrors Phase 2 02-00 → 02-06 MockNotifier+NotifierProtocol pattern)"
    - "Verifier skeleton inheritance: copy verify-phase-N-1.sh helper block byte-identical, add per-phase constants and rows, leave wave-by-wave placeholder comments so downstream executors graft into known anchors"
    - "JSONSerialization dict over string template in test factories — additive JSON keys insert without escaping concerns"

key-files:
  created:
    - scripts/verify-phase-3.sh
    - ClaudeAlertBotTests/Fixtures/MockTerminalJumper.swift
    - .planning/phases/03-click-to-iterm2/03-00-SUMMARY.md
  modified:
    - ClaudeAlertBotTests/Fixtures/HookEventFactory.swift
    - ClaudeAlertBot.xcodeproj/project.pbxproj  # xcodegen regen — registered new fixture file

key-decisions:
  - "MockTerminalJumper wrapped in `#if false` (not a separate xcodegen exclude) — minimal-edit, single-line removal in 03-01"
  - "HookEventFactory body switched from string template to JSONSerialization dict — required because optional term_program key cannot be cleanly inlined into a fixed-shape template; keeps Phase 2 wire-path semantics identical (still decoded via JSONDecoder)"
  - "Verifier mirrors verify-phase-2.sh helper block (lines 1-100) verbatim per CLAUDE.md 'preserve original code' — only constants block + smoke row + placeholder comments are net-new"

patterns-established:
  - "Wave 0 compile gate (`#if false` … `#endif`) for forward-spec fixtures whose collaborator types arrive in a later wave"
  - "verify_3_NN_NN function naming + main() commented call list → downstream plans uncomment their call as they graft in their function"
  - "Default-nil parameter for new optional envelope fields preserves zero-edit backward-compat for upstream call sites"

requirements-completed: [JUMP-02]

# Metrics
duration: ~9min
completed: 2026-05-08
---

# Phase 3 Plan 00: Wave 0 Test Scaffold Summary

**verify-phase-3.sh harness + MockTerminalJumper compile-gated fixture + HookEventFactory.termProgram optional param — every downstream Phase 3 plan now has Nyquist-passing automated-row infrastructure.**

## Performance

- **Duration:** ~9 min (xcodebuild test runs dominate)
- **Started:** 2026-05-08T14:49Z (approx — first task action)
- **Completed:** 2026-05-08T14:58:22Z
- **Tasks:** 3
- **Files modified:** 3 (1 created verifier, 1 created fixture, 1 modified factory) + pbxproj regen

## Accomplishments

- `scripts/verify-phase-3.sh` runs end-to-end: smoke row 3-00-01 PASSes, summary prints, exit 0
- `MockTerminalJumper` ships in the test target compile-gated — sentinel test passes, gate removal in 03-01 is a 2-line diff (delete `#if false` / `#endif`)
- `HookEventFactory.stop` + `userPromptSubmit` extended with optional `termProgram` parameter — full 82-test suite stays green (zero regressions)
- `verify-phase-2.sh` byte-identical (verified via `git diff` exit empty)

## Task Commits

Each task committed atomically:

1. **Task 1: scripts/verify-phase-3.sh skeleton** — `7a6a6e9` (feat)
2. **Task 2: MockTerminalJumper.swift compile-gated fixture** — `ede3a4a` (test) — also includes pbxproj regen
3. **Task 3: HookEventFactory.termProgram parameter** — `badb66d` (test)

(Plan-metadata commit appended after this SUMMARY.md is staged.)

## Files Created/Modified

- `scripts/verify-phase-3.sh` — Phase 3 single-shot validation harness; helper block copied verbatim from verify-phase-2.sh lines 1-100, with Phase 3 constants (`SESSIONS_JSON`, `LOG_CATEGORIES_PHASE3="widget|applescript|registry|listener"`, `JUMP_LOG_PREFIXES='\[jumped|\[jump-missed|\[jump-denied|\[jump-error'`), one smoke row `verify_3_00_01`, and placeholder comments for every downstream-plan row (3-01-01..3-09-03).
- `ClaudeAlertBotTests/Fixtures/MockTerminalJumper.swift` — test double recording `jumpCalls` and replaying a configurable `JumpResult` queue. Class body wrapped in `#if false` until 03-01 declares `TerminalJumper` / `JumpResult` / `CompletedSession`.
- `ClaudeAlertBotTests/Fixtures/HookEventFactory.swift` — added optional `termProgram: String? = nil` to both `stop` and `userPromptSubmit`; switched JSON construction to `JSONSerialization.data(withJSONObject:)` so the optional key inserts cleanly when non-nil and is omitted when nil.
- `ClaudeAlertBot.xcodeproj/project.pbxproj` — xcodegen-regenerated after adding the new fixture (4 lines added: file reference + build-file entry + group/source-build-phase membership).

## verify-phase-2.sh Lines Copied Byte-Identical

`verify-phase-2.sh` lines 1-100 (header comment block + `set -uo pipefail` + colors + constants `APP_PATH`, `SOCK`, `LOG_FILE`, `LOG_SUBSYS` + aggregation counters `PASS/FAIL/SKIP/RESULTS` + `_record_pass`, `_record_fail`, `_record_skip`, `_record_manual` + `_ensure_app_running` helper) were copied verbatim into `verify-phase-3.sh`. Phase 2's `SESSIONS_JSON` and `LOG_CATEGORIES_PHASE2` constants were re-declared (renamed to `LOG_CATEGORIES_PHASE3`, plus the new `JUMP_LOG_PREFIXES`) so the Phase 3 verifier is self-contained. `_summary` and `main` blocks follow the same structure with phase-specific row-call ordering.

## Downstream-Row Placeholder Map

Executors of plans 03-01..03-09 grep for `verify_3_NN_NN` to find their grafting anchor:

| Wave | Plan | Placeholder rows |
|------|------|------------------|
| 1 | 03-01 contracts | `verify_3_01_01`, `verify_3_01_02`, `verify_3_01_03` |
| 1 | 03-02 envelope | `verify_3_02_01`, `verify_3_02_02` |
| 2 | 03-03 listener decode | `verify_3_03_01`, `verify_3_03_02` |
| 2 | 03-04 AppleScriptHelper extension | `verify_3_04_01`, `verify_3_04_02` |
| 3 | 03-05 ITerm2Jumper | `verify_3_05_01`, `verify_3_05_02` |
| 4 | 03-06 PopoverRowView | `verify_3_06_01`, `verify_3_06_02` |
| 5 | 03-07 WidgetPopoverController | `verify_3_07_01`..`verify_3_07_04` |
| 5 | 03-08 SettingsView SET-05 | `verify_3_08_01`, `verify_3_08_02`, `verify_3_08_03` |
| 6 | 03-09 e2e | `verify_3_09_01`, `verify_3_09_02`, `verify_3_09_03` |

For each, the placeholder lives both as a comment block (declarations) and as a commented-out call inside `main()` — uncomment the call when grafting.

## Decisions Made

- **MockTerminalJumper compile-gate via `#if false`** rather than xcodegen `excludes:` — keeps `project.yml` unchanged, aligns with CLAUDE.md "no over-editing", and the gate flip in 03-01 is a 2-line removal. Same Wave-0/Wave-1 sequencing pattern Phase 2 02-00 used for `MockNotifier+NotifierProtocol.swift`.
- **HookEventFactory body switched from string template to JSONSerialization dict** — required because optional `term_program` cannot be cleanly inlined as a printf-style template branch. The wire path stays identical: a serialized JSON object passed through `JSONDecoder().decode(HookEvent.self, …)`. All 82 existing tests still pass, confirming the shape is byte-equivalent for the keys HookEvent currently decodes.
- **Verifier helper block copied verbatim** — colors, counters, `_record_*`, `_ensure_app_running`, `_summary` are byte-identical to verify-phase-2.sh. Only Phase 3 constants + smoke row + placeholder comments are net-new. Per CLAUDE.md "preserve the original code as much as possible".

## Deviations from Plan

None — plan executed exactly as written. The plan explicitly anticipated each move (compile gate, JSONSerialization dict, byte-identical helper copy, no `project.yml` edit because recursive sources path picks up the new fixture).

## Issues Encountered

None. xcodegen's pbxproj regeneration was expected and the diff (4 lines, only file/build-file/group entries for `MockTerminalJumper.swift`) was reviewed before commit.

## User Setup Required

None — purely test-target infrastructure.

## Self-Check: PASSED

- `scripts/verify-phase-3.sh` exists and is executable: FOUND
- `ClaudeAlertBotTests/Fixtures/MockTerminalJumper.swift` exists: FOUND
- `ClaudeAlertBotTests/Fixtures/HookEventFactory.swift` carries `termProgram` parameter: VERIFIED via `xcodebuild test` ** TEST SUCCEEDED ** with 82 tests
- Commit `7a6a6e9` (Task 1): FOUND in `git log`
- Commit `ede3a4a` (Task 2): FOUND in `git log`
- Commit `badb66d` (Task 3): FOUND in `git log`
- `git diff scripts/verify-phase-2.sh`: empty (verify-phase-2.sh byte-identical)
- Smoke row `verify_3_00_01` PASS: confirmed via `bash scripts/verify-phase-3.sh` — `Results: 1 pass, 0 fail`

## Next Phase Readiness

- Wave 1 plans (03-01 contracts, 03-02 envelope) can graft `verify_3_01_*` / `verify_3_02_*` directly into the placeholder slots
- 03-01 Task 1 final step removes `#if false` / `#endif` from `MockTerminalJumper.swift` and adds `: TerminalJumper` to the class declaration — a single-line edit
- 03-02 will add `term_program: String?` to `HookEvent`; the factory side is already shipping the JSON key when non-nil

---
*Phase: 03-click-to-iterm2*
*Plan: 00*
*Completed: 2026-05-08*
