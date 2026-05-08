---
phase: 02-alert-loop
plan: 02
subsystem: permissions-prep
tags: [phase-2, wave-0, permissions, korean-copy, system-deep-link, tdd]
requires:
  - Phase 2 Plan 02-00 (XCTest target + verify-phase-2.sh skeleton)
  - xcodegen 2.45+, Xcode 15.4+ macOS 14 SDK
provides:
  - App/PermissionDeepLink.swift (urls: [String], openAutomationPreferences())
  - D2-33 Korean NSAppleEventsUsageDescription in App/Info.plist + project.yml
  - 2 passing PermissionDeepLinkTests guarding D2-36 URL sequence
  - verify_2_02_01 + verify_2_02_02 row bodies (for 02-11 to graft into verify-phase-2.sh)
affects:
  - App/AppDelegate.swift (Rule 1 fix — idempotent dispatch_group_leave guard in reclaimSocketIfStale)
tech-stack:
  added: []
  patterns: [TDD RED→GREEN cycle, idempotent NWConnection state handler]
key-files:
  created:
    - App/PermissionDeepLink.swift
    - ClaudeAlertBotTests/PermissionDeepLinkTests.swift
  modified:
    - App/Info.plist (NSAppleEventsUsageDescription → Korean)
    - project.yml (NSAppleEventsUsageDescription → Korean)
    - App/AppDelegate.swift (Rule 1 race fix in reclaimSocketIfStale)
    - ClaudeAlertBot.xcodeproj/project.pbxproj (xcodegen-regenerated for new files)
decisions:
  - "PermissionDeepLink exposes `urls` as `static let` (not embedded in openAutomationPreferences) so unit tests can verify the list independent of NSWorkspace.shared.open's side effect."
  - "verify_2_02_01 + verify_2_02_02 rows live as row-bodies in this SUMMARY only — scripts/verify-phase-2.sh is owned by 02-11 (e2e wave), which grafts them in to avoid file-ownership conflicts."
  - "Phase 1 latent race in reclaimSocketIfStale's NWConnection state handler is fixed here (Rule 1) rather than deferred — every downstream Phase 2 plan's xcodebuild test would otherwise hit the same coin-flip crash."
metrics:
  duration_min: 30
  completed: 2026-05-08
  tasks_total: 2
  tasks_completed: 2
  files_created: 2
  files_modified: 3
requirements: [WIDG-02]
---

# Phase 2 Plan 02: Permissions Prep (Korean copy + System Settings deep-link) Summary

**One-liner:** Two pre-implementation chores that unblock downstream Phase 2 plans — D2-33 Korean NSAppleEventsUsageDescription locked in both Info.plist and project.yml (drift-proof), and D2-36 sequential System Settings deep-link helper with regression-guarded URL ordering test.

## Why

Two small chores blocked the rest of Phase 2:

