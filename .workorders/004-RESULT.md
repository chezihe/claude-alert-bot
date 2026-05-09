## Summary

- Added `AlertKind` and extended `CompletedSession` with `kind`, `exitCode`, `startedAt`, and capped `lastOutput`.
- Extended `HookEvent` decoding for optional `exit_code`, `started_at`, `kind`, and `last_output`, then propagated those values through `SessionRegistry`.
- Updated reporter pass-through for explicit hook payload fields and compatible derived fields without adding `kind` heuristics.
- Added regression coverage for legacy decode fallback, payload round-trip, 4 KB `lastOutput` cap, SessionStore migration preservation, SessionRegistry propagation, and reporter emit/omit behavior.

## Verification

- RED check: targeted WO-004 tests initially failed at compile because `HookEvent` extended fields and `AlertKind` were missing.
- Targeted tests: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' -derivedDataPath build/DerivedData -only-testing:ClaudeAlertBotTests/HookEventTests -only-testing:ClaudeAlertBotTests/SessionRecordTests/test_alertKind_decodesUnknownAsSuccess -only-testing:ClaudeAlertBotTests/SessionRecordTests/test_completedSession_roundTripsExtendedPayloadFields -only-testing:ClaudeAlertBotTests/SessionRecordTests/test_completedSession_capsLastOutputTo4KB -only-testing:ClaudeAlertBotTests/SessionRegistryTests/test_ingest_stop_propagatesExtendedPayloadFields -only-testing:ClaudeAlertBotTests/SessionStoreTests/test_saveAndLoad_roundTrip -only-testing:ClaudeAlertBotTests/SessionStoreTests/test_load_migratesEnvelopeFormatItermID -only-testing:ClaudeAlertBotTests/ReporterScriptTests` -> passed, 12 tests.
- Full tests: `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` -> passed, 142 tests.
- Build: `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` -> passed.
- `git diff --check` -> clean.
- Out-of-scope guard: no changes to `DesignTokens`, `PopoverRowView`, `WidgetPopoverController`, or `PopoverContentView`.

## Deviations

- Xcode test/build commands required running outside the sandbox because `xcodebuild test` needs `testmanagerd` access and canonical build writes to Xcode DerivedData.
- Manual socket injection was not run separately; propagation is covered by `SessionRegistryTests`, and reporter behavior is covered by `ReporterScriptTests`.
