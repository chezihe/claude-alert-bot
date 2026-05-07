---
phase: 01-foundation
plan: 05
subsystem: build-pipeline
tags: [macos, xcodebuild, codesign, ad-hoc, distribution, dist-01]
requires:
  - "Plan 01-01 (Xcode project + ClaudeAlertBot scheme + cab-test target)"
  - "Plan 01-03 (App listener + cab-test source — both Mach-Os must be present in the archive for the per-binary signing loop)"
provides:
  - "scripts/build.sh — one-command Phase 1 build pipeline (archive + per-Mach-O ad-hoc sign + verify)"
  - "Canonical output path: build/export/ClaudeAlertBot.app"
  - "Idempotent ad-hoc-signed .app reproducible on any Apple Silicon dev host without Apple Developer Program"
affects:
  - "Plan 01-06 (Wave 3 e2e verifier) — verify-phase-1.sh's APP_PATH default already points at build/export/ClaudeAlertBot.app; Plan 06 should standardize on this path and remove the build/Build/Products/Debug references inherited from Plan 03"
  - "Phase 6 (Distribution) — release.sh will wrap this script and add create-dmg packaging; the `-` ad-hoc identity will be swapped for a Developer ID identity if the project ever joins the Apple Developer Program"
tech-stack:
  added:
    - "xcodebuild archive (Xcode 26.0.1 toolchain on the dev host; targets macOS 14)"
    - "codesign (Apple's /usr/bin/codesign — system tool, no install)"
  patterns:
    - "Per-Mach-O explicit signing (RESEARCH Pitfall #9): helper(s) → main exe → bundle seal LAST"
    - "Fail-on-unsigned guard: each binary's `codesign -dv` Signature line is grepped for `Signature=adhoc`; non-zero exit on any miss"
    - "Idempotent clean rebuild: `rm -rf $BUILD_DIR` at top so re-running on an already-built tree produces the same artifact shape"
key-files:
  created:
    - "scripts/build.sh"
  modified: []
decisions:
  - "Used explicit per-Mach-O `codesign --force --sign - --options=runtime` instead of `codesign --force --deep --sign -` (D-11's literal text). RESEARCH Pitfall #9 documents that Apple deprecated the recursive flag in macOS 13 (TN3127); explicit per-binary signing is the recommended replacement. Effect on ad-hoc signing is identical, but explicit form is reliably future-proof. Acceptance criteria explicitly forbid `--deep` (`! grep -q -- '--deep' scripts/build.sh`)."
  - "Canonical output path is `build/export/ClaudeAlertBot.app`. This matches `scripts/verify-phase-1.sh`'s `APP_PATH` default (set by Plan 00) and the RESEARCH Code Examples block. Plan 03's `build/Build/Products/Debug/...` is the xcodebuild-derived-data path used by Debug builds and should be reconciled in Plan 06."
  - "`--options=runtime` retained on every codesign call. For ad-hoc identity it has no enforcement effect, but it sets up the option flag so the same bundle can be re-signed later with a Developer ID identity without flag changes. RESEARCH-prescribed."
  - "Phase 6 prep note: when swapping `-` for `Developer ID Application: …`, the only changes needed are (a) replace `--sign -` with `--sign \"Developer ID Application: <name> (<team>)\"`, (b) chain `xcrun notarytool submit` after the bundle seal, (c) `xcrun stapler staple` the .app, (d) feed it into `create-dmg`. The current per-Mach-O loop and verify-block stay verbatim."
metrics:
  duration: "~5 minutes (single task, no rework)"
  tasks_completed: 1
  files_created: 1
  files_modified: 0
  build_time_seconds: 16
  archive_size_mb: 8.8
  exported_app_size_kb: 412
  main_exe_size_bytes: 239712
  cab_test_size_bytes: 163168
  completed: "2026-05-07"
---

# Phase 1 Plan 05: Build Pipeline (xcodebuild + ad-hoc codesign) Summary

**One-liner:** `scripts/build.sh` runs `xcodebuild archive` (Release configuration) → copies the `.app` to the canonical `build/export/` path → ad-hoc-signs each Mach-O explicitly in order (cab-test → main exe → bundle seal LAST, no `--deep`) → fails non-zero if any binary lacks `Signature=adhoc` — producing a launchable, ad-hoc-signed `ClaudeAlertBot.app` on Apple Silicon without `cs_invalid_page` errors, in ~16 seconds end-to-end.

## What Shipped

### `scripts/build.sh` (71 lines, mode 0755)

