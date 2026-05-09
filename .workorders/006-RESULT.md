## Summary

- Added `CompletedSession.pinned` with default `false`, Codable fallback, and persistence through `SessionStore` migration paths.
- Added `SettingsStore.mutedProjects` JSON/UserDefaults persistence plus `mute`, `unmute`, and `isMuted` helpers.
- Added `SessionRegistry.togglePin`, pinned-preserving `clearAll`, and muted-project drop in stop ingest before enqueue/present.
- Wired popover row context menu callbacks through `PopoverContentView` and `WidgetPopoverController`; pinned rows sort first while preserving stopped-at descending order within groups.
- Added regression tests for pinned Codable/load behavior, mute persistence/boundaries, registry pin/clear/mute behavior, ordering, and row context menu wiring.

## Verification

- RED: targeted WO-006 tests failed before implementation because `SettingsStore.mute/isMuted/unmute/mutedProjects` did not exist.
- Targeted GREEN: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' -derivedDataPath build/DerivedData ...` passed 11 selected WO-006 tests, 0 failures.
- Flake check: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' -only-testing:ClaudeAlertBotTests/SessionRegistryTests/test_injectTest_appendsAndScheduleAutoDismiss` passed after tightening the existing async wait condition.
- Full suite: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` passed 155 tests, 0 failures.
- Build: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` succeeded.
- Diff hygiene: `git diff --check` passed.
- Out-of-scope file check for WO-forbidden paths produced no changes.

## Deviations

- `xcodebuild test` and the canonical Debug build were run outside the sandbox because macOS XCTest requires `testmanagerd`/Xcode services and the canonical build writes to Xcode DerivedData.
- Manual right-click UI verification was not run; coverage is through unit tests and source-level audits for context menu wiring.
- During the first full-suite run, an existing async test observed the registry state before the notifier refresh callback completed. The test was minimally tightened to wait for both queue drain and refresh notification before asserting.
