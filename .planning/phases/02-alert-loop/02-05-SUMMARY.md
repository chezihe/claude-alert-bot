---
phase: 02-alert-loop
plan: 05
status: complete
completed: 2026-05-08
duration_minutes: 12
requirements: []
tags: [phase-2, wave-2, applescript, permissions, cheap-query, actor]
files_created:
  - App/AppleScriptHelper.swift
  - ClaudeAlertBotTests/AppleScriptHelperTests.swift
files_modified:
  - ClaudeAlertBot.xcodeproj/project.pbxproj
key_decisions:
  - "Static AppleScript source string — target match performed in Swift after the script returns (T-INJECTION-01 mitigation; never interpolate target into source)."
  - "AppleScript-side `with timeout of 1 second` block + Swift `withCheckedContinuation` on serial queue → main thread never blocked even on hung iTerm2 (Pitfall 3)."
  - "classify(error:result:) is a pure static function — testable in isolation; tests do not invoke live AppleScript or trigger TCC dialog."
  - "State mirror via `await MainActor.run { SettingsStore.shared.applescriptPermission = ... }` (Pitfall 9 — actor-isolated helper writes via main-actor hop, never touches @Published from background)."
  - "Silent-skip on denial/timeout/otherError (returns false) — D2-36 contract; suppress layer fails open, alerts always fire when permission absent."
  - "queueLabel test relies on `#filePath`-resolved path (not CWD-relative) — Rule 1 fix during GREEN; production code unchanged."
---

# Plan 02-05 SUMMARY — AppleScriptHelper actor

## What Shipped

Wave 2's parallel companion to 02-04 (SessionRegistry). The only Phase 2 component that crosses the macOS TCC boundary. Provides the body for the `suppressIfFrontmost: @Sendable (String?) async -> Bool` closure that 02-04's `ingest()` exposes.

| File | Role | Status |
|------|------|--------|
| `App/AppleScriptHelper.swift` | `actor AppleScriptHelper` — compile-once NSAppleScript + serial queue + 1s timeout + error classification + state mirror | Created |
| `ClaudeAlertBotTests/AppleScriptHelperTests.swift` | 9 unit tests covering source-string anchors, error classification, state mirror, compile-once contract, queue label | Created |

**Atomic commits on master:**
- `26c735f` — test(02-05): add failing AppleScriptHelperTests (TDD RED)
- `09863e0` — feat(02-05): AppleScriptHelper actor

## Public API Surface (downstream contract)

```swift
enum ScriptResult: Equatable {
    case success(String)
    case denied
    case timeout
    case otherError(Int)
}

actor AppleScriptHelper {
    static let shared: AppleScriptHelper

    // Cheap-query — D2-14. Returns true iff frontmost iTerm2 session id matches target.
    // Permission denial / timeout / other failure → false (silent skip per D2-36).
    func frontmostMatches(itermSessionID target: String) async -> Bool

    // D2-35 — used by Path A (Settings open) and Path B (first Stop) to surface TCC dialog.
    func triggerPermissionPrompt() async

    private(set) var lastKnownPermission: PermissionStatus    // .unknown by default

    // Pure classifier — exposed static for unit tests without live AppleScript.
    static func classify(error: NSDictionary?, result: String) -> ScriptResult

    #if DEBUG
    var rawSource: String { get }                             // Test seam.
    var compiledForTesting: NSAppleScript? { get }            // Test seam.
    func markGrantedForTesting() async                        // Test seam.
    func markDeniedForTesting() async                         // Test seam.
    #endif
}
```

## Canonical AppleScript Source (verbatim, locked)

The full script string compiled at first call and reused thereafter. **Plan-checker invariant:** future plans MUST NOT interpolate user-controlled data into this string (T-INJECTION-01).

```applescript
with timeout of 1 second
    tell application "iTerm2"
        if (count of windows) is 0 then return ""
        return id of current session of current tab of current window
    end tell
end timeout
```

