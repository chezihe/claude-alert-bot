import XCTest

final class ReporterScriptTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("cab-reporter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempHome {
            try? FileManager.default.removeItem(at: tempHome)
        }
        tempHome = nil
    }

    func test_reporterPassesThroughOptionalExtendedFields() throws {
        let envelope = try runReporter(stdin: """
        {
          "session_id": "sid-reporter",
          "cwd": "/tmp/project",
          "exit_code": 2,
          "started_at": 1730000000.5,
          "kind": "waiting",
          "last_output": "tail output"
        }
        """)

        XCTAssertEqual(envelope["exit_code"] as? Int, 2)
        XCTAssertEqual(envelope["started_at"] as? Double, 1_730_000_000.5)
        XCTAssertEqual(envelope["kind"] as? String, "waiting")
        XCTAssertEqual(envelope["last_output"] as? String, "tail output")
    }

    func test_reporterOmitsMissingOptionalExtendedFields() throws {
        let envelope = try runReporter(stdin: #"{"session_id":"sid-reporter","cwd":"/tmp/project"}"#)

        XCTAssertNil(envelope["exit_code"])
        XCTAssertNil(envelope["started_at"])
        XCTAssertNil(envelope["kind"])
        XCTAssertNil(envelope["last_output"])
    }

    func test_reporterCapsLastOutputTo4KB() throws {
        let output = String(repeating: "x", count: 5_000)
        let payloadData = try JSONSerialization.data(withJSONObject: [
            "session_id": "sid-reporter",
            "cwd": "/tmp/project",
            "last_output": output
        ], options: [])
        let envelope = try runReporter(stdin: String(data: payloadData, encoding: .utf8)!)

        XCTAssertEqual((envelope["last_output"] as? String)?.utf8.count, 4_096)
    }

    private func runReporter(stdin: String) throws -> [String: Any] {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let reporter = repoRoot.appendingPathComponent("Reporter/cab-report.sh")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [reporter.path, "stop"]
        process.currentDirectoryURL = repoRoot
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = tempHome.path
        environment["ITERM_SESSION_ID"] = ""
        environment["TERM_PROGRAM"] = ""
        environment["CLAUDE_PROJECT_DIR"] = ""
        process.environment = environment

        let input = Pipe()
        process.standardInput = input
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let logURL = tempHome
            .appendingPathComponent("Library/Logs/ClaudeAlertBot/hook.log")
        let log = try String(contentsOf: logURL, encoding: .utf8)
        let line = try XCTUnwrap(log.split(separator: "\n").last)
        let data = Data(line.utf8)
        let outer = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(outer["envelope"] as? [String: Any])
    }
}
