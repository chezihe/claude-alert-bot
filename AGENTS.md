# Repository Guidelines

## Project Goal & Core Value

Claude Alert Bot is a native macOS app that surfaces a floating Claude-icon widget when a Claude Code session finishes. Clicking the widget jumps to the exact iTerm2 tab/window where that session ran.

**Core value:** "When a long-running Claude Code task finishes while the user is away, they can return to *the exact terminal* without confusion." Notifications that point to the wrong session destroy the value — **session-accurate jump is non-negotiable**.

## Hard Constraints

These are project axioms. Do not propose changes that violate them; if a task seems to require violating one, stop and flag it.

- **Min OS:** macOS 14 Sonoma. Use `MenuBarExtra`, `SMAppService.mainApp`, `Network.framework` UDS as the stable surface.
- **Terminal:** iTerm2 only (MVP scope). Do not add Terminal.app/Warp/Ghostty support.
- **Tech stack:** Swift / SwiftUI + AppKit interop. **Zero external Swift dependencies.** No SwiftPM packages added.
- **No App Sandbox.** Sandboxing breaks Network.framework UDS + AppleScript automation. Do not enable it.
- **Code signing:** Ad-hoc only (`codesign --force --deep --sign -`). No Apple Developer Program. Do not add notarization steps.
- **Hooks required:** Both `Stop` and `UserPromptSubmit` Claude Code hooks. Merge idempotently into `~/.claude/settings.json`.
- **AppleScript permission:** `NSAppleEventsUsageDescription` Info.plist key required for iTerm2 automation.
- **Out of scope:** Sparkle auto-updater, sandboxing, App Store distribution.

## Project Structure & Module Organization

This is a Swift macOS app generated from `project.yml` into `ClaudeAlertBot.xcodeproj`.

- `App/` contains the application source, SwiftUI/AppKit entry points, IPC listener, notification/widget logic, assets, entitlements, and `Info.plist`.
- `ClaudeAlertBotTests/` contains XCTest unit tests, with shared test helpers in `ClaudeAlertBotTests/Fixtures/`.
- `CabTest/` builds the `cab-test` helper tool embedded into the app bundle.
- `Reporter/` contains `cab-report.sh`, the Claude hook reporter script.
- `scripts/` contains build, verification, and local hook-install helpers.
- `.workorders/` holds Work Orders dispatched from Claude → Codex (manual handoff). See `.workorders/README.md`.
- `build/` is generated output and should not be committed.

## Build, Test, and Development Commands

- `xcodegen generate` regenerates `ClaudeAlertBot.xcodeproj` from `project.yml` after target or file-structure changes.
- `xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS'` runs the XCTest suite.
- `xcodebuild -scheme ClaudeAlertBot -configuration Debug build` is the canonical Debug build command (use this in CI/verification scripts).
- `scripts/build.sh` creates an ad-hoc signed release app at `build/export/ClaudeAlertBot.app`.
- `scripts/verify-phase-3.sh` runs the Phase 3 validation harness, including targeted unit and integration checks.
- `scripts/dev-install-hook.sh --apply` installs `Reporter/cab-report.sh` into the user support directory and merges Claude hook settings.

## Tech Stack — USE these

