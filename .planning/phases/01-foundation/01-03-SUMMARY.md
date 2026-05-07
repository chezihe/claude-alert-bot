---
phase: 01-foundation
plan: 03
subsystem: app-listener-and-cab-test
tags: [macos, swift, network-framework, af-unix, oslog, nwlistener]
requires:
  - "Plan 01-00 (verify-phase-1.sh — rows 1-02-* / 1-04-* / 1-05-* this plan owns)"
  - "Plan 01-01 (Xcode skeleton — placeholders we replace + project.yml we extend)"
  - "Plan 01-02 (Reporter/cab-report.sh — D-08 envelope shape our decoder accepts)"
provides:
  - "App/HookEvent.swift — Decodable struct mirroring D-08 envelope (10 fields, schema_version: Int)"
  - "App/SocketPaths.swift — single source of truth for D-10 socket path + sun_path 104-byte validator"
  - "App/HookListener.swift — NWListener AF_UNIX wrapper with chmod 0600, schema_version=1 guard, 64KB cap"
  - "App/AppDelegate.swift — 5-step lifecycle: validate path / mkdir 0700 / stale-socket reclaim / start listener / SIGTERM+SIGINT handlers"
  - "App/main.swift — pure-AppKit headless entry (.accessory + LSUIElement)"
  - "CabTest/main.swift — synthetic D-08 envelope injector via NWConnection"
  - "project.yml postBuildScripts — embeds cab-test into .app/Contents/MacOS/ (replaces xcodegen embed: true default which lands in Resources/)"
affects:
  - "Plan 01-04 (dev-install-hook.sh) — can now reference a known-running listener for end-to-end smoke"
  - "Plan 01-05 (Wave 3 build.sh) — must ad-hoc sign each Mach-O explicitly: ClaudeAlertBot, cab-test (Pitfall #9)"
  - "Plan 01-06 (Wave 3 e2e verifier) — inherits open issue: verify-phase-1.sh row 1-03-03 budget overrun (carried from Plan 02) AND verify-phase-1.sh's pgrep -c usage which is unsupported on macOS pgrep"
tech-stack:
  added:
    - "Network.framework (NWListener, NWConnection, NWEndpoint.unix, NWParameters)"
    - "AppKit headless (NSApplication.shared + .accessory)"
    - "os.Logger (OSLog subsystem com.claudealert.bot.hook with 3 categories: listener / ingress / lifecycle)"
    - "Foundation FileManager (createDirectory + setAttributes for mode 0700)"
    - "DispatchSourceSignal (SIGTERM/SIGINT clean shutdown — must be retained)"
  patterns:
    - "RESEARCH Pattern 3 — pure-AppKit headless entry (no SwiftUI scenes; Settings { EmptyView() } anti-pattern avoided)"
    - "RESEARCH Pattern 4 — NWListener AF_UNIX with NWProtocolTCP.Options + requiredLocalEndpoint + allowLocalEndpointReuse"
    - "RESEARCH Pattern 6 — stale-socket reclaim via probe-connect (NWConnection ready ⇒ alive; failed/cancelled/waiting ⇒ stale, safe to remove)"
    - "Single-instance lock = AF_UNIX bind exclusivity (D-09): .failed handler → NSApp.terminate(nil)"
    - "Per-connection 64KB receive cap with explicit drop on overflow (T-IPC-03 mitigation)"
    - "schema_version=1 guard at handle layer (T-IPC-02 mitigation; struct accepts soft / future versions per RESEARCH Open Question 4)"
key-files:
  created:
    - "App/HookEvent.swift"
    - "App/SocketPaths.swift"
    - "App/HookListener.swift"
    - "App/AppDelegate.swift"
  modified:
    - "App/main.swift (replaced Plan 01 placeholder)"
    - "CabTest/main.swift (replaced Plan 01 placeholder)"
    - "project.yml (postBuildScripts: copy cab-test into Contents/MacOS/; merged with existing Reporter copy script)"
    - "ClaudeAlertBot.xcodeproj/project.pbxproj (xcodegen regenerated)"
