import XCTest
@testable import ClaudeAlertBot

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

    func test_hookInstallerCopiesReporterAndCreatesClaudeHooks() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)

        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)

        let installedReporter = tempHome
            .appendingPathComponent("Library/Application Support/ClaudeAlertBot/cab-report.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedReporter.path))
        let installedMode = try FileManager.default.attributesOfItem(atPath: installedReporter.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(installedMode?.intValue, 0o700)

        let hooks = try loadInstalledHooks()
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop"), [
            "\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" stop"
        ])
        XCTAssertEqual(cabCommands(in: hooks, event: "UserPromptSubmit"), [
            "\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" user_prompt_submit"
        ])
    }

    func test_hookInstallerIsIdempotentAndPreservesOtherHooks() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)
        let settings = tempHome.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "theme": "dark",
          "hooks": {
            "Stop": [
              {
                "matcher": "keep",
                "hooks": [
                  { "type": "command", "command": "echo keep", "timeout": 1 }
                ]
              },
              {
                "matcher": "",
                "hooks": [
                  { "type": "command", "command": "old/ClaudeAlertBot/cab-report.sh stop", "timeout": 5 }
                ]
              }
            ]
          }
        }
        """.write(to: settings, atomically: true, encoding: .utf8)

        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)
        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)

        let installed = try loadInstalledSettings()
        XCTAssertEqual(installed["theme"] as? String, "dark")
        let hooks = try XCTUnwrap(installed["hooks"] as? [String: Any])
        XCTAssertEqual(otherCommands(in: hooks, event: "Stop"), ["echo keep"])
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop").count, 1)
        XCTAssertEqual(cabCommands(in: hooks, event: "UserPromptSubmit").count, 1)
    }

    func test_appDelegateWiresHookInstallerOutsideUnitTests() throws {
        let source = try readAppDelegateSource()

        XCTAssertTrue(source.contains("HookInstaller.installBundledReporterIfNeeded()"))
        XCTAssertTrue(source.contains("!Self.isRunningUnitTests"))
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

    private func loadInstalledSettings() throws -> [String: Any] {
        let settings = tempHome.appendingPathComponent(".claude/settings.json")
        let data = try Data(contentsOf: settings)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func loadInstalledHooks() throws -> [String: Any] {
        let settings = try loadInstalledSettings()
        return try XCTUnwrap(settings["hooks"] as? [String: Any])
    }

    private func cabCommands(in hooks: [String: Any], event: String) -> [String] {
        commands(in: hooks, event: event).filter { $0.contains("ClaudeAlertBot/cab-report.sh") }
    }

    private func otherCommands(in hooks: [String: Any], event: String) -> [String] {
        commands(in: hooks, event: event).filter { !$0.contains("ClaudeAlertBot/cab-report.sh") }
    }

    private func commands(in hooks: [String: Any], event: String) -> [String] {
        guard let entries = hooks[event] as? [[String: Any]] else { return [] }
        return entries.flatMap { entry -> [String] in
            guard let commands = entry["hooks"] as? [[String: Any]] else { return [] }
            return commands.compactMap { $0["command"] as? String }
        }
    }

    private func readAppDelegateSource(_ thisFile: StaticString = #filePath) throws -> String {
        let repoRoot = URL(fileURLWithPath: "\(thisFile)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/AppDelegate.swift")
        return try String(contentsOf: target, encoding: .utf8)
    }
}