Five-stage pipeline, one execution flow, no branches:

| Stage | Command(s) | Purpose |
|-------|-----------|---------|
| 0. Clean | `rm -rf "$BUILD_DIR"; mkdir -p "$BUILD_DIR"` | Idempotent rebuild — guarantees the next steps see no stale artifacts. |
| 1. Archive | `xcodebuild -scheme ClaudeAlertBot -configuration Release -archivePath … -destination 'generic/platform=macOS' archive` | Produces `build/ClaudeAlertBot.xcarchive` containing `Products/Applications/ClaudeAlertBot.app`. |
| 2. Export | `cp -R "$ARCHIVE_PATH/Products/Applications/$APP_NAME" "$EXPORT_DIR/"` | Lands the `.app` at the **canonical path** `build/export/ClaudeAlertBot.app`. |
| 3. Sign | `codesign --force --sign - --options=runtime` × 3 (cab-test → main exe → bundle) | Per-Mach-O explicit signing per RESEARCH Pitfall #9 — bundle seal LAST. |
| 4. Verify | `codesign -dv --verbose=4` per binary, grep `Signature=adhoc`, plus `codesign --verify --verbose=4` on the bundle | Non-zero exit on any non-adhoc binary; structural integrity check at the end. |

The `cab-test` signing step is guarded with `[ -f … ] && codesign …` so that if Plan 01 / Plan 03 ever drop the helper, the script doesn't fail on a missing path; its acceptance check then short-circuits.

## Verification Run (live)

```
$ time bash scripts/build.sh
=== Archiving ===
... (xcodebuild output) ...
** ARCHIVE SUCCEEDED **
=== Ad-hoc signing ===
…/build/export/ClaudeAlertBot.app/Contents/MacOS/cab-test: replacing existing signature
…/build/export/ClaudeAlertBot.app/Contents/MacOS/ClaudeAlertBot: replacing existing signature
…/build/export/ClaudeAlertBot.app: replacing existing signature
=== Verifying signatures ===
--prepared:…/cab-test
--validated:…/cab-test
…/ClaudeAlertBot.app: valid on disk
…/ClaudeAlertBot.app: satisfies its Designated Requirement

=== Build complete ===
App: /Users/choijihye/Study/source/claude_alert_bot/build/export/ClaudeAlertBot.app
Bundle: Signature=adhoc
Main:   Signature=adhoc
CabTest: Signature=adhoc
bash scripts/build.sh  16.51s total
```

### Independent post-build inspection

```
$ codesign -dv --verbose=4 build/export/ClaudeAlertBot.app 2>&1 | head -7
Executable=…/Contents/MacOS/ClaudeAlertBot
Identifier=com.claudealert.bot
Format=app bundle with Mach-O universal (x86_64 arm64)
…
Signature=adhoc                                     ← bundle ad-hoc

$ codesign -dv --verbose=4 build/export/ClaudeAlertBot.app/Contents/MacOS/cab-test 2>&1 | grep Signature
Signature=adhoc                                     ← embedded helper ad-hoc

$ codesign --verify --verbose=4 build/export/ClaudeAlertBot.app
…/ClaudeAlertBot.app: valid on disk
…/ClaudeAlertBot.app: satisfies its Designated Requirement
```

### Apple Silicon launch (RESEARCH Validation Architecture Success #3)

```
$ rm -f "$HOME/Library/Application Support/ClaudeAlertBot/sock"
$ ./build/export/ClaudeAlertBot.app/Contents/MacOS/ClaudeAlertBot &
[PID=92035]
$ sleep 2
$ test -S "$HOME/Library/Application Support/ClaudeAlertBot/sock" && echo SOCK_EXISTS
SOCK_EXISTS
$ /usr/bin/log show --last 15s --predicate 'subsystem == "com.claudealert.bot.hook"' | tail -1
… ClaudeAlertBot: [com.claudealert.bot.hook:listener] listener bound on \
  /Users/<u>/Library/Application Support/ClaudeAlertBot/sock
$ kill -TERM 92035   # clean SIGTERM shutdown (signal handler from Plan 03)

$ /usr/bin/log show --last 30s --predicate 'eventMessage CONTAINS "cs_invalid_page"' | grep -i claudealertbot
(no output — empty)
```

The Release-configuration, ad-hoc-signed `.app` launches cleanly on Apple Silicon, binds the AF_UNIX listener, and produces no `cs_invalid_page` faults.

## Acceptance Criteria — All Met

