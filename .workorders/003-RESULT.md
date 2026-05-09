## Summary

- Added injectable `UserDefaults` support to `SettingsStore` and covered `widgetCorner` default/persistence with tests.
- Updated the Settings widget-position section to use minimal English labels and four English corner options.
- Added `FloatingWidgetWindowController` observation of settings changes so a visible widget repositions immediately when the selected corner changes.
- Regenerated `ClaudeAlertBot.xcodeproj` with XcodeGen so the new test files are part of the test target.

## Verification

- RED check: targeted WO-003 tests initially failed because `SettingsView.widgetCornerLabel` did not exist.
- Targeted tests: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:ClaudeAlertBotTests/SettingsStoreTests -only-testing:ClaudeAlertBotTests/SettingsViewTests/test_settingsCopy_widgetPositionSection -only-testing:ClaudeAlertBotTests/SettingsViewTests/test_widgetCornerLabels_4English -only-testing:ClaudeAlertBotTests/FloatingWidgetWindowControllerTests/test_visibleWidgetRepositionsWhenWidgetCornerChanges` — passed, 5 tests.
- Full tests: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` — passed, 132 tests.
- Build: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` — passed.

## Deviations

- The first sandboxed `xcodebuild test` attempt could not communicate with macOS `testmanagerd`; verification was rerun outside the sandbox.
- An already-running ClaudeAlertBot instance held the Unix-domain socket during early test attempts, so it was terminated before the successful test run.
- Existing offset controls and safe-area clamping were retained. Defaults still provide the WO-required 16pt inset.
- Manual visual verification was not run; live reposition behavior is covered by `FloatingWidgetWindowControllerTests`.
