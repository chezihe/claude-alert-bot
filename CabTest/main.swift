// CabTest/main.swift — Sends a synthetic D-08 envelope to the App's socket.
// Used by scripts/verify-phase-1.sh row 1-04-01 as e2e smoke check.
// RESEARCH "Code Examples → Embedded cab-test CLI helper" — verbatim.

import Foundation
import Network

/// Phase 2 — accept `cab-test --event=stop` or `cab-test --event=user_prompt_submit`.
/// Defaults to "stop" preserving Phase 1 behavior.
private func parseEventArg() -> String? {
    for arg in CommandLine.arguments.dropFirst() {
        if arg.hasPrefix("--event=") { return String(arg.dropFirst("--event=".count)) }
    }
    return nil
}

let socketPath = "\(NSHomeDirectory())/Library/Application Support/ClaudeAlertBot/sock"
let payload: [String: Any] = [
    "schema_version": 1,
    "event": parseEventArg() ?? "stop",
    "session_id": "cab-test-\(UUID().uuidString)",
    "transcript_path": NSNull(),
    "cwd": FileManager.default.currentDirectoryPath,
    "iterm_session_id": ProcessInfo.processInfo.environment["ITERM_SESSION_ID"] ?? NSNull(),
    "tty": NSNull(),
    "ppid": Int(getppid()),
    "claude_project_dir": ProcessInfo.processInfo.environment["CLAUDE_PROJECT_DIR"] ?? NSNull(),
    "ts": ISO8601DateFormatter().string(from: Date()),
]

guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []),
      let line = String(data: data, encoding: .utf8) else {
    FileHandle.standardError.write(Data("cab-test: failed to serialize payload\n".utf8))
    exit(2)
}

let conn = NWConnection(to: .unix(path: socketPath), using: NWParameters.tcp)
let group = DispatchGroup()
group.enter()

conn.stateUpdateHandler = { state in
    switch state {
    case .ready:
        let bytes = (line + "\n").data(using: .utf8)!
        conn.send(content: bytes, completion: .contentProcessed { err in
            if let err {
                FileHandle.standardError.write(Data("cab-test: send error \(err)\n".utf8))
            } else {
                print("cab-test: sent \(bytes.count) bytes to \(socketPath)")
            }
            conn.cancel()
            group.leave()
        })
    case .failed(let err):
        FileHandle.standardError.write(Data("cab-test: connect failed: \(err)\n".utf8))
        conn.cancel()
        group.leave()
    default: break
    }
}
conn.start(queue: .global())
_ = group.wait(timeout: .now() + 2.0)
exit(0)
