---
phase: 02-alert-loop
plan: 10
status: complete
completed: 2026-05-08
subsystem: ui-settings
tags: [phase-2, wave-5, settings, swiftui, permission-banner, korean-ui, d2-35-path-a, d2-36, set-01, set-02, set-03, set-04]
requirements: [SET-01, SET-02, SET-03, SET-04]
dependency_graph:
  requires:
    - 02-02 (PermissionDeepLink.openAutomationPreferences)
    - 02-03 (SettingsStore.shared @StateObject + WidgetCorner + cornerBinding + applescriptPermission)
    - 02-04 (SessionRegistry.shared.injectTest(soundEnabled:))
    - 02-05 (AppleScriptHelper.shared.triggerPermissionPrompt())
  provides:
    - SettingsView (the SwiftUI view 02-11 places inside `Settings { ... }` scene)
    - PermissionBannerView (denied-state UI + D2-36 deep-link CTA)
    - 10 static-let Korean copy constants locked by 8 unit tests
  affects:
    - Wave 6 plan 02-11 (AppDelegate / scene wiring needs `Settings { SettingsView() }`)
tech_stack:
  added: []     # zero new dependencies
  patterns:
    - "View → Store single-direction (D2-30): SettingsView holds `@StateObject SettingsStore.shared`; never reaches into actors directly except via `Task { await … }`"
    - "Locked-copy regression guard (T-COPY-DRIFT-01 mitigation): all user-visible Korean strings hoisted to `static let` properties on the view types and asserted verbatim in SettingsViewTests"
    - "D2-35 Path A trigger: `.onAppear` → `if store.applescriptPermission == .unknown { Task { await AppleScriptHelper.shared.triggerPermissionPrompt() } }` — fires the TCC dialog when the user has explicitly opened Settings"
key_files:
  created:
    - App/PermissionBannerView.swift
    - App/SettingsView.swift
    - ClaudeAlertBotTests/SettingsViewTests.swift
  modified:
    - ClaudeAlertBot.xcodeproj/project.pbxproj  # xcodegen-regenerated to include the 3 new source files
decisions: []   # plan executed verbatim; no new architectural decisions logged
metrics:
  duration_min: 3
  tasks_completed: 2
  files_created: 3
  commits: 4
  unit_tests_added: 8
  full_target_tests: "79/79 pass (was 71 + 8 new = 79; zero regressions)"
---

# Phase 2 Plan 10: SettingsView + PermissionBannerView Summary

**One-liner:** SwiftUI Settings Form + denied-state yellow banner + D2-35 Path A `.onAppear` permission-prompt trigger; zero external dependencies; 8 Korean copy regression tests.

## What Shipped

Wave 5 ships the entire user-facing settings surface for Phase 2. Two SwiftUI views + one test file. The actual `Settings { SettingsView() }` scene wiring lives in 02-11 (Wave 6).

| File | Role | Status |
|------|------|--------|
| `App/PermissionBannerView.swift` | Yellow-tint denied-state banner; CTA button → `PermissionDeepLink.openAutomationPreferences()` (D2-36) | Created |
| `App/SettingsView.swift` | `Form { Section ×4 + conditional Permission Section }`; D2-35 Path A trigger; D2-21 Test button | Created |
| `ClaudeAlertBotTests/SettingsViewTests.swift` | 8 unit tests — 3 banner-copy + 4 settings-copy + 1 corner-label regression guards | Created |

## Locked Static Copy Constants (translation-pass contract)

These constants are the _single source of truth_ for every user-visible string in the Settings + Permission Banner UI. Future translation passes must update both the constant and the matching test assertion. Drift is caught immediately on the next CI run via `SettingsViewTests`.

### `PermissionBannerView` (3 strings — App/PermissionBannerView.swift)
| Constant | Value |
|----------|-------|
| `PermissionBannerView.headlineCopy` | `"자동화 권한이 꺼져 있어요"` |
| `PermissionBannerView.bodyCopy` | `"이미 보고 있는 터미널에서도 알림이 뜰 수 있습니다."` |
| `PermissionBannerView.buttonCopy` | `"시스템 설정 열기"` |

### `SettingsView` (10 strings — App/SettingsView.swift)
| Constant | Value |
|----------|-------|
| `SettingsView.thresholdHeading` | `"알림 임계값"` |
| `SettingsView.thresholdCaption` | `"이 시간 이상 걸린 작업만 알려요"` |
| `SettingsView.soundHeading` | `"사운드"` |
| `SettingsView.soundToggleLabel` | `"알림 사운드 재생"` |
| `SettingsView.widgetPositionHeading` | `"위젯 위치"` |
| `SettingsView.cornerLabel` | `"코너"` |
| `SettingsView.offsetXLabel` | `"가로 오프셋"` |
| `SettingsView.offsetYLabel` | `"세로 오프셋"` |
| `SettingsView.testHeading` | `"테스트"` |
| `SettingsView.testButtonLabel` | `"테스트 알림 보내기"` |

### `WidgetCorner.localizedLabel` (4 strings — already locked in Wave 1, App/SessionRecord.swift)
The corner Picker reads these via `WidgetCorner.allCases.map(\.localizedLabel)` → `["왼쪽 위", "오른쪽 위", "왼쪽 아래", "오른쪽 아래"]`. Wave 5's `test_widgetCornerLabels_4Korean` re-asserts the order from this plan's perspective so a future Wave-1 refactor that reorders `CaseIterable` cases is caught here too.

## D2-35 Path A — Wired

```swift
.onAppear {
    if store.applescriptPermission == .unknown {
        Task { await AppleScriptHelper.shared.triggerPermissionPrompt() }
    }
}
```