1. **D2-33 Korean copy** — The Apple Events permission dialog will fire in Phase 2 (D2-35 first-Stop, or D2-35 Path A "Test notification" Settings trigger). The user sees this string verbatim. Phase 1 shipped a placeholder English string ("Claude Alert Bot needs to switch focus to your iTerm2 tab when a Claude Code task completes."); generic strings drive denial (Pitfall #3 / T-PERM-01). The Korean copy is the first thing the user reads when deciding whether to grant automation permission — gating on the wrong copy poisons every downstream verification.

2. **D2-36 deep-link helper** — When AppleScript permission is denied, the Wave 5 `PermissionBannerView` button needs to open System Settings → Privacy & Security → Automation. The URL changed in macOS 15 Sequoia, so the helper must try Sequoia → Ventura → root in sequence. Wave 5 (plan 02-10) implements the banner view, but the helper is small enough to ship in Wave 0 alongside the Korean copy. Shipping it now means 02-10 can wire the button straight into a tested API.

## What Shipped

### 1. App/PermissionDeepLink.swift + PermissionDeepLinkTests (Task 1, commits `c400a1f` RED + `dadf6c8` GREEN)

**Helper file** (`App/PermissionDeepLink.swift`):

```swift
enum PermissionDeepLink {
    static let urls: [String] = [
        // macOS 15 Sequoia — extension-model URL
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
        // macOS 14 Sonoma + 13 Ventura — legacy URL
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
        // Final fallback — root Privacy & Security pane (no anchor)
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
    ]

    static func openAutomationPreferences() {
        for s in urls {
            guard let u = URL(string: s) else { continue }
            if NSWorkspace.shared.open(u) { return }
        }
    }
}
```

The minor refactor vs RESEARCH Pattern 12: `urls` is exposed as `static let` (instead of being a function-scope local) so unit tests can assert the list ordering and content independently of `NSWorkspace.shared.open`'s side effect (the latter is a UI session interaction that can only be verified manually during Wave 5 testing).

**Test file** (`ClaudeAlertBotTests/PermissionDeepLinkTests.swift`):

- `test_urlList_matchesD2_36_verbatim` — asserts `PermissionDeepLink.urls.count == 3` and each index equals the exact D2-36 string. Drift in any character of any URL fails the test.
- `test_urlList_allParseAsURL` — every entry parses as a non-nil `URL`. Catches encoding bugs / typos that would silently no-op `openAutomationPreferences()`.

The "actual settings pane opens" path is intentionally NOT tested — `NSWorkspace.shared.open` returns success on URL scheme registration, not on actual pane existence; only Wave 5 manual testing can confirm the correct pane appears for the running OS version.

**TDD cycle observed:**

| Phase | Commit | xcodebuild test result |
|-------|--------|------------------------|
| RED | `c400a1f` | Compile failure — "cannot find 'PermissionDeepLink' in scope" (3 errors) |
| GREEN | `dadf6c8` | `** TEST SUCCEEDED **` — both tests pass in 0.006s |

3 consecutive `xcodebuild test -only-testing:ClaudeAlertBotTests/PermissionDeepLinkTests` runs confirmed stability after the AppDelegate Rule 1 fix landed (see Deviations).

### 2. D2-33 Korean copy locked in App/Info.plist + project.yml (Task 2, commit `cf26d5f`)

**Locked Korean string (verbatim):**

> Claude Alert Bot이 iTerm2의 현재 탭을 확인해서 이미 보고 있는 작업의 알림을 끄고, 클릭 시 정확한 탭으로 이동하기 위해 사용합니다.

This appears in two places — both must match byte-for-byte (PATTERNS.md §project.yml: xcodegen regenerates Info.plist from project.yml on every run; drift means the next `xcodegen generate` silently reverts Info.plist back to whatever project.yml says):

| File | Line | After change |
|------|------|--------------|
| `App/Info.plist` | 26 | `<string>Claude Alert Bot이 iTerm2의 현재 탭을 확인해서 이미 보고 있는 작업의 알림을 끄고, 클릭 시 정확한 탭으로 이동하기 위해 사용합니다.</string>` |
| `project.yml` | 21 | `NSAppleEventsUsageDescription: "Claude Alert Bot이 iTerm2의 현재 탭을 확인해서 이미 보고 있는 작업의 알림을 끄고, 클릭 시 정확한 탭으로 이동하기 위해 사용합니다."` |

`git diff` for this commit was exactly 2 lines changed (+2 / -2) — no other Info.plist key modified, no other project.yml setting touched.

**Anti-regression evidence:**

```bash
$ xcodegen generate
Created project at .../ClaudeAlertBot.xcodeproj
$ /usr/libexec/PlistBuddy -c "Print :NSAppleEventsUsageDescription" App/Info.plist
Claude Alert Bot이 iTerm2의 현재 탭을 확인해서 이미 보고 있는 작업의 알림을 끄고, 클릭 시 정확한 탭으로 이동하기 위해 사용합니다.
$ grep -c '이미 보고 있는' App/Info.plist project.yml
App/Info.plist:1
project.yml:1
```

`xcodegen generate` did not revert the Korean copy → both files match → drift is structurally prevented.

### 3. verify-phase-2.sh row bodies (NOT applied — owned by 02-11)

Per the plan's "owned by 02-11 — this plan only contributes the row body via SUMMARY" directive, the actual `scripts/verify-phase-2.sh` is left untouched. Plan 02-11 (e2e wave) grafts these row bodies into the file. Bodies recorded here for that future executor:

```bash
# Insert under "Wave 0" section in scripts/verify-phase-2.sh, after verify_2_00_02:

# 2-02-01: PermissionDeepLink URL sequence (D2-36) regression guard
verify_2_02_01() {
    local id="2-02-01" name="PermissionDeepLink URL sequence (D2-36)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/PermissionDeepLinkTests \
        > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

# 2-02-02: NSAppleEventsUsageDescription D2-33 Korean copy matches in Info.plist + project.yml
verify_2_02_02() {
    local id="2-02-02" name="NSAppleEventsUsageDescription Korean copy (D2-33) matches in Info.plist + project.yml"
    local expected='이미 보고 있는'  # unique-enough Korean substring
    local plist_val
    plist_val=$(/usr/libexec/PlistBuddy -c "Print :NSAppleEventsUsageDescription" App/Info.plist 2>/dev/null || echo "")
    local yml_val
    yml_val=$(grep -A0 "NSAppleEventsUsageDescription:" project.yml | head -1)
    if [[ "$plist_val" == *"$expected"* && "$yml_val" == *"$expected"* ]]; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "Info.plist=[$plist_val] project.yml=[$yml_val]"
    fi
}
```

Register both in `main()` after `verify_2_00_02`:

```bash
verify_2_02_01
verify_2_02_02
```

## Decisions Made

| ID | Decision | Why |
|----|----------|-----|
| 02-02-D1 | `PermissionDeepLink.urls` is `static let` (publicly readable), not a function-local. | Lets unit tests verify the list independently of `NSWorkspace.shared.open`'s side effect. The cost — `urls` becomes part of the type's API surface — is acceptable because the test guards against silent reordering. |
| 02-02-D2 | verify_2_02_01 + verify_2_02_02 row bodies live in this SUMMARY only; `scripts/verify-phase-2.sh` is untouched. | The plan explicitly assigns ownership of the script to 02-11 (e2e wave) to avoid every plan touching the same file. 02-11 grafts these row bodies in. |
| 02-02-D3 | Fix the Phase 1 `reclaimSocketIfStale` race here (Rule 1) instead of deferring. | Every downstream Phase 2 plan runs `xcodebuild test`, which boots the TEST_HOST app, which traverses `reclaimSocketIfStale`. The unbalanced `dispatch_group_leave()` crash is reproducible (1 of 2 cold starts) and would block every plan's verification rows. Fixing now unblocks all downstream TDD work. |
| 02-02-D4 | Use a `Bool` flag (`leftOnce`) inside the state handler closure instead of a queue-based serialisation primitive. | The handler runs serially on the queue passed to `probe.start(queue:)` — a plain `Bool` flip is race-free in that context. Idempotency is the minimum surgical fix per CLAUDE.md "fix only the offending line". |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] `reclaimSocketIfStale` race: unbalanced `dispatch_group_leave()` crashed the test runner**

