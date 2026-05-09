## Summary

- Added a conditional pinned-row glyph in `PopoverRowView`: `pin.fill`, 11pt, 45 degree rotation, secondary label color, and `Pinned` accessibility label.
- Review follow-up: moved the effective pinned announcement into the parent row `Button` accessibility label because the explicit row label overrides child image labels.
- Placed the glyph directly after the project name and before `Spacer()`, without changing row height, hover, opacity, status dot, time suffix, orphan indicator, click handling, or context menu behavior.
- Added source-level regression tests for the WO-011 pin indicator and row accessibility contracts.
- Updated the Step 4 pin backlog line to note ordering, Clear All preservation, and the visual indicator are complete.

## Verification

- RED: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' -only-testing:ClaudeAlertBotTests/PopoverRowStateTests -derivedDataPath build/DerivedData` failed with the expected three WO-011 assertions before implementation.
- GREEN targeted: same `PopoverRowStateTests` command passed, 8 tests, 0 failures.
- Review RED: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' -only-testing:ClaudeAlertBotTests/PopoverRowStateTests/test_pinnedRowAccessibility_isAnnouncedFromButtonLabel -derivedDataPath build/DerivedData` failed before the row-level accessibility fix.
- Review GREEN targeted: same review test passed, 1 test, 0 failures; `PopoverRowStateTests` passed, 9 tests, 0 failures.
- Full suite: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' -derivedDataPath build/DerivedData` passed, 159 tests, 0 failures.
- Build: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build -derivedDataPath build/DerivedData` succeeded.
- Diff hygiene: `git diff --check` passed.

## Deviations

- The first non-escalated `xcodebuild test` attempt was blocked by sandboxed access to Xcode test services; verification was rerun outside the sandbox.
- The prototype HTML was opened per WO visual-reference guidance, but manual right-click pin/unpin UI verification was not performed in the running app.
