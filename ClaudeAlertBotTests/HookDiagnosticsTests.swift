// ClaudeAlertBotTests/HookDiagnosticsTests.swift — menu bar Diagnostics checks.
import XCTest
@testable import ClaudeAlertBot

final class HookDiagnosticsTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("cab-diagnostics-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempHome {
            try? FileManager.default.removeItem(at: tempHome)
        }
        tempHome = nil
    }

    func test_check_freshHome_reportsNothingInstalled() {
        let report = check()

        XCTAssertFalse(report.claudeHooksInstalled)
        XCTAssertNil(report.codexHooksInstalled)
        XCTAssertFalse(report.reporterInstalled)
        XCTAssertFalse(report.socketListening)
        XCTAssertTrue(report.accessibilityGranted)
        XCTAssertFalse(report.allOK)
    }

    func test_check_afterInstall_reportsHooksAndReporter() throws {
        try install()

        let report = check()

        XCTAssertTrue(report.claudeHooksInstalled)
        XCTAssertNil(report.codexHooksInstalled)
        XCTAssertTrue(report.reporterInstalled)
    }

    func test_check_missingOneClaudeHook_reportsNotInstalled() throws {
        try install()
        let settingsURL = tempHome.appendingPathComponent(".claude/settings.json")
        var settings = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any])
        var hooks = try XCTUnwrap(settings["hooks"] as? [String: Any])
        hooks.removeValue(forKey: "PostToolUse")
        settings["hooks"] = hooks
        try JSONSerialization.data(withJSONObject: settings).write(to: settingsURL)

        XCTAssertFalse(check().claudeHooksInstalled)
    }

    func test_check_codexDirWithoutHooks_reportsCodexNotInstalled() throws {
        try FileManager.default.createDirectory(at: tempHome.appendingPathComponent(".codex"),
                                                withIntermediateDirectories: true)

        let report = check()

        XCTAssertEqual(report.codexHooksInstalled, false)
        XCTAssertFalse(report.allOK)
    }

    func test_check_codexHooksJSONAfterInstall_reportsCodexInstalled() throws {
        try FileManager.default.createDirectory(at: tempHome.appendingPathComponent(".codex"),
                                                withIntermediateDirectories: true)
        try install()

        XCTAssertEqual(check().codexHooksInstalled, true)
    }

    func test_check_codexInlineHooksAfterInstall_reportsCodexInstalled() throws {
        let codexDir = tempHome.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try """
        [[hooks.Stop]]
        matcher = ""
        [[hooks.Stop.hooks]]
        type = "command"
        command = "other-tool stop"
        """.write(to: codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)
        try install()

        XCTAssertEqual(check().codexHooksInstalled, true)
    }

    func test_check_socketFile_reportsListening() throws {
        let socketPath = "/tmp/cab-diag-\(UUID().uuidString.prefix(8)).sock"
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(fd, 0)
        defer { close(fd); unlink(socketPath) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(socketPath.utf8)) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bound, 0)

        XCTAssertTrue(check(socketPath: socketPath).socketListening)
    }

    func test_allOK_requiresEveryCheck() {
        let ok = allGoodReport()
        XCTAssertTrue(ok.allOK)

        var noAccessibility = ok
        noAccessibility.accessibilityGranted = false
        XCTAssertFalse(noAccessibility.allOK)

        var codexBroken = ok
        codexBroken.codexHooksInstalled = false
        XCTAssertFalse(codexBroken.allOK)

        var socketDown = ok
        socketDown.socketListening = false
        XCTAssertFalse(socketDown.allOK)
    }

    func test_lastEventLabel_formatsElapsedTime() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(HookDiagnostics.lastEventLabel(nil, now: now), "Last hook event: none yet")
        XCTAssertEqual(HookDiagnostics.lastEventLabel(now.addingTimeInterval(-30), now: now), "Last hook event: just now")
        XCTAssertEqual(HookDiagnostics.lastEventLabel(now.addingTimeInterval(-5 * 60), now: now), "Last hook event: 5 min ago")
        XCTAssertEqual(HookDiagnostics.lastEventLabel(now.addingTimeInterval(-3 * 3600), now: now), "Last hook event: 3h ago")
        XCTAssertEqual(HookDiagnostics.lastEventLabel(now.addingTimeInterval(-50 * 3600), now: now), "Last hook event: 2d ago")
    }

    func test_rows_allGood_useCheckmarks() {
        let rows = HookDiagnostics.rows(allGoodReport())

        XCTAssertEqual(rows.map(\.text), [
            "Claude hooks registered",
            "Reporter installed",
            "App listening for hooks",
            "Accessibility granted",
        ])
        XCTAssertTrue(rows.allSatisfy { $0.systemImage == "checkmark.circle" })
    }

    func test_rows_failures_useXmarkAndProblemText() {
        var report = allGoodReport()
        report.codexHooksInstalled = false
        report.accessibilityGranted = false

        let rows = HookDiagnostics.rows(report)

        XCTAssertEqual(rows.filter { !$0.ok }.map(\.text), ["Codex hooks missing", "Accessibility not granted"])
        XCTAssertEqual(rows.filter { !$0.ok }.map(\.systemImage), ["xmark.circle", "xmark.circle"])
    }

    private func allGoodReport() -> HookDiagnosticsReport {
        HookDiagnosticsReport(claudeHooksInstalled: true, codexHooksInstalled: nil, reporterInstalled: true,
                              socketListening: true, accessibilityGranted: true, lastEventAt: nil)
    }

    private func install() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report")
        try "binary".write(to: reporter, atomically: true, encoding: .utf8)
        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)
    }

    private func check(socketPath: String = "/nonexistent/cab-diagnostics.sock") -> HookDiagnosticsReport {
        HookDiagnostics.check(homeDirectory: tempHome, socketPath: socketPath,
                              accessibilityGranted: true, lastEventAt: nil)
    }
}
