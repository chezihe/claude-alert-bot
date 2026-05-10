import XCTest
@testable import ClaudeAlertBot

final class SessionRecordTests: XCTestCase {

    func test_completedSession_codableRoundTrip() throws {
        let original = CompletedSession(
            sessionID: "abc-123",
            projectName: "claude_alert_bot",
            stoppedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSec: 45,
            itermSessionID: "w0t0p1:UUID",
            tty: "/dev/ttys001",
            cwd: "/Users/me/proj"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CompletedSession.self, from: data)
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.kind, .success)
        XCTAssertNil(decoded.exitCode)
        XCTAssertNil(decoded.startedAt)
        XCTAssertNil(decoded.lastOutput)

        // optional-nil round-trip
        let nilCase = CompletedSession(
            sessionID: "x",
            projectName: "p",
            stoppedAt: Date(timeIntervalSince1970: 0),
            durationSec: nil,
            itermSessionID: nil,
            tty: nil,
            cwd: nil
        )
        let nilData = try JSONEncoder().encode(nilCase)
        let nilDecoded = try JSONDecoder().decode(CompletedSession.self, from: nilData)
        XCTAssertEqual(nilDecoded, nilCase)
    }

    func test_completedSession_identifiableIDIsUniquePerAlert() {
        let first = CompletedSession(
            sessionID: "same-claude-session",
            projectName: "claude_alert_bot",
            stoppedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSec: 45,
            itermSessionID: nil,
            tty: nil,
            cwd: nil
        )
        let second = CompletedSession(
            sessionID: "same-claude-session",
            projectName: "claude_alert_bot",
            stoppedAt: Date(timeIntervalSince1970: 1_700_000_100),
            durationSec: 30,
            itermSessionID: nil,
            tty: nil,
            cwd: nil
        )

        XCTAssertEqual(first.sessionID, second.sessionID)
        XCTAssertNotEqual(first.id, second.id)
    }

    func test_completedSession_decodesMissingAvailableAsTrue() throws {
        let json = """
        {
          "sessionID": "legacy",
          "projectName": "claude_alert_bot",
          "stoppedAt": "2026-05-09T00:00:00Z",
          "durationSec": 45,
          "itermSessionID": "79C4699F-1234-5678-9ABC-DEF012345678",
          "tty": "/dev/ttys001",
          "cwd": "/Users/me/proj"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(CompletedSession.self, from: json)

        XCTAssertTrue(decoded.available)
        XCTAssertEqual(decoded.kind, .success)
        XCTAssertNil(decoded.exitCode)
        XCTAssertNil(decoded.startedAt)
        XCTAssertNil(decoded.lastOutput)
    }

    func test_completedSession_decodesMissingPinnedAsFalse() throws {
        let json = """
        {
          "sessionID": "legacy-pin",
          "projectName": "claude_alert_bot",
          "stoppedAt": "2026-05-09T00:00:00Z",
          "durationSec": 45,
          "itermSessionID": "79C4699F-1234-5678-9ABC-DEF012345678",
          "tty": "/dev/ttys001",
          "cwd": "/Users/me/proj",
          "available": true
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let decoded = try decoder.decode(CompletedSession.self, from: json)

        XCTAssertFalse(decoded.pinned)
    }

    func test_completedSession_roundTripsPinned() throws {
        let original = CompletedSession(
            sessionID: "pinned",
            projectName: "claude_alert_bot",
            stoppedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSec: 45,
            itermSessionID: nil,
            tty: nil,
            cwd: nil,
            pinned: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CompletedSession.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertTrue(decoded.pinned)
    }

    func test_alertKind_decodesUnknownAsSuccess() throws {
        let decoded = try JSONDecoder().decode(AlertKind.self, from: Data(#""surprise""#.utf8))

        XCTAssertEqual(decoded, .success)
    }

    func test_completedSession_roundTripsExtendedPayloadFields() throws {
        let json = """
        {
          "sessionID": "extended",
          "projectName": "claude_alert_bot",
          "stoppedAt": "2026-05-09T00:00:10Z",
          "durationSec": 45,
          "itermSessionID": "79C4699F-1234-5678-9ABC-DEF012345678",
          "tty": "/dev/ttys001",
          "cwd": "/Users/me/proj",
          "available": true,
          "kind": "waiting",
          "exitCode": 7,
          "startedAt": "2026-05-09T00:00:00Z",
          "lastOutput": "tail output"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601

        let decoded = try decoder.decode(CompletedSession.self, from: json)
        let encoded = try encoder.encode(decoded)
        let roundTripped = try decoder.decode(CompletedSession.self, from: encoded)

        XCTAssertEqual(roundTripped, decoded)
        XCTAssertEqual(roundTripped.kind, .waiting)
        XCTAssertEqual(roundTripped.exitCode, 7)
        XCTAssertEqual(roundTripped.startedAt, ISO8601DateFormatter().date(from: "2026-05-09T00:00:00Z"))
        XCTAssertEqual(roundTripped.lastOutput, "tail output")
    }

    func test_completedSession_capsLastOutputTo4KB() throws {
        let oversized = String(repeating: "x", count: 5_000)
        let session = CompletedSession(
            sessionID: "capped",
            projectName: "claude_alert_bot",
            stoppedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSec: 45,
            itermSessionID: nil,
            tty: nil,
            cwd: nil,
            lastOutput: oversized
        )

        XCTAssertEqual(session.lastOutput?.utf8.count, 4_096)

        let json = """
        {
          "sessionID": "capped-json",
          "projectName": "claude_alert_bot",
          "stoppedAt": "2026-05-09T00:00:10Z",
          "durationSec": 45,
          "available": true,
          "lastOutput": "\(oversized)"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(CompletedSession.self, from: json)

        XCTAssertEqual(decoded.lastOutput?.utf8.count, 4_096)
    }

    func test_sessionsSnapshot_schemaVersion_1() throws {
        let snap = SessionsSnapshot(inFlight: [:], completed: [])
        let data = try JSONEncoder().encode(snap)
        let json = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(json.contains("\"schema\":1"), "expected \"schema\":1 in encoded JSON, got: \(json)")

        // Decoder captures whatever schema is in the JSON (downstream 02-04 owns mismatch handling).
        let v2Json = #"{"schema":2,"inFlight":{},"completed":[]}"#.data(using: .utf8)!
        let v2Decoded = try JSONDecoder().decode(SessionsSnapshot.self, from: v2Json)
        XCTAssertEqual(v2Decoded.schema, 2)
    }

    func test_dedupeKey_hashing() {
        let a = DedupeKey(sessionID: "x", bucketedTS: 100)
        let b = DedupeKey(sessionID: "x", bucketedTS: 100)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)

        var set: Set<DedupeKey> = []
        XCTAssertTrue(set.insert(a).inserted)
        XCTAssertFalse(set.insert(b).inserted)

        // from(sessionID:at:) buckets by /2s.
        let date = Date(timeIntervalSince1970: 200.5)
        let key = DedupeKey.from(sessionID: "y", at: date)
        XCTAssertEqual(key.bucketedTS, 100)  // 200 / 2 = 100
    }

    func test_widgetCorner_rawValue_roundTrip() {
        for corner in WidgetCorner.allCases {
            let rt = WidgetCorner(rawValue: corner.rawValue)
            XCTAssertEqual(rt, corner)
        }
        XCTAssertNil(WidgetCorner(rawValue: "invalid"))
    }

    func test_socketPaths_sessionsJSONPath() {
        XCTAssertTrue(SocketPaths.sessionsJSONPath.hasSuffix("/sessions.json"))
        XCTAssertTrue(SocketPaths.sessionsJSONPath.hasPrefix(SocketPaths.appSupportDir))
    }
}