Field-by-field guarantees:
- `with timeout of 1 second` — AppleScript-side hard timeout (Pitfall 3, D2-34); Stop alert latency budget protected even if iTerm2 itself hangs.
- `if (count of windows) is 0 then return ""` — empty-string sentinel; Swift treats it as a non-match (`!s.isEmpty && s == target`).
- `id of current session of current tab of current window` — read-only query; never sends commands.
- No `\(target)` or `&` operator — target match happens in Swift after the script returns its raw value.

## Error-Code → ScriptResult Mapping

| AppleScript error code | Constant | ScriptResult | Behavior | Wave 5 banner |
|------------------------|----------|--------------|----------|---------------|
| `-1743` | `errAEEventNotPermitted` | `.denied` | mark SettingsStore .denied via MainActor hop, log error, return false | **Show** "Automation 권한 없음" banner with deep-link |
| `-1712` | `errAEEventTimeout` | `.timeout` | log warning, return false (no state change) | No banner (transient) |
| any other non-nil | — | `.otherError(code)` | log warning with code, return false | No banner |
| nil (success) | — | `.success(value)` | mark SettingsStore .granted via MainActor hop, return `!value.isEmpty && value == target` | No banner (cleared) |

This mapping is the **single contract** between Wave 5 SettingsView banner and the helper. Wave 5 shows the deep-link banner only on `.denied`. Wave 4 / Wave 6 ignore the helper's permission state entirely — they consume only the boolean.

## Trigger Path Reservations

D2-35 hybrid: two trigger paths surface the TCC dialog. macOS shows the dialog once per (app, target); whichever path fires first carries the user through.

- **Path A (Wave 5 / SettingsView, plan 02-08):**
  ```swift
  // SettingsView.onAppear OR a "Show settings" notification handler:
  Task { await AppleScriptHelper.shared.triggerPermissionPrompt() }
  ```
  User explicitly opens Settings → context-rich permission request.

- **Path B (Wave 6 / AppDelegate hook dispatch, plan 02-11):**
  ```swift
  // HookListener dispatch closure (the suppressIfFrontmost seam from 02-04):
  await SessionRegistry.shared.ingest(event, ...) { iTermID in
      guard let iTermID else { return false }
      return await AppleScriptHelper.shared.frontmostMatches(itermSessionID: iTermID)
  }
  ```
  First Stop arrival when the user has not opened Settings → cheap-query call itself triggers the dialog. The first alert fires normally (cannot be suppressed without permission); subsequent alerts get the D2-14 layer.

## Wave 6 Manual Checkpoint Anchor

Real iTerm2 + first Stop event must produce the macOS Apple Events permission dialog with the **D2-33 Korean copy** verbatim:

> "Claude Alert Bot이 iTerm2의 현재 탭을 확인해서 이미 보고 있는 작업의 알림을 끄고, 클릭 시 정확한 탭으로 이동하기 위해 사용합니다."

(Already locked into `App/Info.plist` and `project.yml` by plan 02-02 — verified at run time only here.)

## Threat Model — Closure Notes

| Threat ID | Disposition | Closure |
|-----------|-------------|---------|
| T-PERM-01 | mitigate | State mirrored to `SettingsStore.shared.applescriptPermission` on every query result that resolves the permission. Wave 5 SettingsView watches `@Published` and surfaces the banner — denial is **visible**, not silent. |
| T-INJECTION-01 | mitigate | AppleScript source is `private static let scriptSource: String` constant. Test 1 grep-asserts `with timeout of 1 second` AND `id of current session of current tab of current window`. No `\(target)` interpolation. Match happens at `s == target` in Swift. |
| T-CONC-02 | mitigate | Dedicated `DispatchQueue(label: "com.claudealert.bot.applescript")`. Test 9 grep-asserts the literal label string in `App/AppleScriptHelper.swift`. RESEARCH Pitfall 3 directly closed. |
| T-TIMEOUT-01 | mitigate | AppleScript-side `with timeout of 1 second` block + Swift continuation on a separate queue. Worst case (iTerm2 deadlocked, AppleScript ignores timeout): the BG queue's task may leak, but main thread remains responsive — accepted trade-off, revisit if observed. |

