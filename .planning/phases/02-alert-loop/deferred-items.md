# Phase 02 — Deferred / Out-of-Scope Findings

Items discovered during plan execution that are out of scope for the current plan and should be addressed by a future plan or verifier.

## Open

### REQ-WIDG-02-FALSE-COMPLETE (logged 2026-05-08 by 02-05)

- **What:** `.planning/REQUIREMENTS.md` has `WIDG-02` marked `[x] Complete` and the traceability table shows `Complete` — but no plan in Phase 2 has wired `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded` (those are reserved for the future NSPanel widget plan, likely 02-09).
- **Trace:** False mark introduced by commit `666c3e2 docs(02-04): complete SessionRegistry + SessionStore plan`, despite 02-04's frontmatter listing `[SESS-01, SESS-02, SESS-03, SESS-04, THR-01, THR-02, AUD-01]` (no WIDG-02). Plan 02-05's frontmatter also incorrectly listed `[WIDG-02]` — corrected to `[]` in 02-05 SUMMARY but the REQUIREMENTS.md state remained the false-complete from 02-04.
- **Why deferred (not auto-fixed in 02-05):** Reverting WIDG-02 from `[x]` to `[ ]` is touching state owned by prior plans. Per executor SCOPE BOUNDARY rules and CLAUDE.md "No Over-Editing," 02-05 declines to mutate it.
- **Action for future plan:** The plan that actually delivers `NSPanel(.nonactivatingPanel) + becomesKeyOnlyIfNeeded` (likely 02-09 widget) MUST verify the existing `[x]` mark is justified before continuing — i.e., grep-confirm the two anchors exist in production code, OR revert the mark and re-mark it as part of that plan's normal completion.
- **Action for Phase 2 verifier (02-12):** Add a row that grep-asserts:
  ```bash
  grep -E '\.nonactivatingPanel' App/*.swift && grep -E 'becomesKeyOnlyIfNeeded' App/*.swift
  ```
  PASS only if both match. This catches the false-complete at phase-gate.

## Closed

(none)
