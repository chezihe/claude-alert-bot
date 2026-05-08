// App/HookEvent.swift — D-08 envelope schema (10 fields, schema_version=1).
// Locked for Phase 2 to consume; Phase 1 only decodes/logs.
// RESEARCH Pitfall #11: stop_hook_active is NOT in current Claude Code docs — do NOT add it.
// RESEARCH Open Question 4: keep `event` as String (not enum) so Phase 2's UserPromptSubmit
//   ingestion does not require a struct change.
import Foundation

struct HookEvent: Decodable {
    let schema_version: Int
    let event: String                      // "stop" | "user_prompt_submit"
    let session_id: String?
    let transcript_path: String?
    let cwd: String?
    let iterm_session_id: String?
    let tty: String?
    let ppid: Int?
    let claude_project_dir: String?
    let ts: String?
    let term_program: String?              // D3-05 — $TERM_PROGRAM capture; v1 unused, v2 dispatch key (MTERM-01..04).
}
