# WO-002 Result

## Summary
- Added `CompletedSession.available` with legacy decode fallback to `true`.
- Mark missing iTerm session jump results unavailable instead of removing the completed row.
- Added status-dot rendering, unavailable row opacity, and hover/status-dot tokens in `DesignTokens`.

## Verification
- `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` - passed.
- Direct `xcrun xctest` for the six added/targeted tests - passed.
- Direct `env CI=1 xcrun xctest .../ClaudeAlertBotTests.xctest` - passed, 129 tests with 1 documented AVAudio skip.
- Direct `xcrun xctest .../ClaudeAlertBotTests.xctest` without `CI=1` - failed one existing `SoundPlayerTests` AVAudio playback assertion; no WO-002 tests failed.
- `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` - blocked by a live release app already owning `/Users/choijihye/Library/Application Support/ClaudeAlertBot/sock`; the test host exits during app bootstrap with `Address already in use`.

## Deviations
- Did not stop the live release app to run the canonical full XCTest suite.
- Used direct `xcrun xctest` to verify the new unit coverage without launching the app delegate.
