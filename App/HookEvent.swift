// App/HookEvent.swift — D-08 envelope schema (10 fields, schema_version=1).
// Locked for Phase 2 to consume; Phase 1 only decodes/logs.
// RESEARCH Pitfall #11: stop_hook_active is NOT in current Claude Code docs — do NOT add it.
// RESEARCH Open Question 4: keep `event` as String (not enum) so Phase 2's UserPromptSubmit
//   ingestion does not require a struct change.
import Foundation

struct HookEvent: Decodable {
    let schema_version: Int
    let event: String                      // "stop" | "user_prompt_submit" | "notification" | "question_answered"
    let session_id: String?
    let transcript_path: String?
    let cwd: String?
    let iterm_session_id: String?
    let tty: String?
    let ppid: Int?
    let claude_project_dir: String?
    let ts: String?
    let term_program: String?              // D3-05 — $TERM_PROGRAM capture; v1 unused, v2 dispatch key (MTERM-01..04).
    let exit_code: Int?
    let started_at: Date?
    let kind: AlertKind?
    let last_output: String?

    enum CodingKeys: String, CodingKey {
        case schema_version
        case event
        case session_id
        case transcript_path
        case cwd
        case iterm_session_id
        case tty
        case ppid
        case claude_project_dir
        case ts
        case term_program
        case exit_code
        case started_at
        case kind
        case last_output
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schema_version = try container.decode(Int.self, forKey: .schema_version)
        self.event = try container.decode(String.self, forKey: .event)
        self.session_id = try container.decodeIfPresent(String.self, forKey: .session_id)
        self.transcript_path = try container.decodeIfPresent(String.self, forKey: .transcript_path)
        self.cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        self.iterm_session_id = try container.decodeIfPresent(String.self, forKey: .iterm_session_id)
        self.tty = try container.decodeIfPresent(String.self, forKey: .tty)
        self.ppid = try container.decodeIfPresent(Int.self, forKey: .ppid)
        self.claude_project_dir = try container.decodeIfPresent(String.self, forKey: .claude_project_dir)
        self.ts = try container.decodeIfPresent(String.self, forKey: .ts)
        self.term_program = try container.decodeIfPresent(String.self, forKey: .term_program)
        self.exit_code = try? container.decodeIfPresent(Int.self, forKey: .exit_code)
        if let started = try? container.decodeIfPresent(Double.self, forKey: .started_at) {
            self.started_at = Date(timeIntervalSince1970: started)
        } else {
            self.started_at = nil
        }
        self.kind = try? container.decodeIfPresent(AlertKind.self, forKey: .kind)
        self.last_output = LastOutputLimiter.capped(try? container.decodeIfPresent(String.self, forKey: .last_output))
    }
}
