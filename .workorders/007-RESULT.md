# WO-007 Result: Muted Projects in Settings

## Summary
- Added `MutedProjectsRules` as a Foundation-only pure-function helper for active mute filtering and remaining-time labels.
- Added a conditional Settings section, "Muted Projects", between Widget Position and test controls.
- Each active mute row shows project name, remaining minutes, and a borderless "Unmute" action wired to `SettingsStore.unmute(project:)`.
- Added focused unit tests for mute filtering/label boundaries and Settings source/copy contracts.
- Regenerated `ClaudeAlertBot.xcodeproj` with `xcodegen generate` so the new app/test Swift files are included in targets.

## Verification
- RED: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' -only-testing:ClaudeAlertBotTests/MutedProjectsRulesTests -only-testing:ClaudeAlertBotTests/SettingsViewTests/test_settingsCopy_mutedProjectsSection -only-testing:ClaudeAlertBotTests/SettingsViewTests/test_mutedProjectsSection_usesActiveMutesRule -only-testing:ClaudeAlertBotTests/SettingsViewTests/test_mutedProjectsSection_wiresUnmuteButtonToStore -only-testing:ClaudeAlertBotTests/SettingsViewTests/test_mutedProjectsSection_usesLockedCopy -derivedDataPath build/DerivedData` failed as expected before implementation because `SettingsView.mutedProjectsHeading` and `SettingsView.unmuteButtonLabel` were missing.
- Targeted GREEN: same command passed after implementation: 10 tests, 0 failures.
- Full test suite: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' -derivedDataPath build/DerivedData` passed: 173 tests, 0 failures.
- Debug build: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build -derivedDataPath build/DerivedData` succeeded.

## Deviations
- Used a small `MutedEntry` struct instead of a tuple for `activeMutes` results; this keeps SwiftUI `ForEach(..., id: \.project)` straightforward and stays within the WO allowance.
- Manual Settings window verification was not run in-app.
- No mute expiry pruning, timer/auto-refresh, Settings-side mute creation, duration controls, or popover changes were added.

## Suggested Follow-Up WOs
- Add a lightweight manual/UI verification path for Settings-only sections if screenshot automation becomes useful.
- Reconcile stale backlog rows for WO-006 right-click/mute completion separately from this WO.