| # | Criterion | Result |
|---|-----------|--------|
| 1 | `test -x scripts/build.sh` | PASS |
| 2 | `bash -n scripts/build.sh` | PASS |
| 3 | Signs cab-test explicitly (regex match) | PASS |
| 4 | Signs main exe explicitly (regex match) | PASS |
| 5 | Bundle codesign appears AFTER both Mach-O codesigns (awk line-order check) | PASS |
| 6 | `--options=runtime` count ≥ 3 | PASS — 3 occurrences (one per binary) |
| 7 | Does NOT use `--deep` (Pitfall #9) | PASS |
| 8 | Verification check fails the script if signature is not ad-hoc (`exit 1` + `Signature=adhoc` both present) | PASS |
| 9 | **VALIDATION 1-00-01** — `bash scripts/build.sh` produces `build/export/ClaudeAlertBot.app` | PASS |
| 10 | **VALIDATION 1-00-02** — bundle `Signature=adhoc` | PASS |
| 11 | cab-test also `Signature=adhoc` | PASS |
| 12 | **RESEARCH Success #3** — built `.app` launches; no `cs_invalid_page` | PASS |
| 13 | `codesign --verify --verbose=4` passes | PASS |
| 14 | T-DIST-01 mitigated (per-Mach-O sign + verify gate) | PASS — script exits 1 on any non-adhoc binary |
| 15 | T-DIST-05 mitigated (clean rebuild) | PASS — `rm -rf "$BUILD_DIR"` at top |
| 16 | T-DIST-07 mitigated (no `--deep` regression) | PASS — acceptance criterion 7 enforces |

VALIDATION rows turning green this plan: **1-00-01, 1-00-02** (Wave 0 build-pipeline rows finally satisfied by Wave 3's actual build script — Plan 00 placed these rows at Wave 0 anticipating this dependency).

## Canonical Build Path Decision (Open Issue 4 from Plan 03)

Plan 03's SUMMARY flagged three competing paths for the built `.app`:

1. `build/Debug/ClaudeAlertBot.app` (Plan 03 plan text, never actually used)
2. `build/export/ClaudeAlertBot.app` (Plan 00's `verify-phase-1.sh` `APP_PATH` default)
3. `build/Build/Products/Debug/ClaudeAlertBot.app` (xcodebuild's derived-data path used in Plan 03's live verification)

**Resolution: this plan's `scripts/build.sh` emits to `build/export/ClaudeAlertBot.app` — chosen as canonical going forward.** Reasons:

- It matches `scripts/verify-phase-1.sh`'s default with no override needed.
- It's a stable, predictable path under the repo root (`build/export/`) — not derived from the build-system's internal layout, so it survives Xcode upgrades and `-derivedDataPath` overrides.
- `cp -R` from the xcarchive is idempotent and trivial; no symlinks or other layout cleverness.

Plan 06 should:
- Confirm `verify-phase-1.sh`'s `APP_PATH=${APP_PATH:-…/build/export/ClaudeAlertBot.app}` is unchanged (it should be).
- Document this canonical path in `01-VERIFICATION.md` so Phase 2+ knows where to find the bundle.
- Phase 3+ should always launch via `open build/export/ClaudeAlertBot.app` for Automation-permission consistency (TCC ties to bundle path).

For local Debug iteration via Xcode, developers will still hit the derived-data path — that's expected and not a contradiction. The canonical path applies to the **build-script-produced artifact** that downstream phases (verifier, .dmg packaging) consume.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Bug] Reworded comment to avoid `--deep` substring match**

- **Found during:** Task 1 acceptance verification — initial comment `# Pitfall #9 — --deep is deprecated` matched the `! grep -q -- '--deep' scripts/build.sh` guard, failing the criterion.
- **Issue:** The acceptance check is a literal `grep -q -- '--deep'`; it cannot distinguish between an actual flag and a comment that *mentions* the flag. Both substrings are forbidden by the criterion as written.
- **Fix:** Reworded the inline comment to `# Pitfall #9 — Apple deprecated the recursive flag` — same documentary intent, no `--deep` substring anywhere in the file.
- **Files modified:** `scripts/build.sh` (one-line comment edit, before the first commit).
- **Commit:** `97de952` (the Task 1 commit; the wording was fixed pre-commit).

### D-11 Deviation (intentional, planned)

**Plan deliberately deviates from D-11's literal `codesign --force --deep --sign -` text** — see Decisions section above.

D-11's intent: ad-hoc sign the bundle so it runs on Apple Silicon without Apple Developer Program enrollment.
RESEARCH Pitfall #9 disposition: Apple deprecated `--deep` in macOS 13 (TN3127) and recommends explicit per-binary signing.

This script honors D-11's intent (every Mach-O is ad-hoc-signed; `Signature=adhoc` confirmed on bundle + main + cab-test) and substitutes the deprecated flag with the recommended per-binary form. The Phase 1 plan text explicitly demands this substitution (acceptance criterion 7: `! grep -q -- '--deep' scripts/build.sh`), so this is a *plan-mandated* deviation from the older D-11 text, not a planner-introduced surprise.

## Threat Surface Scan

No new security-relevant surface introduced beyond `<threat_model>`. The script:
- Operates entirely on developer-side artifacts (no network, no user data exfiltration).
- T-DIST-01 (unsigned helper inside signed bundle): mitigated — `cab-test` is signed BEFORE bundle seal and verified independently.
- T-DIST-05 (stale build artifacts): mitigated — `rm -rf` at the top.
- T-DIST-07 (`--deep` regression): mitigated — acceptance criterion forbids it; CI re-runs the verifier.

Phase 6 will re-evaluate when notarization + Developer-ID signing enter the pipeline.

## Codesign Warnings Observed

None during the verify pass. Two **build-time** warnings persist from Plan 01/03 (cosmetic only, not codesign-related):

```
warning: Run script build phase 'Embed Reporter shell script' will be run during every build
because it does not specify any outputs.
warning: Run script build phase 'Embed cab-test helper into Contents/MacOS' will be run during
every build because it does not specify any outputs.
```

These are documented in Plan 01's SUMMARY ("Known Build Warnings") and Plan 03's SUMMARY. They affect incremental-build performance, not signing or correctness. Phase 1 hasn't established build-cache discipline; Phase 6 may address them when release.sh adds incremental-aware caching.

The `Sign to Run Locally` line emitted by `xcodebuild`'s internal codesign step is the expected ad-hoc identity label used by Xcode 26 when `CODE_SIGN_IDENTITY="-"`; it is the SAME identity our explicit post-archive `codesign --sign -` re-applies. The "replacing existing signature" lines confirm the re-sign happened correctly (bundle seal is what authoritatively reaches the user, not Xcode's intermediate signature).

## Phase 6 Prep Notes (what changes when swapping `-` for Developer ID)

1. Replace `--sign -` with `--sign "Developer ID Application: <Name> (<TeamID>)"` in all four codesign calls.
2. Inject `--timestamp` to all signing calls (mandatory for notarization).
3. After bundle seal, add:
   ```bash
   ditto -c -k --keepParent "$APP" "$BUILD_DIR/ClaudeAlertBot-for-notary.zip"
   xcrun notarytool submit "$BUILD_DIR/ClaudeAlertBot-for-notary.zip" \
       --keychain-profile "claude-alert-notary" --wait
   xcrun stapler staple "$APP"
   ```
4. Replace the `Signature=adhoc` grep with `Signature size=` (or check `TeamIdentifier=`) since chain-signed bundles report a real chain, not `adhoc`.
5. The per-Mach-O loop and bundle-seal-LAST order **stay verbatim** — Pitfall #9 applies the same way for chain signing.

## Authentication Gates

None encountered.

## TDD Gate Compliance

Plan is `type: execute` (not `type: tdd`); RED/GREEN/REFACTOR gating does not apply. Verification is via the script's own exit-code gate plus independent `codesign -dv` and a launch smoke-test, which collectively cover all acceptance criteria.

## Self-Check

Verifying deliverables:

- `scripts/build.sh`: FOUND (71 lines, mode 0755, `bash -n` valid)
- Commit `97de952` (feat 01-05 build.sh): present in `git log`
- `build/export/ClaudeAlertBot.app`: FOUND (412KB; `Signature=adhoc`)
- `build/export/ClaudeAlertBot.app/Contents/MacOS/ClaudeAlertBot`: FOUND (239,712 bytes; `Signature=adhoc`)
- `build/export/ClaudeAlertBot.app/Contents/MacOS/cab-test`: FOUND (163,168 bytes; `Signature=adhoc`)
- `codesign --verify --verbose=4 build/export/ClaudeAlertBot.app` exits 0: VERIFIED
- App launches on Apple Silicon, binds AF_UNIX socket, emits `listener bound` OSLog, no `cs_invalid_page`: VERIFIED via direct binary launch + `kill -TERM` clean shutdown
- Acceptance criterion 7 (`! grep -q -- '--deep' scripts/build.sh`): PASS

## Self-Check: PASSED
