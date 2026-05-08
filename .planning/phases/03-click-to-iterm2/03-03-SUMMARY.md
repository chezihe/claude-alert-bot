---
phase: 03-click-to-iterm2
plan: 03
subsystem: ipc-normalization
tags: [phase-3, wave-2, d3-01, d3-02, d3-03, d3-04, normalization]
requires:
  - 03-01 (iTermSessionID.uuid + isValid)
provides:
  - HookListener.suppressIfFrontmost normalization
  - SessionRegistry.handleStop UUID-only write contract
  - SessionStore.load() in-memory migration of legacy ':'-prefixed iterm_session_id
affects:
  - any downstream consumer of CompletedSession.itermSessionID (03-04 jump-by-uuid script, 03-05 ITerm2Jumper)
tech-stack:
  added: []
  patterns:
    - "Idempotent in-memory migration at load (no schema bump)"
    - "Two-point normalization: input boundary (suppress closure) + persistence write site"
key-files:
  created: []
  modified:
    - App/HookListener.swift
    - App/SessionRegistry.swift
    - App/SessionStore.swift
    - ClaudeAlertBotTests/SessionStoreTests.swift
decisions:
  - "Two-point normalization (HookListener suppress closure + SessionRegistry write site) instead of HookEvent mutation — HookEvent fields are `let`, restructuring would touch many call sites; iTermSessionID.uuid is idempotent so applying twice is safe."
  - "SessionStore.load() migration is in-memory only; next save() cycle persists normalized form via existing atomic write path. No schema bump."
  - "Round-trip test fixture updated (Rule 1): the envelope-format strings `w0t0p1:UUID` / `w0t1p0:OTHER` modeled exactly the legacy shape D3-03 strips, so equality assertions would break post-migration. Replaced with colon-free strings that pass through migrateItermIDs untouched."
metrics:
  duration_minutes: 5
  completed: 2026-05-08T15:13:58Z
  tasks_total: 3
  tasks_completed: 3
  tests_added: 3
  total_tests_passing: 93
---

# Phase 3 Plan 03: UUID Normalization at HookListener / SessionStore.load Summary

**One-liner:** Wires `iTermSessionID.uuid(fromRaw:)` (from 03-01) into the two ingestion points where `wXtYpZ:UUID` envelope values can enter the App's domain — HookListener pre-suppress closure + SessionRegistry persistence write site — and adds an idempotent in-memory migration at `SessionStore.load()` that strips the prefix from any legacy `sessions.json` records on disk.

## What Changed

### Task 1 — Two-point UUID normalization (HookListener + SessionRegistry)
- **`App/HookListener.swift`** (one-line replacement, lines 114-117): the `suppressIfFrontmost` closure now normalizes via `iTermSessionID.uuid(fromRaw: iTermID)` BEFORE handing the value to `AppleScriptHelper.shared.frontmostMatches`. Closes the Phase 2 D2-14/D2-15 silent-failure where the envelope was `wXtYpZ:UUID` but AppleScript's `id of session` returns UUID-only — comparison was always false.
- **`App/SessionRegistry.swift`** (one-line field-init change at handleStop line 120): `CompletedSession(... itermSessionID: iTermSessionID.uuid(fromRaw: event.iterm_session_id), ...)`. Persistence write site is now UUID-only — every record written post-Phase-3 is normalized, so SessionStore migration only needs to handle pre-Phase-3 disk state.
- **Why two edits, not one centralized one (per plan-time decision):** `HookEvent` fields are `let` (immutable Decodable). Wrapping in a normalized-event struct would touch many call sites; adding `itermSessionIDOverride: String?` to `ingest()` would expand its surface beyond what the plan authorizes. The two locks (suppress closure + write site) are each a one-line change and `iTermSessionID.uuid` is idempotent, so applying twice is harmless.

### Task 2 — `SessionStore.load()` in-memory migration (D3-03)
- **`App/SessionStore.swift`** — added private static helper `migrateItermIDs(in:)`:

  ```swift
  private static func migrateItermIDs(in snap: SessionsSnapshot) -> (SessionsSnapshot, migrated: Int) {
      var migrationCount = 0
      let newCompleted = snap.completed.map { c -> CompletedSession in
          guard let raw = c.itermSessionID, raw.contains(":") else { return c }
          guard let stripped = iTermSessionID.uuid(fromRaw: raw), stripped != raw else { return c }
          migrationCount += 1
          return CompletedSession(
              sessionID: c.sessionID,
              projectName: c.projectName,
              stoppedAt: c.stoppedAt,
              durationSec: c.durationSec,
              itermSessionID: stripped,
              tty: c.tty,
              cwd: c.cwd
          )
      }
      var result = snap
      result.completed = newCompleted
      return (result, migrationCount)
  }
  ```

- `load()` calls `Self.migrateItermIDs(in: snap)` between schema check and return; logs migration count when > 0:
  ```
  D3-03: migrated <N> sessions to UUID-only iterm_session_id
  ```
- **Schema stayed at 1.** `grep -c "currentSchema = 1" App/SessionRecord.swift` → `1`. CONTEXT D3-03 lock honored.
- **Idempotent:** `raw.contains(":")` guard skips already-normalized records; second `stripped != raw` guard further skips edge cases where uuid(fromRaw:) returned input unchanged. Re-load yields zero migrations.

