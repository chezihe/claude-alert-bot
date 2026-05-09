// HookEventFactory.swift — Phase 2 Wave 0 + Phase 3 Wave 0 extension. Synthetic HookEvent producers.
// Used by all SessionRegistry / NotificationOrchestrator unit tests in downstream
// plans (02-04 SessionRegistry, 02-06 NotificationOrchestrator, 02-09 GC).
//
// Phase 3 Wave 0 (03-00) added an optional `termProgram` parameter to both
// `stop` and `userPromptSubmit`. Default = nil preserves every Phase 2 call
// site verbatim (additive parameter, additive JSON key). When non-nil, the
// `term_program` JSON key is inserted; HookEvent currently ignores unknown
// keys, and 03-02 will add `term_program: String?` to HookEvent so the field
// becomes addressable end-to-end.
//
// Decoded via JSONDecoder so we exercise the real wire path (HookEvent is
// `Decodable` only — see App/HookEvent.swift).
import Foundation
@testable import ClaudeAlertBot

enum HookEventFactory {
    static func stop(sessionID: String = "test-stop-\(UUID().uuidString)",
                     iTermSessionID: String? = "w0t0p1:TEST-UUID",
                     cwd: String? = "/Users/test/project",
                     ts: String = ISO8601DateFormatter().string(from: Date()),
                     termProgram: String? = nil,
                     exitCode: Int? = nil,
                     startedAt: Date? = nil,
                     kind: AlertKind? = nil,
                     lastOutput: String? = nil) -> HookEvent {
        var dict: [String: Any] = [
            "schema_version": 1,
            "event": "stop",
            "session_id": sessionID,
            "transcript_path": "/tmp/t.jsonl",
            "cwd": cwd ?? "",
            "iterm_session_id": iTermSessionID ?? "",
            "tty": "/dev/ttys001",
            "ppid": 1234,
            "claude_project_dir": cwd ?? "",
            "ts": ts
        ]
        if let tp = termProgram { dict["term_program"] = tp }
        if let exitCode { dict["exit_code"] = exitCode }
        if let startedAt { dict["started_at"] = startedAt.timeIntervalSince1970 }
        if let kind { dict["kind"] = kind.rawValue }
        if let lastOutput { dict["last_output"] = lastOutput }
        let data = try! JSONSerialization.data(withJSONObject: dict, options: [])
        return try! JSONDecoder().decode(HookEvent.self, from: data)
    }

    static func userPromptSubmit(sessionID: String,
                                 ts: String = ISO8601DateFormatter().string(from: Date()),
                                 termProgram: String? = nil) -> HookEvent {
        var dict: [String: Any] = [
            "schema_version": 1,
            "event": "user_prompt_submit",
            "session_id": sessionID,
            "transcript_path": "/tmp/t.jsonl",
            "cwd": "/Users/test/project",
            "iterm_session_id": "w0t0p1:TEST-UUID",
            "tty": "/dev/ttys001",
            "ppid": 1234,
            "claude_project_dir": "/Users/test/project",
            "ts": ts
        ]
        if let tp = termProgram { dict["term_program"] = tp }
        let data = try! JSONSerialization.data(withJSONObject: dict, options: [])
        return try! JSONDecoder().decode(HookEvent.self, from: data)
    }
}
