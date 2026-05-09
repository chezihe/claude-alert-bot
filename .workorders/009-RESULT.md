# WO-009 Result: Popover Dimensions, Empty State, and Header Gear

## Summary
- Reconciled popover geometry to 270pt width and a 4-row visible cap through `GeometryTokens`.
- Added `EmptyStateView` with "Listening for Claude sessions" and rendered it whenever the queue is empty.
- Made the popover header always visible, kept "모두 지우기" conditional, and added a trailing `gearshape` Settings button.
- Wired the Settings gear through `WidgetPopoverController` and tokenized popover sizing, including the empty-state height.
- Updated `SPEC.md` geometry and WO backlog entries for the completed popover items.

## Verification
- RED: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' -only-testing:ClaudeAlertBotTests/DesignTokensTests/test_geometryTokens_popoverWidth_is270_perSpec -only-testing:ClaudeAlertBotTests/DesignTokensTests/test_geometryTokens_popoverMaxVisibleRows_is4_perFeaturesSpec -only-testing:ClaudeAlertBotTests/PopoverContentTests/test_popoverContentView_rendersEmptyStateWhenQueueIsEmpty -only-testing:ClaudeAlertBotTests/PopoverContentTests/test_popoverContentView_alwaysRendersHeaderWithSettingsGear -only-testing:ClaudeAlertBotTests/PopoverContentTests/test_widgetPopoverController_sizingUsesPopoverGeometryTokens -only-testing:ClaudeAlertBotTests/PopoverContentTests/test_widgetPopoverController_wiresOpenSettingsCallback -derivedDataPath build/DerivedData` failed as expected before implementation: 6 tests, 14 failures.
- GREEN targeted: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' -only-testing:ClaudeAlertBotTests/DesignTokensTests/test_geometryTokens_popoverWidth_is270_perSpec -only-testing:ClaudeAlertBotTests/DesignTokensTests/test_geometryTokens_popoverMaxVisibleRows_is4_perFeaturesSpec -only-testing:ClaudeAlertBotTests/EmptyStateViewTests -only-testing:ClaudeAlertBotTests/PopoverContentTests/test_popoverContentView_rendersEmptyStateWhenQueueIsEmpty -only-testing:ClaudeAlertBotTests/PopoverContentTests/test_popoverContentView_alwaysRendersHeaderWithSettingsGear -only-testing:ClaudeAlertBotTests/PopoverContentTests/test_widgetPopoverController_sizingUsesPopoverGeometryTokens -only-testing:ClaudeAlertBotTests/PopoverContentTests/test_widgetPopoverController_wiresOpenSettingsCallback -derivedDataPath build/DerivedData` passed: 11 tests, 0 failures.
- Full test suite: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' -derivedDataPath build/DerivedData` passed: 182 tests, 0 failures.
- Debug build: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build -derivedDataPath build/DerivedData` succeeded.

## Deviations
- Did not add `everHadAlerts`; empty state is intentionally shown for any empty queue per WO-009.
- Did not run manual in-app click/screenshot verification for the popover gear or empty state.
- Kept the existing `.thinMaterial`, row styling, dismiss policy, MenuBarExtra Settings entry, and "모두 지우기" copy unchanged.

## Suggested Follow-Up WOs
- Add `everHadAlerts` persistence if onboarding should only appear before the first alert.
- Add a manual UI verification path for popover screenshots and Settings-window opening.
