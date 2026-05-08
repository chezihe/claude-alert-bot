// HookEventFactory.swift — Phase 2 Wave 0. Synthetic HookEvent producers.
// Used by all SessionRegistry / NotificationOrchestrator unit tests in downstream
// plans (02-04 SessionRegistry, 02-06 NotificationOrchestrator, 02-09 GC).
//
// Decoded via JSONDecoder so we exercise the real wire path (HookEvent is
// `Decodable` only — see App/HookEvent.swift).
import Foundation
@testable import ClaudeAlertBot

enum HookEventFactory {
    static func stop(sessionID: String = "test-stop-\(UUID().uuidString)",
                     iTermSessionID: String? = "w0t0p1:TEST-UUID",
                     cwd: String? = "/Users/test/project",
                     ts: String = ISO8601DateFormatter().string(from: Date())) -> HookEvent {
        let json = """
        {"schema_version":1,"event":"stop","session_id":"\(sessionID)","transcript_path":"/tmp/t.jsonl","cwd":"\(cwd ?? "")","iterm_session_id":"\(iTermSessionID ?? "")","tty":"/dev/ttys001","ppid":1234,"claude_project_dir":"\(cwd ?? "")","ts":"\(ts)"}
        """
        return try! JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
    }

    static func userPromptSubmit(sessionID: String,
                                 ts: String = ISO8601DateFormatter().string(from: Date())) -> HookEvent {
        let json = """
        {"schema_version":1,"event":"user_prompt_submit","session_id":"\(sessionID)","transcript_path":"/tmp/t.jsonl","cwd":"/Users/test/project","iterm_session_id":"w0t0p1:TEST-UUID","tty":"/dev/ttys001","ppid":1234,"claude_project_dir":"/Users/test/project","ts":"\(ts)"}
        """
        return try! JSONDecoder().decode(HookEvent.self, from: Data(json.utf8))
    }
}
