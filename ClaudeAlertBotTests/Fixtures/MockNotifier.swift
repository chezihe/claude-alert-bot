// MockNotifier.swift — Phase 2 Wave 0. Records calls to NotificationOrchestrator-shaped stub.
// Wave 0 ships the *minimum* shape needed for the test target to compile.
// Downstream plans (02-06 NotificationOrchestrator) MAY extend this when the
// orchestrator's protocol is finalized — do NOT remove existing fields, only add.
import Foundation
@testable import ClaudeAlertBot

@MainActor
final class MockNotifier {
    struct PresentCall { let session: String; let playSound: Bool }
    private(set) var presentCalls: [PresentCall] = []
    private(set) var refreshCalls: [Int] = []
    private(set) var refreshQueueCalls: [[String]] = []

    func present(sessionID: String, playSound: Bool) {
        presentCalls.append(.init(session: sessionID, playSound: playSound))
    }

    func refresh(count: Int, completedSessionIDs: [String] = []) {
        refreshCalls.append(count)
        refreshQueueCalls.append(completedSessionIDs)
    }
}