This is the canonical Path A trigger anchor. The anchor `triggerPermissionPrompt` lives in `App/SettingsView.swift` exactly once (`grep -c 'triggerPermissionPrompt' App/SettingsView.swift` → 1) — the Phase 2 verifier may grep this literal as a regression guard. Path B (first Stop hook) already lives in `SessionRegistry` and is unchanged.

## D2-21 Test Button — Wired

```swift
Button(Self.testButtonLabel) {
    Task { await SessionRegistry.shared.injectTest(soundEnabled: store.soundEnabled) }
}
.buttonStyle(.borderedProminent)
.frame(maxWidth: .infinity)
```

The button reads `store.soundEnabled` at click time and forwards it to the actor — the in-memory injection walks the standard alert path (widget + sound + popover) without persisting (D2-22). 30s auto-dismiss is enforced inside `SessionRegistry.injectTest` itself, not here.

## Wave 6 (02-11) Wiring Requirement

`main.swift` (or the App body / AppDelegate alternative — 02-11 decides) MUST host the SwiftUI Settings scene:

```swift
// In the App's Scene composition:
Settings {
    SettingsView()
}
```

This is the only thing Wave 6 needs to do for the Settings surface — the view itself wires its own dependencies via the singletons `SettingsStore.shared`, `SessionRegistry.shared`, `AppleScriptHelper.shared`, and `PermissionDeepLink` (static).

The standard `⌘,` keyboard shortcut is automatic via SwiftUI's `Settings` scene; no `KeyboardShortcuts` import needed (D2-29 zero-deps invariant preserved).

## Verifier Row Body (for 02-11 to graft into scripts/verify-phase-2.sh)

```bash
verify_2_10_01() {
    local id="2-10-01" name="SettingsView + PermissionBanner copy regression (D2-33, D2-36)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/SettingsViewTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}
```

This single row covers all 8 SettingsViewTests in one xctest invocation (3 banner + 5 settings).

### Wave 6 e2e row anchors still owned by 02-11
- **SC#4 settings persistence (SET-03):** write a value via xctest helper → terminate app → relaunch → read value. Owned by 02-11 — this plan's tests are pure copy/structure assertions (no UserDefaults round-trip), so 02-11's e2e row still proves SET-03 end-to-end.
- **SET-04 e2e (manual checkpoint):** click Test button in real app → verify widget appears → verify auto-dismiss after 30s. Owned by 02-11's manual checkpoint script.

## Verification Grep Guards (passing as of this commit)

| # | Anchor | File | Count |
|---|--------|------|-------|
| 3 | `자동화 권한이 꺼져 있어요` | `App/PermissionBannerView.swift` | 1 |
| 4 | `테스트 알림 보내기` | `App/SettingsView.swift` | 1 |
| 5 | `triggerPermissionPrompt` | `App/SettingsView.swift` | 1 |
| 6 | `SessionRegistry.shared.injectTest` | `App/SettingsView.swift` | 2 (one in `// D2-21:` doc comment + one call site) |

All ≥ 1. Plan verification ✓.

## Threat Mitigations Confirmed

| Threat ID | Disposition | Where Implemented |
|-----------|-------------|-------------------|
| T-INPUT-01 | accept | Stepper UI clamps thresholdSeconds to 5...600 and offsets to 0...64 — out-of-range UserDefaults shell-injection is a tampered-defaults concern only, accepted per plan. |
| T-PERM-TRIGGER-01 | mitigate | D2-35 Path A wired via `.onAppear` (this plan); Path B (first Stop) wired in 02-04; Wave 6 manual checkpoint verifies both paths surface the dialog. |
| T-COPY-DRIFT-01 | mitigate | 13 static-let constants (3 banner + 10 settings) + 8 unit tests asserting verbatim Korean. Drift = test fails on next CI run. |

## Atomic Commits

| Commit | Type | Scope |
|--------|------|-------|
| `6b7a716` | test | RED — failing PermissionBannerView copy tests |
| `99b64e7` | feat | GREEN — PermissionBannerView SwiftUI denied-state banner |
| `40aa803` | test | RED — failing SettingsView copy + corner-label tests |
| `f44a27b` | feat | GREEN — SettingsView Form + D2-35 Path A + Test button |

## Notable Deviations

None. Plan executed verbatim across both tasks. The action templates were copy-pasted into the corresponding files with zero structural edits beyond what the action block specified.

## Self-Check: PASSED

- [x] App/PermissionBannerView.swift exists (FOUND)
- [x] App/SettingsView.swift exists (FOUND)
- [x] ClaudeAlertBotTests/SettingsViewTests.swift exists (FOUND)
- [x] Commit 6b7a716 exists (FOUND)
- [x] Commit 99b64e7 exists (FOUND)
- [x] Commit 40aa803 exists (FOUND)
- [x] Commit f44a27b exists (FOUND)
- [x] `xcodebuild build -scheme ClaudeAlertBot` succeeds (BUILD SUCCEEDED)
- [x] `xcodebuild test -scheme ClaudeAlertBot` 79/79 pass (was 71 + 8 new = 79; zero regressions)
- [x] 8/8 SettingsViewTests pass
- [x] All 4 verification grep guards return ≥ 1
- [x] No external SwiftUI/Settings dependencies introduced (D2-29 zero-deps invariant preserved)

## Next

Wave 6 plan 02-11 — AppDelegate boot wiring + the actual `Settings { SettingsView() }` scene mount + Pitfall #11 boot order (`restore()` before `listener.start()`) + retain WidgetPopoverController + WakeObserver + WorkspaceFrontmostObserver + SessionGCTimer as stored properties on AppDelegate. After 02-11, Phase 2 closes and `verify-phase-2.sh` grafts the row body above.