| Concern | Use | Why |
|---|---|---|
| Floating widget | `NSPanel` (subclass) + `NSHostingView`, `level = .floating`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]` | Pure SwiftUI `Window` cannot pin above all spaces |
| Hook → app IPC | Unix domain socket via `Network.framework` (`NWListener` + `NWEndpoint.unix`) | Local, fast, no entitlements, structured JSON |
| iTerm2 control | `NSAppleScript` (compile once, execute many) | Native, in-process, ~10–100× faster than `osascript` subprocess |
| Sound | `AVAudioPlayer` (AVFoundation) | Stable across macOS 14/15/26 |
| Settings UI | SwiftUI `Settings { … }` scene + `@AppStorage` | Standard, zero deps |
| Dock hide | `LSUIElement = true` in Info.plist | Accessory app, invisible until Stop event |
| Build system | Xcode project (`.xcodeproj` via XcodeGen from `project.yml`) | Required for `MenuBarExtra` + asset catalog + Info.plist + signing |

## Tech Stack — AVOID these

| Avoid | Reason |
|---|---|
| `NSSound` | Reported macOS 26 CoreAudio init crashes. Use `AVAudioPlayer`. |
| `ScriptingBridge` for iTerm2 | Header churn across iTerm2 updates; no perf win. Use `NSAppleScript`. |
| `Process` + `osascript` in hot path | ~30–100ms subprocess fork-exec per call. Use `NSAppleScript` compile-once. |
| `XPC`, `DistributedNotifications`, URL scheme as hook→app IPC | Wrong tier or activates the app. Use Unix domain socket. |
| `UNUserNotificationCenter` as **primary** notify | Banners auto-dismiss; violates the persistence requirement. May only be a fallback. |
| App Sandbox | Breaks Network.framework UDS + AppleScript automation. |
| Sparkle, fastlane, notarytool | Out of scope per project decision. |
| External Swift dependencies (SwiftPM packages) | Zero-deps constraint. |
| SwiftUI `Window` scene for floating widget | `collectionBehavior` not exposed; cannot pin across spaces. |

## Code Change Discipline (No Over-Editing)

Apply to every change you make:

- Identify the affected scope and side effects, then make the **minimum** modification needed. Preserve original code and logic as much as possible.
- Before adding a new rule/branch, check whether adjacent code already covers it — strengthen the existing one rather than appending a parallel duplicate.
- **Do not change function signatures, default arguments, or docstrings** unless the task explicitly requires it.
- When fixing a bug, fix only the offending line/block. Do not rewrite the whole function.
- **Do not mix in unrelated refactors, renames, reformatting, or import reordering** in the same change.
- If the diff feels large, stop and verify each change is actually needed.
- If a referenced file/symbol does not match what you expect, ask or stop — do not invent missing pieces.

## Coding Style & Naming Conventions

Use Swift 5 conventions with 4-space indentation. Prefer small, focused types and keep existing file-level phase/context comments when editing nearby logic. Types use `UpperCamelCase`; properties, methods, enum cases, and test methods use `lowerCamelCase`. Preserve existing public/internal signatures unless the change requires a contract update. Avoid broad reformatting, import churn, or unrelated renames.

## Testing Guidelines

Tests use XCTest and `@testable import ClaudeAlertBot`. Place tests beside the behavior they cover using files such as `SessionStoreTests.swift` or `ITerm2JumperTests.swift`; shared fakes belong in `ClaudeAlertBotTests/Fixtures/`. Name tests with `test_...` and encode the behavior plus expected result, for example `test_load_missingFile_returnsNil`. Use temporary files or mocks rather than real `~/Library/Application Support/ClaudeAlertBot` state.

## UI Copy

Widget and popover copy is **minimal English in macOS-system tone**. Use the term **"session"** (not "task" / "job"). Avoid emoji, colored dots as decoration, or marketing-style phrasing. When in doubt, match Apple HIG cadence.

## Commit & Pull Request Guidelines

Recent commits use concise Conventional Commit-style prefixes, often with phase scopes: `refactor(03.1-03): ...`, `docs(phase-03.1): ...`, `chore: ...`, `test(03.1-05): ...`. Keep commits narrow and describe the user-visible or verification-relevant change. When a change comes from a Work Order, reference its number (e.g. `feat(WO-007): ...`). Pull requests should include a summary, tests run, linked issue or phase context when applicable, and screenshots or recordings for UI/widget changes.

## Security & Configuration Tips

Do not commit generated build products, user hook settings, logs, or local app-support data. Be careful around AppleEvents, entitlements, socket paths, file permissions, and hook installation because these affect macOS privacy prompts and local user state.
