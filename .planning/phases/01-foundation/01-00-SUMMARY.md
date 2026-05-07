---
phase: 01-foundation
plan: 00
subsystem: validation-harness
tags: [macos, shell, validation, wave-0, tripwire]
requires: []
provides:
  - "scripts/verify-phase-1.sh — single-shot harness for all 14 VALIDATION rows"
  - "--quick mode (post-task-commit sampling)"
  - "full mode (post-wave sampling)"
affects:
  - "Every subsequent Phase 1 plan (01-01 through 01-06) — they commit against this harness"
tech-stack:
  added:
    - "bash 3.2+ (POSIX-style structure, but #!/bin/bash for arrays)"
    - "python3 (validators: JSON parsing in 1-03-01, sub-ms timing in 1-03-03)"
  patterns:
    - "Aggregating PASS/FAIL counter with trap-based cleanup for socket / process leaks"
    - "Set -uo pipefail (no -e) so all checks run even on first failure"
key-files:
  created:
    - "scripts/verify-phase-1.sh"
  modified: []
decisions:
  - "Used `#!/bin/bash` (not `/bin/sh`) because aggregation arrays + `[[ ]]` tests + `pipefail` require bash; macOS ships bash 3.2 which supports everything used here."
  - "Sub-ms timing in 1-03-03 done via `python3 time.perf_counter()` rather than `/usr/bin/time -p` because POSIX `time` reports only 0.01s resolution which sits at the same magnitude as the 0.050s budget — too imprecise."
  - "Skipped `verify_1_06_01` from FAIL accounting and routed to a [MANUAL] result class; per the plan, manual checks must NOT increment FAIL."
  - "Restored \$SOCK via trap in both 1-03-02 (functional test) and 1-03-03 (perf test) per threat T-VRFY-01."
metrics:
  duration: "~5 minutes"
  tasks_completed: 1
  files_created: 1
  files_modified: 0
  completed: "2026-05-07"
---

# Phase 1 Plan 00: Wave 0 Validation Harness Scaffolding — Summary

**One-liner:** Single bash harness `scripts/verify-phase-1.sh` implementing 14 discrete `verify_*` checks that mirror `01-VALIDATION.md`'s Per-Task Verification Map, ready to act as the post-task / post-wave tripwire for the rest of Phase 1.

## What Shipped

`scripts/verify-phase-1.sh` (399 lines, executable) with:

1. **14 verify functions**, each callable independently and matching one row of `01-VALIDATION.md` verbatim:
   - `verify_1_00_01` — `bash scripts/build.sh && test -d "$APP_PATH"` (Wave 3 dep)
   - `verify_1_00_02` — `codesign -dv ... | grep Signature=adhoc` (Wave 3 dep)
   - `verify_1_01_01` — Xcode project + cab-test target presence (Wave 1)
   - `verify_1_01_02` — `PlistBuddy :LSUIElement` = true (Wave 1)
   - `verify_1_02_01` — running app + AF_UNIX socket (Wave 2)
   - `verify_1_02_02` — `log show --predicate subsystem==com.claudealert.bot.hook` "listener bound" (Wave 2)
   - `verify_1_03_01` — Reporter writes valid JSON envelope to hook.log (Wave 1/2)
   - `verify_1_03_02` — Reporter exits 0 with no socket (Wave 1)
   - `verify_1_03_03` — Reporter ≤ 50ms when socket missing (Wave 1)
   - `verify_1_03_04` — hook.log accumulates ≥ 1 line (Wave 1)
   - `verify_1_04_01` — `cab-test --synthetic` → OSLog `session_id` (Wave 2/3)
   - `verify_1_05_01` — second `open` of .app blocked by socket bind (Wave 2/3)
   - `verify_1_06_01` — manual visual invisibility check ([MANUAL] — does not count toward FAIL)
   - `verify_1_07_01` — self-check (this script exists & is executable)

2. **CLI modes:**
   - bare invocation → full suite (~10–20s when later waves land; currently fast because most checks short-circuit on missing files)
   - `--quick` → fast subset: `1_01_01`, `1_01_02`, `1_03_04`, `1_07_01` only
   - `--help` / `-h` → usage text

3. **Constants block** (overridable via env): `APP_PATH`, `SOCK`, `LOG_FILE`, `LOG_SUBSYS` — pinned to D-07 (`com.claudealert.bot.hook`) and D-10 (`~/Library/Application Support/ClaudeAlertBot/sock`).

4. **Aggregation:** PASS/FAIL/SKIP counters + RESULTS array; final exit code is `1` iff `FAIL > 0`.

