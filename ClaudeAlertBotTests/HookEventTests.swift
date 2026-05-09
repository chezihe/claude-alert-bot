import XCTest
@testable import ClaudeAlertBot

final class HookEventTests: XCTestCase {
    func test_decodesExtendedPayloadFields() throws {
        let json = """
        {
          "schema_version": 1,
          "event": "stop",
          "session_id": "sid-extended",
          "transcript_path": "/tmp/transcript.jsonl",
          "cwd": "/tmp/project",
          "iterm_session_id": "w0t0p1:79C4699F-1234-5678-9ABC-DEF012345678",
          "tty": "/dev/ttys001",
          "ppid": 1234,
          "claude_project_dir": "/tmp/project",
          "ts": "2026-05-09T00:00:10Z",
          "term_program": "iTerm.app",
          "exit_code": 2,
          "started_at": 1730000000.5,
          "kind": "error",
          "last_output": "tail output"
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(HookEvent.self, from: json)

        XCTAssertEqual(event.exit_code, 2)
        XCTAssertEqual(event.started_at, Date(timeIntervalSince1970: 1_730_000_000.5))
        XCTAssertEqual(event.kind, .error)
        XCTAssertEqual(event.last_output, "tail output")
    }

    func test_decodesLegacyPayloadExtendedFieldsAsNil() throws {
        let json = """
        {
          "schema_version": 1,
          "event": "stop",
          "session_id": "sid-legacy",
          "transcript_path": "/tmp/transcript.jsonl",
          "cwd": "/tmp/project",
          "iterm_session_id": "w0t0p1:79C4699F-1234-5678-9ABC-DEF012345678",
          "tty": "/dev/ttys001",
          "ppid": 1234,
          "claude_project_dir": "/tmp/project",
          "ts": "2026-05-09T00:00:10Z",
          "term_program": "iTerm.app"
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(HookEvent.self, from: json)

        XCTAssertNil(event.exit_code)
        XCTAssertNil(event.started_at)
        XCTAssertNil(event.kind)
        XCTAssertNil(event.last_output)
    }

    func test_decodesStartedAtIntegerEpoch() throws {
        let json = """
        {
          "schema_version": 1,
          "event": "stop",
          "session_id": "sid-int",
          "ts": "2026-05-09T00:00:10Z",
          "started_at": 1730000000
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder().decode(HookEvent.self, from: json)

        XCTAssertEqual(event.started_at, Date(timeIntervalSince1970: 1_730_000_000))
    }
}
