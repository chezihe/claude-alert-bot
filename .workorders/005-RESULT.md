## Summary

- Added `ColorTokens.statusDot(for:)` to map `AlertKind.success/error/waiting` to the existing status color tokens.
- Updated `PopoverRowView.statusDot` so available rows use `fill(dotColor)` and unavailable rows keep the hollow `stroke(dotColor, lineWidth: GeometryTokens.statusDotRingStroke)` path.
- Added tests for the kind-to-color mapping and the available/unavailable row rendering contract.

## Verification

- RED: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:ClaudeAlertBotTests/DesignTokensTests/test_colorTokens_statusDotMapsAlertKindToStatusColors -only-testing:ClaudeAlertBotTests/PopoverRowStateTests/test_statusDot_usesAlertKindColorForFillAndUnavailableRing` failed because `ColorTokens.statusDot(for:)` did not exist.
- GREEN targeted: same command passed, 2 tests, 0 failures.
- Full tests: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` passed, 144 tests, 0 failures.
- Build: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` passed.
- Diff hygiene: `git diff --check` passed.

## Deviations

- `xcodebuild test` and the canonical build were run outside the sandbox because XCTest needs `testmanagerd` access and the canonical build writes to Xcode DerivedData.
- Manual visual injection was not run; the behavior is covered by pure color mapping tests plus source-level row rendering audit, as allowed by the WO.