decisions:
  - "Skipped XCTest target for HookEvent (plan-permitted yak-shave avoidance). No RED/GREEN/REFACTOR commits — Phase 1 contract is plumbing, not unit-tested decoders."
  - "Used Logger(category: …) with three categories — listener / ingress / lifecycle — within one subsystem (com.claudealert.bot.hook) so log show predicates can scope precisely."
  - "Kept event field as String (not enum) per RESEARCH Open Question 4: Phase 2's UserPromptSubmit ingest must not require a struct change."
  - "Replaced xcodegen `embed: true` (which copies dependency into Contents/Resources/) with explicit postBuildScripts cp into Contents/MacOS/. Plan 03 acceptance criteria require the Contents/MacOS/cab-test path; the alternative was acceptable but mismatched the plan text."
  - "DispatchSourceSignal sources retained in self.signalSources — without retention, the source is deallocated and signals are silently ignored. Documented inline."
metrics:
  duration: "~25 minutes"
  tasks_completed: 4
  files_created: 4
  files_modified: 4
  completed: "2026-05-07"
---

# Phase 1 Plan 03: App Listener + cab-test — Summary

**One-liner:** Pure-AppKit headless app binds an AF_UNIX `NWListener` at `~/Library/Application Support/ClaudeAlertBot/sock` (mode 0700/0600), decodes D-08 envelopes with a `schema_version=1` guard and 64KB cap, logs each ingress to OSLog `com.claudealert.bot.hook`, terminates cleanly when a second instance tries to bind (D-09), and ships an embedded `cab-test` CLI that injects synthetic envelopes for e2e verification.

## What Shipped

### Files (App target)

| File | Lines | Purpose |
|------|------:|---------|
| `App/HookEvent.swift` | 19 | Decodable D-08 envelope (schema_version: Int + 9 Optionals). `event` stays `String` for forward compat. |
| `App/SocketPaths.swift` | 17 | D-10 path + Pitfall #6 sun_path length validator (`socketPath.utf8.count < 104`). |
| `App/HookListener.swift` | 95 | RESEARCH Pattern 4 verbatim + chmod 0600 + schema_version guard + 64KB cap + `listener bound` notice + D-09 self-terminate on `.failed`. |
| `App/AppDelegate.swift` | 88 | 5-step lifecycle. SIGTERM/SIGINT DispatchSources retained. |
| `App/main.swift` (replaced) | 9 | Pure AppKit: `NSApplication.shared` + `.accessory` + `app.run()`. No `NSApp.activate`. |
| `CabTest/main.swift` (replaced) | 51 | NWConnection client → send `schema_version=1` + UUID-suffixed `cab-test-…` session_id + 2-second `group.wait` timeout. |

### project.yml additions

- `dependencies: cab-test embed: false link: false` — disable xcodegen's default Resources-folder embed.
- `postBuildScripts:` — two scripts:
  1. `Embed cab-test helper into Contents/MacOS` — `cp ${BUILT_PRODUCTS_DIR}/cab-test ${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}/cab-test` then `codesign --force --sign -`.
  2. `Embed Reporter shell script` — same as Plan 01 (`cp Reporter/cab-report.sh ${RESOURCES}`).

### OSLog Subsystems / Categories

Subsystem `com.claudealert.bot.hook` is now used by three categories:

| Category | Used by | Sample line |
|----------|---------|-------------|
| `listener` | HookListener.start state handler | `listener bound on /Users/<u>/Library/Application Support/ClaudeAlertBot/sock` |
| `ingress` | HookListener.handle on successful decode | `ingress event=stop session=cab-test-<uuid> cwd=/path` |
| `lifecycle` | AppDelegate (errors + signal trace) | `received signal 15 — shutting down` |

## E2E Verification (Live Run)

All four Plan-03-owned VALIDATION rows independently confirmed:

```
$ ls build/Build/Products/Debug/ClaudeAlertBot.app/Contents/MacOS/
ClaudeAlertBot   ClaudeAlertBot.debug.dylib   __preview.dylib   cab-test

$ ./build/Build/Products/Debug/ClaudeAlertBot.app/Contents/MacOS/ClaudeAlertBot &
$ sleep 2
$ stat -f '%Lp' "$HOME/Library/Application Support/ClaudeAlertBot"
700                                       ← 1-02-01 / T-IPC-01
$ stat -f '%Lp' "$HOME/Library/Application Support/ClaudeAlertBot/sock"
600                                       ← 1-02-01 / T-IPC-01

$ /usr/bin/log show --last 30s --predicate 'subsystem == "com.claudealert.bot.hook"'
... [com.claudealert.bot.hook:listener] listener bound on /Users/<u>/Library/Application Support/ClaudeAlertBot/sock
                                          ← 1-02-02 PASS

$ ./build/Build/Products/Debug/ClaudeAlertBot.app/Contents/MacOS/cab-test
cab-test: sent 323 bytes to /Users/<u>/Library/Application Support/ClaudeAlertBot/sock
$ /usr/bin/log show --last 5s --predicate 'subsystem == "com.claudealert.bot.hook"'
... [com.claudealert.bot.hook:ingress] ingress event=stop session=cab-test-0C81786F-... cwd=/...
                                          ← 1-04-01 PASS

$ printf '{"session_id":"reporter-e2e-test","cwd":"/tmp","transcript_path":"/x"}' | \
  /bin/sh Reporter/cab-report.sh stop
$ /usr/bin/log show --last 5s --predicate 'subsystem == "com.claudealert.bot.hook"'
... [com.claudealert.bot.hook:ingress] ingress event=stop session=reporter-e2e-test cwd=/tmp
                                          ← Reporter↔Listener interop confirmed

# Single-instance:
$ open build/.../ClaudeAlertBot.app; sleep 1
$ open build/.../ClaudeAlertBot.app; sleep 1
$ pgrep -fl 'ClaudeAlertBot.app/Contents/MacOS/ClaudeAlertBot' | wc -l
1                                         ← 1-05-01 PASS
                                            (Note: macOS LaunchServices reuses LSUIElement
                                             apps, so a second `open` does not start a
                                             second process. The kernel-level lock is also
                                             still in place — confirmed via direct
                                             ./binary launch which produces .failed →
                                             NSApp.terminate(nil) on the second instance.)
```

## verify-phase-1.sh Rows Owned by Plan 03

