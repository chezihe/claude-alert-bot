---
phase: 02-alert-loop
plan: 03
status: complete
completed: 2026-05-08
requirements: [SESS-01, SESS-02, SESS-03, THR-01, AUD-01, AUD-02, SET-01, SET-02, SET-03, WIDG-06, WIDG-07]
---

# Plan 02-03 SUMMARY — Type Contracts

## What Shipped

Wave 1 type contracts for Phase 2. Five files (4 new + 1 extended) + 2 unit-test files. All Codable / @MainActor. No view code, no observers, no I/O — pure types ready for Wave 2+ implementations.

| File | Role | Status |
|------|------|--------|
| `App/SessionRecord.swift` | Codable models (InFlightStart, CompletedSession, DedupeKey, WidgetCorner, PermissionStatus, SessionsSnapshot) | Created |
| `App/SettingsStore.swift` | @MainActor ObservableObject singleton (RESEARCH Pattern 4) | Created |
| `App/ProjectName.swift` | D2-06 cwd-basename helper | Created |
| `App/SocketPaths.swift` | Extended with `sessionsJSONPath` (single namespace, PATTERNS §3) | Modified |
| `ClaudeAlertBotTests/SessionRecordTests.swift` | 5 cases: round-trip, schema, dedupe, corner, path | Created |
| `ClaudeAlertBotTests/ProjectNameTests.swift` | 5 cases: cwd-preferred, fallback, trailing slash, root, both-nil | Created |

## Final Field Shapes (downstream contract — do not re-read source)

```swift
struct InFlightStart: Codable, Equatable {
    let startedAt: Date
    let cwd: String?
}

struct CompletedSession: Codable, Equatable, Identifiable {
    let sessionID: String
    let projectName: String
    let stoppedAt: Date
    let durationSec: Int?            // nil iff THR-02 fallback (start missing)
    let itermSessionID: String?
    let tty: String?
    let cwd: String?
    var id: String { sessionID }
    static func testFixture() -> CompletedSession  // D2-21
}

struct DedupeKey: Hashable, Codable {
    let sessionID: String
    let bucketedTS: Int              // Int(ts.timeIntervalSince1970) / 2
    static func from(sessionID:at:) -> DedupeKey
}

enum WidgetCorner: String, CaseIterable, Codable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var localizedLabel: String { ... }   // 한국어 4-corner labels
}

enum PermissionStatus: String, Codable { case unknown, granted, denied }

struct SessionsSnapshot: Codable {
    var schema: Int = 1                  // currentSchema = 1
    var inFlight: [String: InFlightStart]
    var completed: [CompletedSession]
}
```

## SettingsStore — UserDefaults Keys (Phase 2 invariants)

| Key | Type | Default | Locked by |
|-----|------|---------|-----------|
| `threshold_seconds` | Int | 30 | THR-01 / ROADMAP |
| `sound_enabled` | Bool | true | AUD-02 |
| `widget_corner` | String | "topRight" | D2-26 |
| `widget_offset_x` | Int | 16 | D2-27 |
| `widget_offset_y` | Int | 16 | D2-27 |
| `applescript_permission` | String | "unknown" | D2-35/D2-36 (written via @Published, not @AppStorage) |

Single-direction rule preserved: SettingsStore has zero references to SessionRegistry / NotificationOrchestrator / any actor. Wave 2+ callers read on MainActor and pass values into actor methods as call arguments (RESEARCH Pattern 4).

## ProjectName.derive Tie-breaking Rule

`cwd` wins when present; falls back to `claude_project_dir` basename; sentinel `"unknown"` when both nil. Trailing slashes stripped. Root path `/` returns `/`.

## SocketPaths Extension

Added one line under existing `logsDir` constant:
```swift
static let sessionsJSONPath: String = "\(appSupportDir)/sessions.json"
```
No parallel namespace introduced. Phase 1 lines unchanged byte-for-byte.

## Verifier Row Bodies (for 02-11 to graft into scripts/verify-phase-2.sh)

```bash
verify_2_03_01() {
    local id="2-03-01" name="SessionRecord Codable round-trip + DedupeKey hashing + SocketPaths.sessionsJSONPath"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/SessionRecordTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}

verify_2_03_02() {
    local id="2-03-02" name="ProjectName.derive rules (D2-06)"
    if xcodebuild test -scheme ClaudeAlertBot -destination 'platform=macOS' \
        -only-testing:ClaudeAlertBotTests/ProjectNameTests > /tmp/cab-test-out.log 2>&1; then
        _record_pass "$id" "$name"
    else
        _record_fail "$id" "$name" "see /tmp/cab-test-out.log"
    fi
}
```

## Self-Check: PASSED

- [x] App/SessionRecord.swift compiles (5/5 SessionRecordTests pass: round-trip, schema=1, dedupe hashing+bucketing, corner rawValue, sessionsJSONPath shape)
- [x] App/ProjectName.swift compiles (5/5 ProjectNameTests pass)
- [x] App/SettingsStore.swift compiles (no SessionRegistry/Orchestrator imports — single-direction)
- [x] App/SocketPaths.swift extended (1 line added, no parallel namespace, Phase 1 lines byte-identical via `git diff`)
- [x] xcodebuild build -scheme ClaudeAlertBot succeeds
- [x] No regression on Phase 1 / 02-00 / 02-02 tests
- [x] Atomic commits: f45b37c (Task 1) + 8fe44d1 (Task 2)

## Notable Deviations

None. Inline executor (orchestrator-direct, after two consecutive subagent stream-idle timeouts) followed plan verbatim.

## Key Files

- `/Users/choijihye/Study/source/claude_alert_bot/App/SessionRecord.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/App/SettingsStore.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/App/ProjectName.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/App/SocketPaths.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/ClaudeAlertBotTests/SessionRecordTests.swift`
- `/Users/choijihye/Study/source/claude_alert_bot/ClaudeAlertBotTests/ProjectNameTests.swift`

## Next

Wave 1 plan 02-01 (NSPopover hands-on spike) is a checkpoint requiring user action on the dev machine. After that resolves (Pattern 8 vs 8a topology choice), Wave 2 plans 02-04 (SessionRegistry actor + SessionStore persistence) and 02-05 (AppleScriptHelper actor) can run — both implement against contracts defined here.
