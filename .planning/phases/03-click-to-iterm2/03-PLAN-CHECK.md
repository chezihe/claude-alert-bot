---
phase: 3
status: issues_found
blockers: 3
warnings: 4
info: 3
reviewed: 2026-05-08
verifier: gsd-plan-checker (Claude Opus 4.7)
---

# Phase 3 Plan-Check — Click-to-iTerm2

Goal-backward verification of the 10-plan, 7-wave Phase 3 plan set against ROADMAP §"Phase 3" goal, 5 active Success Criteria (SC#6 deferred to v2), 8 requirements (JUMP-01..05, SET-05, ONB-02, ONB-03), and 21 locked decisions (D-ADAPTER + D3-01..20).

## Verdict Summary

| # | Dimension | Verdict | Notes |
|---|-----------|---------|-------|
| 1  | Goal coverage (UUID jump + friendly miss + permission recovery) | **PASS** | Each goal segment maps to specific plans; D-ADAPTER seam complete. |
| 2  | Active SC coverage (SC#1..5; SC#6 struck) | **PASS** | All 5 SCs mapped to verifier rows or 03-09 manual checkpoint; SC#6 correctly absent. |
| 3  | Requirements coverage (JUMP-01..05, SET-05, ONB-02, ONB-03) | **PASS** | 8/8 mapped; ONB-02 inherited from Phase 2 PermissionDeepLink/banner; ONB-03 wired in 03-07 + 03-08. |
| 4  | Decision coverage (D-ADAPTER + D3-01..20) | **PASS** | 21/21 traced to plan tasks; D3-08 correctly noted "deferred to Phase 6 README CREDIT" — no v1 implementation, matches CONTEXT. |
| 5  | Cross-cutting invariants (T-INJECTION-01, T-COPY-DRIFT-01, Pitfall #1, Pitfall #11, D3-13, D2-29, D2-08 sig) | **PASS** | All 7 invariants threaded; comment-stripped grep form is consistent across done-checks, threat models, and verifier row. |
| 6  | Wave dependency soundness (DAG matches PLAN-INDEX claim) | **PASS** | DAG matches; no same-wave file conflicts (Wave 1 03-01 ‖ 03-02 disjoint; Wave 2 03-03 ‖ 03-04 disjoint; Wave 5 03-07 ‖ 03-08 disjoint). |
| 7  | TDD RED/GREEN discipline (Phase 2 inheritance) | **GAP**  | Phase 2 had `test(02-XX) RED` + `feat(02-XX) GREEN` commit pairs for every plan that ships Swift. Phase 3 plans bury tests in the LAST task of each plan with no commit-split callout, no TDD frontmatter tag, and no exception carve-out. **WARNING** — see W1. |
| 8  | Scope creep / boundary | **PASS** | TokenEater (D3-08), TTY fallback, MTERM-01..04, counter badge, hook installer, .dmg all explicitly deferred. No plan smuggles. |
| 9  | Phase 2 D3-04 silent-failure regression seal | **FAIL** | CONTEXT D3-04 demands a regression test in `AppleScriptHelperTests` covering raw `wXtYpZ:UUID-XX` → `frontmostMatches` UUID-only comparison. Plans **do not deliver this test**. **BLOCKER** — see B2. |
| 10 | Verifier coverage (03-09: 22 rows + Phase 1+2 chain) | **GAP**  | All Phase 3 rows present + manual checkpoint covers SC#1..5; **but** `verify_3_09_02` Phase 2 chain tolerance is mathematically wrong post-Phase-3. **BLOCKER** — see B3. |
| 11 | Research resolution (RESEARCH §Open Questions) | **GAP**  | Section heading lacks `(RESOLVED)` suffix; Q3/Q4/Q5 are tagged `open` (Q3 implicitly resolved by 03-06; Q5's "권고: 1회 latency 측정" is not picked up by 03-09 manual checkpoint). **WARNING** — see W2. |
| 12 | Pattern compliance (12/12 PATTERNS.md analogs) | **PASS** | Every plan that creates a new file cites its analog (NotificationOrchestrator → ITerm2Jumper, ProjectName → iTermSessionID, MockNotifier → MockTerminalJumper, etc.). |
| 13 | Architectural tier compliance (RESEARCH responsibility map) | **PASS** | UUID normalization in Domain (`iTermSessionID`), AppleScript I/O in actor, UI state in SwiftUI views, Reporter envelope in shell — every capability matches the assigned tier. |
| 14 | CLAUDE.md compliance (no over-editing, preserve original) | **PASS** | Plans repeatedly cite "minimum modification" + "preserve original code", default-arg parameters keep Phase 2 call sites working, dead-code removal scoped to symbols on a removal path. One trade-off (closure-literal duplication in 03-07 reloadPopoverContent) explicitly documented. |

**Final verdict:** **issues_found** — 3 blockers + 4 warnings before execution starts. Two of the blockers are single-line edits to plan-files; one (B1) requires a planning decision before execution can proceed under the same TDD discipline Phase 2 established.

---

## Blockers

### B1: TDD RED/GREEN commit discipline absent across Phase 3 plans

**Plans affected:** 03-01, 03-03, 03-04, 03-05, 03-06, 03-08 (every plan that ships Swift + tests)
**Severity:** **BLOCKER** (escalatable to WARNING if user explicitly reclassifies — see fix path).

**Evidence:** Phase 2 git log shows verbatim TDD discipline:
```
40aa803 test(02-10): add failing SettingsView copy + corner-label tests (TDD RED)
f44a27b feat(02-10): SettingsView Form + D2-35 Path A trigger + Test button (SET-01..04)
af40594 test(02-06): add failing NotificationOrchestratorTests (TDD RED)
4bf184d feat(02-06): NotificationOrchestrator @MainActor — NotifierProtocol impl
26c735f test(02-05): add failing AppleScriptHelperTests (TDD RED)
09863e0 feat(02-05): AppleScriptHelper actor — compile-once, 1s timeout, error classification, state mirror
```
Every Phase 2 plan that landed Swift code split into two commits: the failing test first, then the implementation that turned it green.

Phase 3 plans place tests as the **final task** of each plan (03-01 Task 3, 03-03 Task 3, 03-04 Task 3, 03-05 Task 2, 03-06 Task 3, 03-08 Task 3). No plan declares a TDD-RED carve-out task. No frontmatter `tdd_split: true` tag. No `<commit-split>` block. The natural execution path is "land impl, then write tests retroactively" — the inverse of Phase 2's RED→GREEN discipline.

This is verifiable from your Phase 2 commit history; the plan set does not match the established phase pattern.

**Recommended fix (cheaper of two):**
1. Add a one-line note to each plan's frontmatter or `<execution_context>` instructing the executor: *"This plan ships in two commits per task: `test(03-NN): ... (TDD RED)` first, then `feat(03-NN): ... (TDD GREEN)`. Mirror Phase 2 02-NN discipline (see git log)."*
2. OR — explicitly reclassify Phase 3 to "tests-after-impl is acceptable for this phase" and remove the implicit Phase 2 TDD invariant. This is a planning-time decision that should be surfaced to the user, not silently dropped.

**If user reclassifies to (2),** this finding downgrades to WARNING and execution can proceed.

---

### B2: D3-04 regression test (raw envelope → `frontmostMatches` UUID-only) not delivered

**Plans affected:** 03-03, 03-04, 03-05
**Severity:** **BLOCKER** (CONTEXT D3-04 verbatim violation; the plan-index claims D3-04 is "full" coverage but no plan delivers the actual regression test).

**Evidence:**

CONTEXT.md D3-04 (line 44): *"`AppleScriptHelperTests`에 raw `w0t0p1:UUID-XX` 입력 → `frontmostMatches` 호출 시 UUID만 비교 검증 회귀 가드 추가."* (Add regression guard in `AppleScriptHelperTests` that takes raw `w0t0p1:UUID-XX` input and verifies `frontmostMatches` does UUID-only comparison.)

PLAN-INDEX line 57: *"D3-04 (Phase 2 silent-failure auto-fix + regression guard) | 03-03 (apply), 03-04 (regression test in `AppleScriptHelperTests`) | full"* — claims the regression test lives in 03-04.

**Actual state:**
- **03-03 Task 3 (lines 324-336):** lists the test as "Optional bonus (CONTEXT D3-04 regression guard)" with explicit punt language: *"If running the test requires live AppleScript (not unit-friendly), skip this bonus — the integration test in 03-09 will cover it via end-to-end log inspection."* The test body is a `// ...` stub.
- **03-03 threat model (line 359):** claims *"Regression test in 03-04 (AppleScriptHelperTests) seals the contract"* — but 03-04 Task 3's test list (lines 337-401) contains `test_runJumpByUUID_rejectsNonUUIDInput`, `test_runJumpByUUID_rejectsAppleScriptInjectionAttempt`, `test_jumpByUUIDTemplate_containsAppleScriptTimeout`, `test_focusFrontmostSource_containsAppleScriptTimeout`, `test_testConnection_deniedShortCircuits` — **none of which exercise `frontmostMatches` with a raw envelope-form input**. The test that CONTEXT D3-04 names is not in 03-04's plan body.
- **03-05 Task 2 (lines 237-263) `test_jump_envelopeFormatItermID_isStrippedAndValidated`:** asserts that when the helper short-circuits via `markDeniedForTesting`, the result is `.permissionDenied` rather than `.otherError(0)` (whitelist-rejection path). This proves *isValid did not reject the stripped UUID* — it does **not** prove that the AppleScript-comparison received UUID-only input. The actual UUID-only-comparison contract (CONTEXT D3-04 verbatim) is never asserted by any unit test in the plan set.

The 03-09 manual checkpoint (SC#1) covers "click → exact tab" end-to-end, but that's a behavior assertion, not the `frontmostMatches` UUID-only contract assertion CONTEXT D3-04 calls out by name.

**Recommended fix:** Move the `test_frontmostMatches_silentFailureFixed_whenItermIDIsEnvelopeFormat` test from 03-03 Task 3 "Optional bonus" stub to a concrete task in 03-04 (where AppleScriptHelperTests is already being extended). The test should:
1. Seed `markGrantedForTesting` so the cheap-query path is exercisable.
2. Skip if `iTerm2.app` is not running (use `XCTSkipIf` — Phase 2 pattern).
3. Otherwise call `frontmostMatches(itermSessionID: "<uuid-only>")` directly and assert the comparison is UUID-only (not envelope-format).

Alternative if the live-AppleScript dependency is too brittle: add a Swift-side comparison test that exercises the closure body in `HookListener.suppressIfFrontmost` with both forms of input through a test seam — but this requires a refactor 03-03 explicitly avoided. The first option is cleaner.

---

### B3: `verify_3_09_02` Phase 2 regression-chain tolerance off by one — V-7 (`2-11-02`) ignored

**Plan affected:** 03-09 (Task 1, `verify_3_09_02` function body)
**Severity:** **BLOCKER** (the row will fail incorrectly the first time it runs post-Phase-3, gating phase-3 sign-off).

**Evidence:**

`02-VERIFICATION.md` line 23, 286 confirms Phase 2 ships **with one persistent FAIL row already on disk**: row `2-11-02` (V-7 carry-over, cab-test UUID-per-invocation tooling artifact, `Phase 3+ verifier-tooling polish`). 02-VERIFICATION.md line 233 + line 258 explicitly defer V-7 to "Phase 3+ verifier-tooling polish" — meaning Phase 3 ships without fixing it.

After Phase 3 plan 03-07 lands, row `2-08-01` (which currently PASSes per 02-VERIFICATION.md line 42) will flip to FAIL because `[would-jump]` literal is removed. So `verify-phase-2.sh` will report **2 FAILs**: `2-08-01` (D3-13 contract change) AND `2-11-02` (V-7 carry-over).

03-09 Task 1, `verify_3_09_02` body (line 261-272):
```bash
if grep -q 'FAIL.*2-08-01' /tmp/cab-3-09-02.log && \
   [[ "$(grep -c FAIL /tmp/cab-3-09-02.log)" == "1" ]]; then
    _record_pass ...
```

The `grep -c FAIL == 1` gate will **never fire** because Phase 2 already produces 2 FAILs post-Phase-3. The row records FAIL → row 3-09-02 fails → manual checkpoint resolution is gated by an arithmetic error in the verifier.

**Recommended fix (replace the count-based gate with an explicit allow-list):**
```bash
verify_3_09_02() {
    local id="3-09-02" name="Phase 2 regression chain (2-08-01 + 2-11-02 expected-red)"
    bash scripts/verify-phase-2.sh > /tmp/cab-3-09-02.log 2>&1 || true
    local failed_rows
    failed_rows=$(grep -E '^FAIL ' /tmp/cab-3-09-02.log | awk '{print $2}' | sort -u)
    local expected_failures="2-08-01 2-11-02"
    local unexpected=""
    for row in $failed_rows; do
        case " $expected_failures " in
            *" $row "*) : ;;
            *) unexpected="$unexpected $row" ;;
        esac
    done
    if [[ -z "$unexpected" ]]; then
        _record_pass "$id" "$name (allowed reds: $expected_failures)"
    else
        _record_fail "$id" "$name" "unexpected Phase 2 reds:$unexpected"
    fi
}
```
Adjust regex to match the actual `_record_fail` output format used in `verify-phase-2.sh`.

Also update the comment annotation in `verify-phase-2.sh` (Task 2) to mention BOTH rows (`2-08-01` D3-13-contract-change AND `2-11-02` V-7 tooling artifact) — currently the annotation only mentions `2-08-01`.

Also update `03-VERIFICATION.md` Task 4's regression chain table:
```
| Phase 2 | All except 2-08-01 AND 2-11-02 | green (carry-over) | 2-08-01 superseded by D3-13; 2-11-02 = V-7 carry-over (cab-test argv polish, deferred Phase 3+ per 02-VERIFICATION.md) |
```

---

## Warnings

### W1: D3-01 "한 곳" (one place) deviation — normalization happens at TWO write sites

**Plans affected:** 03-03 (Task 1)
**CONTEXT reference:** D3-01 line 41: *"적용 지점 = `HookListener` decode 직후 또는 `SessionRegistry.ingest` 진입 전 한 곳."* (apply at HookListener post-decode OR SessionRegistry pre-ingest — **one** place).

03-03 Task 1 normalizes in **both** runtime paths (HookListener.suppressIfFrontmost closure AND SessionRegistry.handleStop CompletedSession init) plus SessionStore.load() migration. The plan explicitly acknowledges this: *"Two edits, both single-line additions...iTermSessionID.uuid(fromRaw:) is idempotent so applying it in both places is safe."*

The justification (`HookEvent` fields are `let`, refactor cost > duplication) is reasonable. But CONTEXT says "한 곳" verbatim. This is a context-compliance soft-violation that the user should ratify rather than have the planner unilaterally widen the surface.

**Recommendation:** Surface this to the user before execution. Either (a) accept the two-point design and update CONTEXT D3-01 to "one logical normalization, applied idempotently at all write sites"; or (b) refactor to single-point (mutate-event wrapper struct, or normalize at HookListener.handle's local before constructing the closure + passing through to ingest via a new param). Option (a) is the cheaper choice given CLAUDE.md "minimum modification" preference.

### W2: RESEARCH §Open Questions section not marked `(RESOLVED)`; Q5 latency probe not captured by manual checkpoint

**Plans affected:** RESEARCH.md (heading at line 994) + 03-09 (manual checkpoint procedure)

RESEARCH §Open Questions has 5 questions. Q1, Q2 are tagged `(resolved)` inline. Q3, Q4, Q5 are tagged `open`. Specifically:
- **Q3:** `withAnimation completion` vs `DispatchQueue.main.asyncAfter` — implicitly resolved by 03-06 Task 1 (uses `withAnimation(_:completion:)` API as primary, `DispatchQueue.main.asyncAfter` for inter-phase chaining). RESEARCH did not mark resolved.
- **Q4:** `lastConnectionTestAt` format `HH:mm` vs relative — RESEARCH says "CONTEXT D3-19 ... 잠금. 변경 X." — actually IS resolved.
- **Q5:** *"verify-phase manual checkpoint에 latency 측정 (Pattern 10) 포함할 것인지? — 권고: 1회 측정 포함"* — RESEARCH recommends including ONE latency measurement in the manual checkpoint. **03-09 Task 3 (manual checkpoint) does not include this step.** SC#5 manual procedure says "Bonus check: `grep 'with timeout of 3 seconds' ...`" and "✅ PASS if the UI stayed interactive throughout" — no latency measurement.

Per Dimension 11 strict reading, an `## Open Questions` section without `(RESOLVED)` suffix is a planner pre-flight gate failure. Pragmatic reading: 4/5 are answered; only Q5's manual-checkpoint-latency step is genuinely missing.

**Recommendation:**
1. Update `03-RESEARCH.md` line 994 heading to `## Open Questions (RESOLVED)` and inline-mark Q3/Q5 with their resolutions (`Q5 — RESOLVED: deferred from 03-09 manual checkpoint per planner discretion; latency probe is Phase 6 polish if performance regression is observed.`).
2. OR — add a one-liner step to 03-09 SC#5 manual checkpoint: *"Bonus latency measurement: `time osascript -e 'tell application \"iTerm2\" to id of current session of current tab of current window'` — confirm well under 3000ms (target ≤200ms per Pattern 10)."*

### W3: 03-06 Task 3 `PopoverRowStateTests` use source-file string greps as test assertions

**Plans affected:** 03-06 (Task 3)

Tests `test_clickHandler_isNoOpInJumpingState` and `test_missingAnimation_callsOnMissingCompleteCallback` open `App/PopoverRowView.swift` as a string and grep for literal substrings (`guard state == .normal else { return }`, `onMissingComplete()`). Brittle to whitespace, comments, refactors. Plan acknowledges trade-off: *"The "read source file" approach is unusual but defensible — it's a documentation-test pattern...Future plans can replace these with proper UI tests when a UI test target lands."*

**Recommendation:** Acceptable as v1 stopgap given D2-29 (zero external deps; ViewInspector adds a SwiftPM dep). Document the brittleness in 03-06-SUMMARY so a future PopoverRowView refactor knows to update the literal greps. No fix required pre-execution — this is a calibrated trade-off.

### W4: 03-06 Task 2 dead-test removal is open-ended ("if PopoverContentTests has tests, delete them too")

**Plans affected:** 03-06 (Task 2)

The plan instructs: *"If `PopoverContentTests.swift` has tests for these (Phase 2 may have asserted the literal "Session unavailable" string), DELETE those test cases too."* No enumerated list of test names; no Read-first-then-decide instruction. The executor must inspect and judge.

**Recommendation:** Have the planner enumerate the candidate tests now (Read `PopoverContentTests.swift` and list `test_*` names that reference `unavailableLabelText` or `isUnavailable`), or explicitly instruct *"if zero matches found, no deletion needed; proceed."* Cheap pre-execution polish.

---

## Info / Suggestions (non-blocking)

### I1: `verify_3_01_02` JumpResult case-counter regex
03-09 Task 1: `grep -cE '^\s+case [a-zA-Z]' App/TerminalJumper.swift`. Safe today because TerminalJumper.swift contains no `switch` statement (only the `JumpResult` enum + `TerminalJumper` protocol). If a future refactor adds a `switch result` inside this file, the count will inflate. Lock note in 03-09-SUMMARY recommended.

### I2: 03-07 reloadPopoverContent closure-literal duplication
The trade-off ("DRY violation tolerated to keep capture semantics simple") is documented in the plan body. Acceptable. If a future refactor extracts a helper, the verifier row `verify_3_07_01` (`grep -c 'jumper.jump'`) returning ≥1 will still hold; no follow-up needed.

### I3: 03-09 manual checkpoint SC#3 — `tccutil reset AppleEvents com.claudealert.bot` requires the actual bundle ID
The instruction says `com.claudealert.bot` — confirm this matches the bundle ID in `Info.plist` (Phase 1 D-08 / Phase 2 D2-33 reference uses `com.claudealert.bot.hook` as the OSLog subsystem; the bundle ID may differ). One-line lookup pre-execution.

---

## Recommended actions before execution

In priority order:

1. **B3 — fix `verify_3_09_02` allow-list** (single-edit to 03-09 Task 1; ~10 lines). Without this, the verifier row fails as soon as it runs.
2. **B2 — relocate D3-04 regression test** (move from 03-03 Task 3 "Optional bonus" stub to a concrete task in 03-04 Task 3 or to its own task in 03-04). One-task addition.
3. **B1 — TDD RED/GREEN ratification**: surface to user — accept Phase 2 inheritance (add per-plan TDD-split note) OR explicitly waive (note "tests-after-impl acceptable for Phase 3" in CONTEXT). Either is a one-line edit.
4. **W1 — D3-01 "한 곳" ratification**: update CONTEXT D3-01 to "applied idempotently at all write sites" OR refactor 03-03 to single-point. User decision.
5. **W2 — Open Questions resolution**: update RESEARCH.md heading to `(RESOLVED)` and mark Q3/Q5 inline. Optionally add latency probe step to 03-09 SC#5 manual.
6. **W4 — enumerate dead-test deletion list** in 03-06 Task 2 for executor clarity.

After steps 1-3, re-verify and Phase 3 is execution-ready.

---

## Coverage Audit (PASS dimensions, condensed)

### Active Success Criteria → verifier rows

| SC | Description | Plans | Verifier row(s) | Manual checkpoint? |
|----|-------------|-------|-----------------|---------------------|
| SC#1 | 3 sessions / 3 tabs / click → exact tab | 03-04, 03-05, 03-07 | 3-04-01, 3-05-02, 3-07-01 | yes (03-09 Task 3) |
| SC#2 | Closed tab → friendly missing UX, queue clears | 03-06, 03-07 | 3-06-01, 3-07-01, 3-07-02 | yes |
| SC#3 | SET-05 1st press TCC, subsequent focus | 03-04, 03-08 | 3-04-02, 3-08-01, 3-08-02 | yes |
| SC#4 | Denied → recovery deep-link | 03-07, 03-08 | 3-07-03, 3-08-02 | yes |
| SC#5 | 3s timeout, no beachball | 03-04, 03-06, 03-07 | 3-04-01, 3-05-01 (Pitfall #1) | yes (no latency probe — see W2) |

### Requirements → plans

| REQ | Plans | Coverage |
|-----|-------|----------|
| JUMP-01 | 03-05, 03-07 | full |
| JUMP-02 | 03-01, 03-03, 03-04, 03-05, 03-06, 03-07 | full |
| JUMP-03 | 03-04 | full (compile-once + serial queue) |
| JUMP-04 | 03-04 | full (`with timeout of 3 seconds` × 2) |
| JUMP-05 | 03-06, 03-07 | full (row-state self-debounce + jumping-state guard) |
| SET-05 | 03-04, 03-08 | full |
| ONB-02 | 03-08 (inheritance from Phase 2 PermissionDeepLink/triggerPermissionPrompt) | inherited |
| ONB-03 | 03-07, 03-08 | full (denied path → openAutomationPreferences) |

### Decisions → plans (D-ADAPTER + D3-01..20)

All 21 decisions verified covered per PLAN-INDEX §"Decision → Plan Coverage Audit"; D3-08 correctly deferred to Phase 6 README CREDIT (out-of-scope marker in 03-VERIFICATION.md is the planned execution surface).

### Cross-cutting invariants

| Invariant | Plan(s) | Verifier row | Status |
|-----------|---------|---------------|--------|
| T-INJECTION-01 (Option C: per-call substitution + isValid whitelist) | 03-01, 03-04 | 3-04-02 (whitelist test) | PASS |
| T-COPY-DRIFT-01 (5 SET-05 verbatim asserts) | 03-08 | 3-08-01 | PASS |
| Pitfall #1 (NSApp.activate forbidden, comment-stripped grep) | 03-05, 03-09 | 3-05-01 | PASS |
| Pitfall #11 (AppDelegate boot order; ITerm2Jumper retained via WPC init) | 03-07 | source review | PASS |
| D3-13 OSLog 4-prefix contract | 03-05, 03-07 | 3-07-02 | PASS |
| D2-29 zero external deps | all plans | implicit | PASS |
| D2-08 onRowClick(sessionID:) signature preserved | 03-07 | source review | PASS |

### Wave dependency DAG (verbatim from frontmatter)

```
Wave 0: 03-00 (depends_on: [])
Wave 1: 03-01 (depends_on: [03-00])  ‖  03-02 (depends_on: [03-00])
Wave 2: 03-03 (depends_on: [03-01])  ‖  03-04 (depends_on: [03-01])
Wave 3: 03-05 (depends_on: [03-01, 03-04])
Wave 4: 03-06 (depends_on: [03-01])
Wave 5: 03-07 (depends_on: [03-05, 03-06])  ‖  03-08 (depends_on: [03-04])
Wave 6: 03-09 (depends_on: [03-00, 03-01, 03-02, 03-03, 03-04, 03-05, 03-06, 03-07, 03-08])
```

Same-wave file-conflict check: Wave 1 03-01 (App/TerminalJumper.swift, App/iTermSessionID.swift, MockTerminalJumper.swift) ‖ 03-02 (Reporter/cab-report.sh, App/HookEvent.swift, CabTest/main.swift) — disjoint. Wave 2 03-03 (App/HookListener.swift, App/SessionRegistry.swift, App/SessionStore.swift) ‖ 03-04 (App/AppleScriptHelper.swift, AppleScriptHelperTests.swift) — disjoint. Wave 5 03-07 (WidgetPopoverController.swift, AppDelegate.swift) ‖ 03-08 (SettingsStore.swift, SettingsView.swift, SettingsViewTests.swift) — disjoint. PASS.

Forward references: none. Cycles: none. Wave numbers consistent with `max(deps) + 1`. PASS.

### Scope sanity

| Plan | Tasks | Files modified | Wave-budget verdict |
|------|-------|----------------|---------------------|
| 03-00 | 3 | 4 | within budget |
| 03-01 | 3 | 4 | within budget |
| 03-02 | 3 | 3 | within budget |
| 03-03 | 3 | 4 | within budget |
| 03-04 | 3 | 2 | within budget (large file additions but single-file scope) |
| 03-05 | 2 | 2 | within budget |
| 03-06 | 3 | 3 | within budget |
| 03-07 | 2 | 2 | within budget |
| 03-08 | 3 | 3 | within budget |
| 03-09 | 4 (3 auto + 1 checkpoint) | 3 | within budget (final integration plan justifiably wider) |

No plan exceeds the 4-task warning threshold. No plan exceeds the 10-file warning threshold. PASS.

---

## Final verdict

**Status: issues_found** — return to planner with B1, B2, B3 addressed (and W1, W2, W4 batched in the same revision pass for efficiency). Estimated revision cost: ~15 minutes — three localized plan edits (03-03 Task 3, 03-09 Task 1) plus a planning-decision callout (B1) that the user resolves in one line. After revision, the plan set is execution-ready against the Phase 3 goal.

Pending blockers fix, the plan structure itself is sound: Wave DAG is correct, cross-cutting invariants are threaded consistently, decision/requirement/SC coverage is complete, and the architectural seam (D-ADAPTER) is properly isolated in 03-01 + 03-05 with v2 readiness preserved.

---

*Phase 3 plan-check artifact*
*Reviewer: gsd-plan-checker (Claude Opus 4.7, 1M context)*
*Cap: 1 of 3 revision iterations*