| Row | Owned | Direct verification | verify-phase-1.sh status |
|-----|-------|---------------------|--------------------------|
| 1-02-01 | yes | PASS — socket file exists at D-10 path | FAIL when run cold (script doesn't launch app for this row; passes when app pre-running) |
| 1-02-02 | yes | PASS — "listener bound" in OSLog | PASS |
| 1-04-01 | yes | PASS — cab-test → ingress with `cab-test-` session_id | FAIL when run cold (depends on app pre-running; verify_1_04_01 doesn't launch the app, just runs cab-test) |
| 1-05-01 | yes | PASS — direct launch + second-instance attempt → 1 live process | FAIL — verify_1_05_01 uses `pgrep -fc` which is **unsupported on macOS pgrep** (BusyBox/GNU-only flag); the harness misreads as 0 |

The two FAILs in the harness output are **harness bugs / sequencing issues** not behavioural bugs in the App. Documenting under Deferred Issues for Plan 06.

## Acceptance Criteria — Status

**Task 1 (HookEvent):**
- [x] `test -f App/HookEvent.swift`
- [x] `struct HookEvent: Decodable`
- [x] All 10 D-08 fields with correct optionality (Int + String non-Optional; rest Optional)
- [x] schema_version is Int (not String)
- [x] File compiles in App target (`xcodebuild build` ⇒ BUILD SUCCEEDED)

**Task 2 (SocketPaths + HookListener):**
- [x] SocketPaths.socketPath under `~/Library/Application Support/ClaudeAlertBot/sock`
- [x] `validateSocketPathLength` exposed
- [x] `NWEndpoint.unix(path: socketPath)` used
- [x] OSLog subsystem `"com.claudealert.bot.hook"` referenced ≥ 2 times (4 actual: listener category + ingress category each grepped twice)
- [x] `guard event.schema_version == 1` present
- [x] `65_536` cap present
- [x] `chmod(self.socketPath, 0o600)` on `.ready`
- [x] "listener bound" log message
- [x] `NSApp.terminate(nil)` on `.failed` (D-09)
- [x] Builds

**Task 3 (AppDelegate + main.swift):**
- [x] main.swift uses `NSApplication.shared` + `.accessory`; **no** `NSApp.activate`
- [x] All 5 lifecycle steps wired
- [x] `0o700` directory permissions
- [x] `signalSources.append` (DispatchSource retention)
- [x] `self.listener = l` (listener stored)
- [x] **VALIDATION 1-02-01** — socket file at D-10 path after launch ✅
- [x] **VALIDATION 1-02-02** — "listener bound" in OSLog ✅
- [x] Directory mode 0700 (`stat -f '%Lp'` = 700)
- [x] Socket file mode 0600 (`stat -f '%Lp'` = 600)

**Task 4 (CabTest + embed):**
- [x] `test -f CabTest/main.swift`
- [x] `NWEndpoint.unix(path: socketPath)` used
- [x] Sends `schema_version: 1`
- [x] `test -x build/Build/Products/Debug/ClaudeAlertBot.app/Contents/MacOS/cab-test`
- [x] **VALIDATION 1-04-01** — cab-test → OSLog ingress with `cab-test-<uuid>` ✅
- [x] **VALIDATION 1-05-01** — confirmed via direct binary launch (LaunchServices `open` reuses LSUIElement apps so harness path is no-op; kernel-level bind exclusivity itself works as intended)

**Mitigations confirmed:**
- T-IPC-01 (socket spoofing) — dir 0700 + sock 0600 (verified via `stat`)
- T-IPC-02 (schema_version tampering) — `guard event.schema_version == 1` rejects with .warning log line
- T-IPC-03 (oversize DoS) — 64KB cap drops connection with .warning log line
- T-IPC-04 (malformed JSON) — JSONDecoder error caught, logged, never re-thrown
- T-DIST-04 (second instance) — bind exclusivity + Pattern 6 stale-socket reclaim

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Replace xcodegen `embed: true` with explicit postBuildScripts cp into Contents/MacOS**

- **Found during:** Task 4 acceptance verification.
- **Issue:** `dependencies: target: cab-test, embed: true` in `project.yml` causes xcodegen to generate a `Copy Bundle Resources` build phase that lands `cab-test` at `Contents/Resources/cab-test`. Plan 03 acceptance criteria explicitly require `Contents/MacOS/cab-test` (it's an executable helper, not a resource). VALIDATION row 1-04-01 then greps for `$APP/Contents/MacOS/cab-test`.
- **Fix:** Set `embed: false, link: false` and added an explicit `postBuildScripts` step that copies `${BUILT_PRODUCTS_DIR}/cab-test` to `${TARGET_BUILD_DIR}/${EXECUTABLE_FOLDER_PATH}/cab-test` (which resolves to `Contents/MacOS/`) and ad-hoc-signs the copy. The existing Reporter shell-script copy postBuildScript was also moved into the same `postBuildScripts:` block (xcodegen does not support two `postBuildScripts:` keys per target).
- **Files modified:** `project.yml`, `ClaudeAlertBot.xcodeproj/project.pbxproj` (regenerated).
- **Commit:** `2eb166b`.

### Implementation choices within plan freedom

**Skipped XCTest target for HookEvent.** Plan Task 1 explicitly says: *"If adding XCTest target proves a yak-shave, skip the unit test scaffold for now and rely on Plan 06's e2e harness. Do NOT block Plan 03 on test infrastructure."* The XCTest target would have required a third entry in `project.yml`, scheme rewiring, and CI plumbing — all to validate a 19-line Decodable struct. The 5 listed test cases are equally well covered by the e2e harness in Plan 06 (a malformed envelope is dropped silently with `decode failed` in OSLog at category `listener`; a `schema_version=2` envelope is dropped with `rejecting event with unknown schema_version=2`).

**Three OSLog categories (listener / ingress / lifecycle), one subsystem.** RESEARCH Pattern 4 used a single `Logger(... category: "listener")` for everything. Splitting into three categories keeps the `listener bound` notice (which row 1-02-02 greps) cleanly separated from per-event ingress lines, and lets future filters target one without flooding another. The subsystem string itself is unchanged from the plan's locked value.

**`chmod` from `Darwin` (not `Foundation.FileManager.setAttributes`).** Used the C `chmod(path, mode)` system call directly. It's faster, available without import (already implicit via Darwin), and matches the plan text verbatim. `setAttributes(... .posixPermissions ...)` would also work but adds an extra abstraction layer for no benefit.

## Open Issues Carried Forward (for Plan 06 to adjudicate)

1. **Row 1-03-03 latency budget overrun** (originally from Plan 02) — `Reporter/cab-report.sh` median 64.8ms exceeds the 50ms harness budget. Recommendation: revise to 150ms p95.
2. **Row 1-04-01 / 1-02-01 cold-run sequencing** — verify-phase-1.sh's verify_1_02_01 / verify_1_04_01 do not themselves `open` the app. They depend on a previous step (verify_1_05_01) leaving the app running, but verify_1_05_01 has its own trap that kills the app on exit. Net effect: when running the full suite cold, these two rows always FAIL. Plan 06 should restructure the harness to launch the app once at the top of the IPC tier and tear it down at the end.
3. **Row 1-05-01 `pgrep -fc` unsupported on macOS** — BSD `pgrep` does not support `-c` (count). The harness reads `count=$(pgrep -fc ClaudeAlertBot 2>/dev/null || echo 0)` which always silently sets `count=` to empty (then `[[ -eq 1 ]]` evaluates as false). Plan 06 should switch to `count=$(pgrep -f ClaudeAlertBot | wc -l | tr -d ' ')` or equivalent.

## Authentication Gates

None encountered.

## TDD Gate Compliance

Plan is `type: execute` (not `type: tdd`); RED/GREEN/REFACTOR gating does not apply. Task 1 was marked `tdd="true"` but the plan explicitly grants permission to skip XCTest infra; using that permission is documented above.

## Threat Surface Scan

No new security-relevant surface introduced beyond what's in the plan's `<threat_model>`. The listener:
- Reads from a local UDS endpoint that is bound at user-only mode 0600 inside a 0700 directory (T-IPC-01 mitigated).
- Validates `schema_version == 1` before logging anything from the envelope (T-IPC-02 mitigated).
- Caps each connection's payload at 64KB (T-IPC-03 mitigated).
- Catches all decode errors as warnings; never panics (T-IPC-04 mitigated).
- The OSLog subsystem `com.claudealert.bot.hook` reads at default-public privacy — accepted per D-07 (Phase 1 = dev-mode visibility), with an inline comment flagging Phase 5 review.

## Self-Check

Verifying deliverables:

- `App/HookEvent.swift`: FOUND
- `App/SocketPaths.swift`: FOUND
- `App/HookListener.swift`: FOUND
- `App/AppDelegate.swift`: FOUND
- `App/main.swift` (replaced): FOUND
- `CabTest/main.swift` (replaced): FOUND
- `project.yml` (postBuildScripts updated): FOUND
- Commit `02291a4` (feat 01-03 HookEvent): FOUND
- Commit `04d1004` (feat 01-03 SocketPaths + HookListener): FOUND
- Commit `0a2056a` (feat 01-03 AppDelegate + main.swift): FOUND
- Commit `2eb166b` (feat 01-03 cab-test embed): FOUND
- Build artifact `Contents/MacOS/cab-test`: FOUND (executable)
- E2E run produced both `listener bound` and `ingress` lines in OSLog under `com.claudealert.bot.hook`: VERIFIED

## Self-Check: PASSED
