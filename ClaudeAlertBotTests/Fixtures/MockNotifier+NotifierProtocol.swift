// MockNotifier+NotifierProtocol.swift — Phase 2 Wave 2 (02-04).
// Extension-only file: adds NotifierProtocol conformance to Wave 0's MockNotifier
// without modifying the original file (file-ownership invariant).
// Wave 0's MockNotifier exposes sessionID/Bool record API; this extension adds the
// typed-CompletedSession protocol surface that SessionRegistryTests needs.
import Foundation
@testable import ClaudeAlertBot

@MainActor
extension MockNotifier: NotifierProtocol {
    func present(session: CompletedSession, playSoundOnce: Bool) async {
        // Forward to the original Wave-0 recording API (sessionID-based).
        present(sessionID: session.sessionID, playSound: playSoundOnce)
    }
    func refreshQueueState(completed: [CompletedSession], count: Int) async {
        refresh(count: count, completedSessionIDs: completed.map(\.sessionID))
    }
}
