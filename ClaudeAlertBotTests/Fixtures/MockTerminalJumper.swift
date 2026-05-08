// MockTerminalJumper.swift — Phase 3 Wave 0 (03-00).
// Test double that records jump calls and replays a configurable JumpResult queue.
//
// Wave 0 ships this file as a *compile-gated* stub. The class body is wrapped in
// `#if false` because the types it depends on (`TerminalJumper` protocol,
// `JumpResult` enum, `CompletedSession` model) do not yet exist — plan 03-01
// (Wave 1) creates them in App/TerminalJumper.swift. After 03-01 lands, the
// executor of Task 1 (final step) removes the `#if false` / `#endif` lines and
// adds the `: TerminalJumper` conformance — a one-line edit.
//
// This is the same Wave-0 / Wave-1 sequencing pattern Phase 2 02-00 used for
// MockNotifier+NotifierProtocol.swift (which 02-06 later wired up).
//
// Downstream consumers (planned):
//   - 03-05 ITerm2Jumper unit tests (substitute for the real jumper)
//   - 03-07 WidgetPopoverController integration tests
//   - 03-08 SettingsView SET-05 (may borrow as needed)
import Foundation
@testable import ClaudeAlertBot

// COMPILE GATE — flip to `#if true` (or delete the gate) after 03-01 lands
// `App/TerminalJumper.swift` (declares `TerminalJumper`, `JumpResult`, and
// confirms `CompletedSession` shape).
#if false

@MainActor
final class MockTerminalJumper {
    /// FIFO of pre-loaded results. Each call dequeues the head; if empty, returns `defaultResult`.
    var resultQueue: [JumpResult] = []

    /// Returned when resultQueue is empty.
    var defaultResult: JumpResult = .ok

    /// Records every (sessionID, itermSessionID) pair the controller asked us to jump to.
    private(set) var jumpCalls: [(sessionID: String, itermSessionID: String?)] = []

    /// The protocol's call shape (forward-spec from 03-01).
    /// Plan 03-01 prepends `: TerminalJumper` conformance — same signature so the
    /// conformance line is a no-op edit.
    func jump(to session: CompletedSession) async -> JumpResult {
        jumpCalls.append((sessionID: session.sessionID, itermSessionID: session.itermSessionID))
        if resultQueue.isEmpty { return defaultResult }
        return resultQueue.removeFirst()
    }

    /// Convenience for tests that want to assert the last call without index math.
    var lastCall: (sessionID: String, itermSessionID: String?)? { jumpCalls.last }

    /// Reset between tests.
    func reset() {
        resultQueue.removeAll()
        defaultResult = .ok
        jumpCalls.removeAll()
    }
}

#endif
