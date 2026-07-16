// MockTerminalJumper.swift — Phase 3 Wave 0 (03-00) → activated by Wave 1 (03-01).
// Test double that records jump calls and replays a configurable JumpResult queue.
//
// History: Wave 0 shipped this file as a compile-gated stub because TerminalJumper
// and JumpResult did not yet exist. Plan 03-01 (Wave 1) created App/TerminalJumper.swift
// and removed the gate, enabling : TerminalJumper conformance — a one-line edit
// matching the same Wave-0/Wave-1 pattern Phase 2 02-00 used for MockNotifier.
//
// Downstream consumers (planned):
//   - 03-05 ITerm2Jumper unit tests (substitute for the real jumper)
//   - 03-07 WidgetPopoverController integration tests
//   - 03-08 SettingsView SET-05 (may borrow as needed)
import Foundation
@testable import ClaudeAlertBot

// 03-01 landed `App/TerminalJumper.swift` (TerminalJumper protocol +
// JumpResult enum). Compile gate removed; `: TerminalJumper` conformance
// enabled. The signature already matches the protocol — no further edits.
@MainActor
final class MockTerminalJumper: TerminalJumper {
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

    /// Reset between tests.
    func reset() {
        resultQueue.removeAll()
        defaultResult = .ok
        jumpCalls.removeAll()
    }
}