5. **Threat mitigations** (per plan's `<threat_model>`):
   - **T-VRFY-01** — `1_03_02` and `1_03_03` rename the user's real socket to `$SOCK.bak` before the test and restore it via `trap … EXIT INT TERM` so a Ctrl-C mid-run cannot orphan the socket.
   - **T-VRFY-02** — `1_05_01` wraps the double-`open` test with a trap that pgreps and kills any stray `ClaudeAlertBot` processes on exit, preventing a failed run from leaving a live app.

## Wired Validation Rows

All 14 rows from `01-VALIDATION.md`'s Per-Task Verification Map are wired. The harness can be run **today** even though most checks will fail — that is the intended Wave 0 state.

## Currently Green vs. Currently Red

| Row | Status | Reason |
|-----|--------|--------|
| 1-07-01 | ✅ PASS | This plan is the deliverable. |
| 1-01-01 | ❌ FAIL | Wave 1 — Plan 01 ships the `.xcodeproj`. |
| 1-01-02 | ❌ FAIL | Wave 1 — Plan 01 ships `App/Info.plist`. |
| 1-02-01 | ❌ FAIL | Wave 2 — Plan 03 ships the listener. |
| 1-02-02 | ❌ FAIL | Wave 2 — Plan 03 ships OSLog logging. |
| 1-03-01..04 | ❌ FAIL | Wave 1 — Plan 02 ships `Reporter/cab-report.sh` + hook.log writes. |
| 1-04-01 | ❌ FAIL | Wave 2/3 — Plan 03 ships `cab-test`; Plan 05 builds it. |
| 1-05-01 | ❌ FAIL | Wave 2/3 — Plan 03 ships the single-instance lock; Plan 05 builds the .app. |
| 1-06-01 | 🟡 MANUAL | Wave 3 — Plan 06's manual checkpoint covers visual invisibility. |
| 1-00-01 | ❌ FAIL | Wave 3 — Plan 05 ships `scripts/build.sh`. |
| 1-00-02 | ❌ FAIL | Wave 3 — Plan 05 invokes `codesign --force --sign -`. |

## What Depends On This Harness

Every subsequent plan in Phase 1 commits against this harness:

- **Wave 1** (Plans 01, 02): after each task commit, `bash scripts/verify-phase-1.sh --quick` should show the corresponding row flipping from FAIL to PASS.
- **Wave 2** (Plans 03, 04): after each plan completes, the full suite should show 1-02-* and 1-03-* and 1-04-01 going green.
- **Wave 3** (Plans 05, 06): the full suite — including 1-00-01, 1-00-02, 1-05-01, and the [MANUAL] 1-06-01 acknowledgement — gates Phase 1 sign-off in `01-VERIFICATION.md`.

## Verification Run

```
$ bash scripts/verify-phase-1.sh --quick; echo "exit=$?"
Phase 1 validation harness — mode=quick
APP_PATH=build/export/ClaudeAlertBot.app
SOCK=/Users/choijihye/Library/Application Support/ClaudeAlertBot/sock
LOG_FILE=/Users/choijihye/Library/Logs/ClaudeAlertBot/hook.log

[FAIL] 1-01-01: Xcode project skeleton + two targets — …missing
[FAIL] 1-01-02: LSUIElement=true in App/Info.plist — App/Info.plist missing
[FAIL] 1-03-04: hook.log accumulates entries — …missing
[PASS] 1-07-01: verify-phase-1.sh exists & exits 0

Results: 1 pass, 3 fail
exit=1
```

This output is the **expected Wave 0 baseline**. The 1 PASS / 3 FAIL ratio is the starting point against which Wave 1 progress will be measured.

## Acceptance Criteria — All Met

- [x] `test -f scripts/verify-phase-1.sh`
- [x] `test -x scripts/verify-phase-1.sh`
- [x] `bash -n scripts/verify-phase-1.sh` exits 0
- [x] `grep -cE '^verify_1_(0[0-7])_(0[1-9])\(\)' …` returns 14 (≥ 14)
- [x] `APP_PATH`, `SOCK`, `LOG_FILE`, `LOG_SUBSYS` all defined (4 = ≥ 4)
- [x] `--quick` supported
- [x] `bash scripts/verify-phase-1.sh --quick` produces a `Results:` line and exits 1 (no crash)

## Deviations from Plan

None — plan executed exactly as written.

The plan called out one optional implementation choice ("`/usr/bin/time -p` or `date +%s%N` deltas" for the 50ms timing in 1-03-03). I picked a third option — `python3 time.perf_counter()` — because:

- POSIX `time -p` reports 0.01s resolution; the budget is 0.05s, so granularity is too coarse.
- macOS bash 3.2's `date +%s%N` is not portable (`%N` is GNU-only); BSD `date` returns literal `N`.
- python3 is already a dependency for 1-03-01 (JSON parse), so no new tooling is added.

This is an implementation detail within the plan's stated freedom, not a deviation from the contract.

## Authentication Gates

None encountered — this plan is pure local file authoring.

## Self-Check

Verifying the deliverables:

- `scripts/verify-phase-1.sh` exists: FOUND
- Commit `8c93620` exists: FOUND (verified via `git log`)

## Self-Check: PASSED