- **Found during:** First `xcodebuild test -only-testing:ClaudeAlertBotTests/PermissionDeepLinkTests` after committing the GREEN code. Test runner crashed with: `BUG IN CLIENT OF LIBDISPATCH: Unbalanced call to dispatch_group_leave()`. Reproducible across cold starts (1 of 2 runs crashed).
- **Issue:** Phase 1's `App/AppDelegate.reclaimSocketIfStale` calls `group.leave()` on every `.failed`/`.cancelled`/`.waiting` state transition — but `NWConnection` state handlers are not single-shot. After the function's own `probe.cancel()` fires, the handler can re-enter `.cancelled`, leading to multiple `group.leave()` calls. libdispatch detects this and aborts. 02-00's deviation note documented this as an operational SKIP workaround; with downstream Phase 2 plans now running tests recurrently, the workaround was insufficient.
- **Fix:** Added an idempotent `var leftOnce = false` guard inside the state handler so `group.leave()` fires at most once. The handler is queue-serialised so the plain `Bool` is race-free. 8 lines added to `App/AppDelegate.swift`, no signature change, no behavior change beyond first-leave-wins.
- **Files modified:** `App/AppDelegate.swift`.
- **Commit:** `d5de896` — `fix(02-02): guard reclaimSocketIfStale against double dispatch_group_leave`.
- **Verification:** 3 consecutive `xcodebuild test` runs of `PermissionDeepLinkTests` all `** TEST SUCCEEDED **` (previously coin-flip).

### Authentication Gates

None.

### Out-of-Scope Discoveries (deferred — not fixed)

None.

## Verification Evidence

**Per-task `<verify><automated>` rows:**

| Task | Command | Result |
|------|---------|--------|
| Task 1 (RED) | `xcodebuild test -only-testing:ClaudeAlertBotTests/PermissionDeepLinkTests` | Compile fails (`PermissionDeepLink` not in scope) — confirms RED |
| Task 1 (GREEN, post-Rule-1-fix) | `xcodebuild test -only-testing:ClaudeAlertBotTests/PermissionDeepLinkTests` | `** TEST SUCCEEDED **`, 2/2 passed (test_urlList_matchesD2_36_verbatim, test_urlList_allParseAsURL) |
| Task 2 | `plutil -lint App/Info.plist` | `App/Info.plist: OK` |
| Task 2 | `/usr/libexec/PlistBuddy -c "Print :NSAppleEventsUsageDescription" App/Info.plist` | Korean string verbatim |
| Task 2 | `grep '이미 보고 있는' project.yml` | matched line |
| Task 2 | `xcodegen generate` then re-grep both | Korean copy preserved (anti-regression) |

**Plan-level success criteria:**

