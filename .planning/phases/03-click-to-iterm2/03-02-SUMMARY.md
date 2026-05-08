---
phase: 03-click-to-iterm2
plan: 02
subsystem: d-adapter-envelope
tags: [phase-3, wave-1, d-adapter, d3-05, envelope, schema-v1-preserved]
requires: [03-00]
provides:
  - "term_program optional field in D-08 envelope (Reporter → App decode path)"
  - "CabTest synthetic-envelope mirror of the new field for verifier-driven testing"
affects:
  - Reporter/cab-report.sh
  - App/HookEvent.swift
  - CabTest/main.swift
tech-stack:
  added: []
  patterns: ["3-site env-capture mirror in Reporter (env line + python -E injection + envelope dict key)", "Decodable Optional default-nil for forward+backward compat additive fields"]
key-files:
  created: []
  modified:
    - Reporter/cab-report.sh
    - App/HookEvent.swift
    - CabTest/main.swift
decisions:
  - "schema_version stays at 1 (D-08 + CONTEXT D-ADAPTER lock) — additive optional field is forward+backward compatible per Apple Decodable Optional semantics; no migration cost"
  - "Field placement: appended after `ts` per plan literal text, mirroring 'after the ts field' instruction. Decodable order is irrelevant for synthesized init; placement is cosmetic"
  - "Inline D3-05 reference comment retained per plan (mirrors existing per-line annotation pattern at lines 4 and 10)"
metrics:
  duration: "~6 min wall (incl. Xcode test cycle)"
  completed: 2026-05-09
  tasks: 3
  files: 3
  tests: "82/82 xcodebuild tests pass"
requirements: [JUMP-02]
---

# Phase 3 Plan 02: D-ADAPTER envelope extension (term_program) Summary

**One-liner:** D-ADAPTER `term_program` envelope field planted through all three Reporter sites (env capture → python injection → JSON key) plus HookEvent decoder + CabTest payload mirror; schema_version stays at 1 because the field is optional, all 82 Phase 1+2 tests stay green.

## What Shipped

### Site 1 — Reporter env capture (Reporter/cab-report.sh line 23)

```diff
 ITERM_SESSION_ID_VAL="${ITERM_SESSION_ID:-}"
+TERM_PROGRAM_VAL="${TERM_PROGRAM:-}"
 CLAUDE_PROJECT_DIR_VAL="${CLAUDE_PROJECT_DIR:-}"
```

Default-empty `:-` keeps HOOK-03 compliance: unset env var → empty string → `nz()` → JSON `null`.

### Site 2 — python env injection (Reporter/cab-report.sh line 37)

```diff
        ITERM="$ITERM_SESSION_ID_VAL" \
+       TERM_PROGRAM="$TERM_PROGRAM_VAL" \
        CLAUDE_DIR="$CLAUDE_PROJECT_DIR_VAL" \
```

Variable name `TERM_PROGRAM` matches the conventional shell name → python `env("TERM_PROGRAM")` lookup is self-documenting.

### Site 3 — python envelope dict (Reporter/cab-report.sh line 63)

```diff
     "iterm_session_id": nz(env("ITERM")),
+    "term_program": nz(env("TERM_PROGRAM")),
     "tty": nz(env("TTY_VAL")),
```

Reuses existing `nz()` helper (line 54). No new helper; no schema_version bump.

### HookEvent struct (App/HookEvent.swift line 19)

```diff
     let ts: String?
+    let term_program: String?              // D3-05 — $TERM_PROGRAM capture; v1 unused, v2 dispatch key (MTERM-01..04).
 }
```

One-line addition with the verbatim D3-05 comment from the plan. Auto-synthesized Decodable: missing JSON key → nil; present key → value; `null` → nil. No custom init, no custom CodingKeys.

### CabTest payload mirror (CabTest/main.swift line 25)

```diff
     "iterm_session_id": ProcessInfo.processInfo.environment["ITERM_SESSION_ID"] ?? NSNull(),
+    "term_program": ProcessInfo.processInfo.environment["TERM_PROGRAM"] ?? NSNull(),
     "tty": NSNull(),
```

Exact-shape sibling of the existing `iterm_session_id` line. Enables the 03-09 verifier to assert `term_program` presence from a synthetic envelope path (cab-test bypasses Reporter entirely).

## Verification Evidence

| # | Check | Result |
|---|-------|--------|
| 1 | `bash -n Reporter/cab-report.sh` | PASS — syntax valid |
| 2 | `grep -c TERM_PROGRAM Reporter/cab-report.sh` | 3 (env capture + python injection + envelope key — exact match to plan acceptance >= 3) |
| 3 | `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` | `** TEST SUCCEEDED **` — 82 of 82 tests pass |
| 4 | `xcodebuild build -scheme cab-test ...` | `** BUILD SUCCEEDED **` |
| 5 | `git diff App/HookEvent.swift` | exactly +1 line; no whitespace reformatting |
| 6 | `git diff CabTest/main.swift` | exactly +1 line; no surrounding code changes |
| 7 | Reporter run with `TERM_PROGRAM=iTerm.app` | log envelope shows `term_program: 'iTerm.app'`, `schema_version: 1` |
| 8 | Reporter run with TERM_PROGRAM unset (`env -i`) | log envelope shows `term_program: None` (JSON null), `schema_version: 1` |