## Verifier Row Body (for 02-11 to graft into scripts/verify-phase-2.sh)

```bash
verify_2_05_01() {
    local id="2-05-01" name="AppleScriptHelper compile-once + classify + state mirror"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/AppleScriptHelperTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 — Planning artifact bug] Plan frontmatter listed `requirements: [WIDG-02]` — wrong REQ-ID**
- **Found during:** state-update step (after final commit, while running `requirements mark-complete WIDG-02`)
- **Issue:** WIDG-02 = "위젯이 등장할 때 현재 앱의 포커스를 빼앗지 않는다 (`.nonactivatingPanel`, `becomesKeyOnlyIfNeeded`)" — pure NSPanel behavior. This plan ships `AppleScriptHelper` (zero NSPanel code). The two have no overlap. AppleScriptHelper is infrastructure for the D2-13/14/15 + D2-33/35/36 *decisions* (cheap-query suppress + Apple Events permission UX), which were added to Phase 2 from Phase 3 — they're not in the v1 REQ-ID list at all.
- **Investigation:** REQUIREMENTS.md's WIDG-02 was already marked `[x] Complete` before plan 02-05 started — the false mark traces back to commit `666c3e2 docs(02-04): complete SessionRegistry + SessionStore plan`, despite 02-04's own frontmatter listing `[SESS-01, SESS-02, SESS-03, SESS-04, THR-01, THR-02, AUD-01]` (no WIDG-02). Likely a planner-side mishap during 02-04's execution.
- **Fix:** Updated this SUMMARY's frontmatter `requirements: []` (this plan satisfies no tracked v1 REQ-ID — it ships infrastructure for un-tracked decisions). The pre-existing false `[x] WIDG-02` mark in REQUIREMENTS.md is a known issue from plan 02-04 — **NOT reverted by this plan** per scope boundary (CLAUDE.md "No Over-Editing"; reverting would touch state owned by a prior plan). Logged to deferred-items.
- **Files modified:** `.planning/phases/02-alert-loop/02-05-SUMMARY.md` only. `.planning/REQUIREMENTS.md` deliberately untouched.
- **Action item for the planner / verifier:** WIDG-02 must be re-opened by a future Phase 2 widget plan (likely 02-09 NSPanel widget) and remarked complete only after `.nonactivatingPanel` + `becomesKeyOnlyIfNeeded` are wired into a real widget. The Phase 2 verifier (02-12) should add a row that grep-asserts those two strings in the codebase before passing WIDG-02.

**2. [Rule 1 — Test bug] `test_queueLabel_isSerial_byConvention` used CWD-relative path**
- **Found during:** Task 1 GREEN run (1 failure: `XCTAssertTrue failed - Queue label must be com.claudealert.bot.applescript`)
- **Issue:** The plan's source-string-grep approach used `String(contentsOfFile: "App/AppleScriptHelper.swift")`, which resolves against the test process's working directory. xcodebuild's test runner CWD is the DerivedData test bundle path, not the project root → `src` resolved to empty string.
- **Fix:** Use `URL(fileURLWithPath: #filePath)` (the test file's own absolute path), walk up two directory levels to the project root, then append `App/AppleScriptHelper.swift`. CWD-independent and stable across CI/dev machines.
- **Files modified:** `ClaudeAlertBotTests/AppleScriptHelperTests.swift` (test 9 body only — same atomic unit as the helper implementation under TDD; production code unchanged)
- **Commit:** `09863e0` (Task 1 GREEN includes the test fix in the same commit)

No production code deviations. Plan executed verbatim otherwise.

## Verification Run Results

| Verification | Command | Result |
|--------------|---------|--------|
| `verify_2_05_01` | `xcodebuild test -only-testing:ClaudeAlertBotTests/AppleScriptHelperTests` | 9/9 pass (0.57s) |
| Production build | `xcodebuild build -scheme ClaudeAlertBot` | BUILD SUCCEEDED (no new warnings; pre-existing build-script warnings are inherited from Phase 1) |
| Full test target (regression) | `xcodebuild test -scheme ClaudeAlertBot` | 40/40 pass (Phase 1 + 02-00 + 02-02 + 02-03 + 02-04 + 02-05 — no regressions) |
| `with timeout of 1 second` count | `grep -c 'with timeout of 1 second' App/AppleScriptHelper.swift` | 3 (≥1 required — comment + source + comment) |
| Queue label count | `grep -c 'com\.claudealert\.bot\.applescript' App/AppleScriptHelper.swift` | 1 |
| OSLog subsystem invariant | `grep -c 'subsystem: "com.claudealert.bot.hook"' App/AppleScriptHelper.swift` | 1 (Phase 1 invariant preserved) |

## Self-Check: PASSED

- [x] App/AppleScriptHelper.swift exists and compiles
- [x] ClaudeAlertBotTests/AppleScriptHelperTests.swift exists (9/9 pass)
- [x] `actor AppleScriptHelper` with `static let shared` — production callers use the singleton
- [x] Public API: `frontmostMatches(itermSessionID:)`, `triggerPermissionPrompt()`, `lastKnownPermission`
- [x] Static `scriptSource` constant — no `\(target)` interpolation (T-INJECTION-01)
- [x] AppleScript-side `with timeout of 1 second` block present (Pitfall 3 anchor)
- [x] Pure `classify(error:result:)` static func — maps -1743/-1712/other/nil correctly
- [x] State mirror via `await MainActor.run { SettingsStore.shared.applescriptPermission = ... }`
- [x] Serial `DispatchQueue` label literal `com.claudealert.bot.applescript`
- [x] OSLog `subsystem: "com.claudealert.bot.hook", category: "applescript"` (D2-37)
- [x] `#if DEBUG` test seams: `rawSource`, `compiledForTesting`, `markGrantedForTesting`, `markDeniedForTesting` — production callers do not access these
- [x] Full test target run: 40/40 pass — no regressions
- [x] git log: 2 commits on master (RED + GREEN)

## Commit-existence verification

```bash
git log --oneline | grep -E "26c735f|09863e0"
# 09863e0 feat(02-05): AppleScriptHelper actor — compile-once, 1s timeout, error classification, state mirror
# 26c735f test(02-05): add failing AppleScriptHelperTests (TDD RED)
```

## TDD Gate Compliance

| Gate | Commit | Type |
|------|--------|------|
| RED | `26c735f` | `test(02-05)` |
| GREEN | `09863e0` | `feat(02-05)` |

RED → GREEN strictly. No REFACTOR commit — implementation matched the canonical RESEARCH Pattern 3 template; the only adjustment was the test-side path-resolution fix included in GREEN.

## Key Files

- `/Users/choijihye/Study/source/claude_alert_bot/App/AppleScriptHelper.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/ClaudeAlertBotTests/AppleScriptHelperTests.swift`

## Next

Wave 2 closes with this plan + 02-04 already shipped. The `suppressIfFrontmost` closure parameter on `SessionRegistry.ingest()` (frozen by 02-04) now has its production body — Wave 6 02-11's HookListener dispatch will wire:

```swift
await SessionRegistry.shared.ingest(event, ...) { iTermID in
    guard let iTermID else { return false }
    return await AppleScriptHelper.shared.frontmostMatches(itermSessionID: iTermID)
}
```

**Wave 3 (02-06 NotificationOrchestrator)** is the next executable plan — implements `NotifierProtocol` concretely against the API surface that 02-04 froze. AppleScriptHelper is leaf-level (no further consumers in Wave 3).