| # | Criterion | Status |
|---|-----------|--------|
| 1 | App/Info.plist NSAppleEventsUsageDescription is the D2-33 Korean copy verbatim, validated by plutil | PASS (plutil OK + PlistBuddy reads Korean) |
| 2 | project.yml NSAppleEventsUsageDescription matches App/Info.plist verbatim | PASS (grep matches identical line) |
| 3 | App/PermissionDeepLink.swift exists, compiles, exposes `urls: [String]` (3 entries) and `openAutomationPreferences()` | PASS (file present, builds, both symbols exposed) |
| 4 | PermissionDeepLinkTests has 2 tests, both passing | PASS (xcodebuild TEST SUCCEEDED, 2/2 passed) |
| 5 | scripts/verify-phase-2.sh has rows 2-02-01 and 2-02-02 wired into the main runner; both PASS | NOT APPLICABLE — file owned by 02-11 (D2 in this SUMMARY); row bodies provided here for grafting |

**Sentinel test (02-00 regression check):** `xcodebuild test -only-testing:ClaudeAlertBotTests/ClaudeAlertBotTests/test_targetCompilesAndLinks` → `** TEST SUCCEEDED **` (Phase 1 / 02-00 functionality preserved).

## Threat Surface Scan

Threats from the plan's `<threat_model>`:

- **T-PERM-01 (locked) — mitigated:** D2-33 Korean copy is now in both Info.plist (runtime source) and project.yml (xcodegen source). The string explicitly explains what the permission is for ("이미 보고 있는 작업의 알림을 끄고, 클릭 시 정확한 탭으로 이동"), reducing denial risk per Pitfall #3. Drift between the two files is structurally prevented (Task 2's xcodegen anti-regression test).
- **T-DEEP-LINK-01 — mitigated:** `PermissionDeepLinkTests.test_urlList_matchesD2_36_verbatim` regression-guards the exact 3-URL sequence. Future drift (e.g. someone adds a 4th URL or reorders) fails the test on the next CI / `xcodebuild test` run.

No new trust boundaries introduced. No `threat_flag` rows.

## Self-Check: PASSED

Files claimed:
- `App/PermissionDeepLink.swift` — FOUND
- `ClaudeAlertBotTests/PermissionDeepLinkTests.swift` — FOUND
- `App/Info.plist` — modified (Korean copy verified via PlistBuddy)
- `project.yml` — modified (Korean copy verified via grep)
- `App/AppDelegate.swift` — modified (Rule 1 fix; reclaimSocketIfStale)
- `.planning/phases/02-alert-loop/02-02-SUMMARY.md` — this file

Commits claimed (`git log --oneline -5`):
- `c400a1f` test(02-02): add failing PermissionDeepLink URL list regression test (TDD RED) — FOUND
- `d5de896` fix(02-02): guard reclaimSocketIfStale against double dispatch_group_leave — FOUND
- `dadf6c8` feat(02-02): ship PermissionDeepLink with sequential URL fallback (TDD GREEN) — FOUND
- `cf26d5f` feat(02-02): NSAppleEventsUsageDescription Korean copy per D2-33 — FOUND

## TDD Gate Compliance

Plan-level `tdd="true"` on Task 1 — RED → GREEN gates observed:

1. RED commit (`c400a1f`): `test(02-02): add failing PermissionDeepLink URL list regression test (TDD RED)` — test compiles only when `App/PermissionDeepLink.swift` ships; intervening fail is structural (compile error).
2. GREEN commit (`dadf6c8`): `feat(02-02): ship PermissionDeepLink with sequential URL fallback (TDD GREEN)` — both tests pass.
3. REFACTOR: not needed (helper is 5 lines + 3-string array; no cleanup opportunity that would not regress against the locked URL sequence).

The intervening Rule 1 fix (`d5de896`) is a `fix(...)` not a `feat(...)` and represents a deviation auto-fix, not part of the TDD cycle for the new feature itself.

## Carry-overs / Follow-ups

- **02-10 (Wave 5 SettingsView):** When implementing `PermissionBannerView`, wire the "Open Settings" button straight to `PermissionDeepLink.openAutomationPreferences()` — the helper is now battle-tested via unit tests. RESEARCH Pattern 12's full reference is the production code.
- **02-11 (Wave 6 e2e):** Graft `verify_2_02_01` + `verify_2_02_02` row bodies (above) into `scripts/verify-phase-2.sh`'s "Wave 0" placeholder section, and register them in `main()`.
- **AppDelegate refactor opportunity (low priority, post-MVP):** `reclaimSocketIfStale` would be cleaner as `async/await` with `withCheckedContinuation`, eliminating the `DispatchGroup` entirely. Out of scope for Phase 2 — current fix is minimum-surgical.

---
*Plan: 02-02*
*Phase: 02-alert-loop*
*Closed: 2026-05-08*