Both Reporter runtime cases (set + unset) demonstrate D-08 schema_version=1 invariance — exactly the forward+backward compat property the plan required.

## Success Criteria — Confirmation

1. ✅ Reporter envelope, when fired with `TERM_PROGRAM=iTerm.app`, contains `"term_program": "iTerm.app"` (verified via `tail hook.log` post-run).
2. ✅ Reporter envelope, when fired without TERM_PROGRAM env, contains `"term_program": null` (verified via `env -i` run).
3. ✅ App's HookEvent decodes both forms — confirmed by 82/82 xcodebuild test pass (which includes Phase 2 fixtures decoding old envelopes that lack `term_program`).
4. ✅ CabTest binary, run with `TERM_PROGRAM` env set, would produce an envelope including the field (build green; same `ProcessInfo.environment` pattern as `iterm_session_id`).
5. ✅ All existing Phase 1+2 tests remain green: 82 tests, 0 failures.

## Schema Lock Confirmation (D-08 + CONTEXT D-ADAPTER)

- `schema_version` stays at **1** in every code path.
- Reporter line 58 unchanged: `"schema_version": 1,`
- HookEvent line 9 unchanged: `let schema_version: Int`
- CabTest line 19 unchanged: `"schema_version": 1,`
- Adding a single Optional field is the canonical Apple-blessed forward+backward-compat shape (RESEARCH Pattern 8 confirms; Apple Decodable docs treat missing keys as `nil` for `Optional` properties).

## Phase 1+2 Verifier Status

- `xcodebuild test -scheme ClaudeAlertBot`: **PASS** (82/82). This is the strongest available signal because every Phase 2 ingestion test re-decodes envelopes that DO NOT include `term_program` — backward compat is empirically proven.
- `bash scripts/verify-phase-1.sh`: deferred to integration on a built `ClaudeAlertBot.app`-from-Applications scenario; the worktree base does not stage a built `.app` for the verifier's `APP_PATH` constant, so all rows that depend on the running app would be SKIP/FAIL for unrelated reasons. Plan's authoritative gate is xcodebuild test pass + the diff-shape constraints, both met.

## Deviations from Plan

None — plan executed exactly as written.

The one micro-judgment call: the plan text under Task 2 says "Add ONE line immediately after the `ts` field" while the surrounding prose mentions "the existing per-line comment pattern (line 10 cites event ...)". The literal text wins — field appended after `ts` (the last existing field). Decodable synthesis order is irrelevant; placement is purely cosmetic. Tracked here for auditor visibility, not as a deviation.

## Threat Model — Disposition

| Threat ID | Disposition at landing | Evidence |
|-----------|------------------------|----------|
| T-IPC-01 (carry) | accept (carry-over) | Phase 1 D-09 schema_version guard + 0600 socket perms unchanged. New optional field does not alter trust surface. |
| T-ENV-01 | accept | env injection uses the same `python3 -S` + `os.environ` + `json.dumps` chain Phase 1 verified. JSON encoding escapes special chars; v1 does NOT consume the field for AppleScript or shell evaluation (CONTEXT D-ADAPTER lock). |

No new threat surface introduced beyond what the threat register already covered.

## Threat Flags

None — no new endpoints, auth paths, file accesses, or schema changes at trust boundaries beyond what was already analyzed.

## Known Stubs

None. The field is intentionally **unused** in v1 dispatch per CONTEXT D-ADAPTER lock — that is by-design future-proofing for v2 MTERM-01..04, not a stub. App-side decode IS wired (the field is now part of the HookEvent struct and visible to all downstream consumers); v1 logic simply ignores it. Documented in the inline comment ("v1 unused, v2 dispatch key").

## Commits

| Task | Commit | Subject |
|------|--------|---------|
| 1 | `d2a75e9` | feat(03-02): extend cab-report.sh with TERM_PROGRAM envelope field |
| 2 | `05659de` | feat(03-02): add term_program optional field to HookEvent |
| 3 | `1a28d22` | feat(03-02): mirror term_program in CabTest synthetic envelope payload |

## Self-Check: PASSED

- File `Reporter/cab-report.sh` — FOUND, 3 TERM_PROGRAM occurrences
- File `App/HookEvent.swift` — FOUND, 1 term_program occurrence
- File `CabTest/main.swift` — FOUND, 1 TERM_PROGRAM occurrence
- Commit `d2a75e9` — FOUND in `git log`
- Commit `05659de` — FOUND in `git log`
- Commit `1a28d22` — FOUND in `git log`
- xcodebuild test — TEST SUCCEEDED (82/82)
- xcodebuild build (cab-test) — BUILD SUCCEEDED
