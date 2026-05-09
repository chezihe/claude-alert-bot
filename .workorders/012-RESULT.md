# WO-012 Result: Breathe Idle Animation

## Summary
- Added `IdleAnimation` as a small source-level selector with `.bounce`, `.breathe`, and `default = .breathe`.
- Added `MotionTokens.breatheDuration = 2.4`, `breatheScale = 1.06`, and `breatheAnimation(reduceMotion:)`.
- Updated `WidgetIconView` so the default idle animation uses breathe scale, while the existing bounce path remains available.
- Added focused tests for breathe motion tokens, reduce-motion gating, idle animation cases, default selection, and WidgetIconView source wiring.
- Regenerated `ClaudeAlertBot.xcodeproj` with XcodeGen so the new app/test Swift files are included.
- Updated `.workorders/BACKLOG.md` to mark the Breathe animation item complete.

## Verification
- RED: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' -only-testing:ClaudeAlertBotTests/DesignTokensTests/test_motionTokens_breatheDuration_is2_4 -only-testing:ClaudeAlertBotTests/DesignTokensTests/test_motionTokens_breatheScale_is1_06 -only-testing:ClaudeAlertBotTests/DesignTokensTests/test_motionTokens_breatheAnimation_returnsNil_whenReduceMotionIsTrue -only-testing:ClaudeAlertBotTests/DesignTokensTests/test_motionTokens_breatheAnimation_returnsNonNil_whenReduceMotionIsFalse -only-testing:ClaudeAlertBotTests/IdleAnimationTests -derivedDataPath build/DerivedData` failed before implementation because `IdleAnimation` was missing.
- GREEN targeted: same selected tests passed outside the sandbox: 7 tests, 0 failures.
- Full test suite: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' -derivedDataPath build/DerivedData` passed outside the sandbox: 189 tests, 0 failures.
- Debug build: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build -derivedDataPath build/DerivedData` succeeded.

## Deviations
- The first sandboxed targeted GREEN run built successfully but could not communicate with `testmanagerd`; verification was rerun outside the sandbox.
- Manual visual verification of the live 2.4s breathe animation was not run.
- Existing bounce implementation remains offset-only; bounce squash scale stays out of scope per WO-012.

## Suggested Follow-Up WOs
- Add Settings UI for choosing idle animation.
- Add Ring, Roam, Drift, Heart, new-alert pulse, and sonar animations.
- Add Quiet Hours gating for idle animations.