### Task 3 — Migration regression tests (3 new methods on `SessionStoreTests`)
- `test_load_migratesEnvelopeFormatItermID` — writes `"w0t0p1:79C4699F-..."`, asserts `load()` returns `"79C4699F-..."`.
- `test_load_idempotentWhenAlreadyNormalized` — already-normalized fixture round-trips unchanged (D3-04 idempotency property).
- `test_load_handlesNilItermSessionIDDuringMigration` — THR-02 orphan path (nil `itermSessionID`) survives migration unchanged.
- All added to existing `SessionStoreTests` class; no new test file (per CLAUDE.md "strengthen existing rather than parallel duplicates").
- D3-04 post-normalization AppleScript-contract assertion lives in 03-04's `AppleScriptHelperTests` (per plan-check B2), not here.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Updated `test_saveAndLoad_roundTrip` envelope-format fixtures**
- **Found during:** Task 2 build verification.
- **Issue:** The plan said "all existing SessionStoreTests must still pass," but the round-trip fixture stored `itermSessionID: "w0t0p1:UUID"` and `"w0t1p0:OTHER"` — exactly the envelope-format shape D3-03 migration strips. Post-migration, the round-trip equality (`save → load → equal`) inevitably breaks.
- **Fix:** Changed the two fixture values to colon-free strings (`"UUID"`, `"OTHER"`). Migration's `raw.contains(":")` guard skips colon-free input, preserving round-trip symmetry the test cares about. Two-character-range edits, no semantic widening.
- **Files modified:** `ClaudeAlertBotTests/SessionStoreTests.swift` (lines 41 & 48).
- **Bundled into:** Task 2 commit `b4ed25b` (so no known-red intermediate state).
- **Why this is the right resolution:** the conflict is between the plan text and the test's pre-existing intent. The test's job is to verify save/load symmetry, not to model a specific on-disk encoding; switching the fixture to a value that doesn't collide with migration semantics keeps both intents intact with minimum diff.

## Verification Results

| Check | Command | Result |
|---|---|---|
| HookListener normalization | `grep -c iTermSessionID.uuid App/HookListener.swift` | `1` ✓ |
| SessionRegistry write-site normalization | `grep -c iTermSessionID.uuid App/SessionRegistry.swift` | `1` ✓ |
| SessionStore migration helper | `grep -c migrateItermIDs App/SessionStore.swift` | `2` (declaration + call site) ✓ |
| SessionStore references iTermSessionID | `grep -c iTermSessionID App/SessionStore.swift` | `2` ✓ |
| Schema unchanged | `grep -c "currentSchema = 1" App/SessionRecord.swift` | `1` ✓ |
| New regression tests present | `grep -c "test_load_migrates" ClaudeAlertBotTests/SessionStoreTests.swift` | `1` ✓ |
| Full test suite | `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` | **TEST SUCCEEDED — 93 tests, 0 failures** ✓ |
| SessionStoreTests-only | `xcodebuild test ... -only-testing:ClaudeAlertBotTests/SessionStoreTests` | **8 tests, 0 failures** (5 existing + 3 new) ✓ |

## Schema Confirmation

`SessionsSnapshot.currentSchema = 1` — unchanged. Migration is in-memory only; the next persist cycle writes back normalized form via the existing atomic write path (Phase 2 D2-23). Re-loading yields zero migrations (idempotent property).

## Migration Log Wording

When `migrationCount > 0`, the exact log line is:
```
D3-03: migrated <count> sessions to UUID-only iterm_session_id
```
(Emitted at `.notice` level, `privacy: .public` for the count.)

## Threat Model Status

| Threat ID | Disposition | Mitigation Status |
|---|---|---|
| T-NORMALIZE-01 | mitigate | ✓ Migration is in-memory only; idempotency verified by `test_load_idempotentWhenAlreadyNormalized`. |
| T-D3-04-CARRY | mitigate | ✓ HookListener.suppressIfFrontmost closure normalizes; the AppleScript-contract regression test in 03-04 (AppleScriptHelperTests) will seal the contract end-to-end. |

## Threat Flags

None — no new network endpoints, auth paths, file access, or schema-trust-boundary surface introduced beyond what's in the plan's threat model.

## Files Touched

| File | Change |
|---|---|
| `App/HookListener.swift` | suppress closure now uses `iTermSessionID.uuid(fromRaw:)` |
| `App/SessionRegistry.swift` | `CompletedSession.itermSessionID` write goes through `iTermSessionID.uuid(fromRaw:)` |
| `App/SessionStore.swift` | new private static `migrateItermIDs(in:)`; `load()` calls it + logs |
| `ClaudeAlertBotTests/SessionStoreTests.swift` | 3 new regression tests; 2 fixture-value tweaks in `test_saveAndLoad_roundTrip` (Rule 1 deviation) |

## Commits

| Hash | Message |
|---|---|
| `6b483b2` | feat(03-03): normalize iterm_session_id at HookListener + SessionRegistry write site |
| `b4ed25b` | feat(03-03): SessionStore.load() in-memory migration of ':'-prefixed iterm_session_id (D3-03) |
| `9460e30` | test(03-03): add SessionStore migration regression tests (D3-03 / D3-04) |

## Self-Check: PASSED

- ✓ `App/HookListener.swift` modified — verified
- ✓ `App/SessionRegistry.swift` modified — verified
- ✓ `App/SessionStore.swift` modified — verified
- ✓ `ClaudeAlertBotTests/SessionStoreTests.swift` modified — verified
- ✓ Commit `6b483b2` exists in `git log`
- ✓ Commit `b4ed25b` exists in `git log`
- ✓ Commit `9460e30` exists in `git log`
- ✓ `xcodebuild test` — 93/93 passing
