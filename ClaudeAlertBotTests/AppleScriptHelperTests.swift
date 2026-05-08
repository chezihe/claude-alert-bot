// ClaudeAlertBotTests/AppleScriptHelperTests.swift — Plan 02-05.
// Tests the AppleScriptHelper actor without invoking live AppleScript or the TCC dialog.
// RESEARCH Pattern 3 (compile-once) + Pitfall 3 (1s timeout) + Pitfall 9 (state mirror) anchors.
import XCTest
@testable import ClaudeAlertBot

final class AppleScriptHelperTests: XCTestCase {
    @MainActor
    override func setUp() async throws {
        // Reset to unknown so state-mirror tests have a known starting point.
        SettingsStore.shared.applescriptPermission = .unknown
    }

    func test_scriptSource_containsAppleScriptTimeout() async {
        let src = await AppleScriptHelper.shared.rawSource
        XCTAssertTrue(
            src.contains("with timeout of 1 second"),
            "AppleScript-side 1s timeout missing — Pitfall 3 regression"
        )
        XCTAssertTrue(
            src.contains("id of current session of current tab of current window"),
            "Read-only iTerm2 query body missing — RESEARCH Pattern 3"
        )
    }

    func test_classifyError_minus1743_isDenied() {
        let err: NSDictionary = [NSAppleScript.errorNumber: -1743]
        XCTAssertEqual(AppleScriptHelper.classify(error: err, result: ""), .denied)
    }

    func test_classifyError_minus1712_isTimeout() {
        let err: NSDictionary = [NSAppleScript.errorNumber: -1712]
        XCTAssertEqual(AppleScriptHelper.classify(error: err, result: ""), .timeout)
    }

    func test_classifyError_otherCode_isOtherError() {
        let err: NSDictionary = [NSAppleScript.errorNumber: -1234]
        XCTAssertEqual(AppleScriptHelper.classify(error: err, result: ""), .otherError(-1234))
    }

    func test_classifyError_nil_isSuccess() {
        XCTAssertEqual(AppleScriptHelper.classify(error: nil, result: "abc"), .success("abc"))
    }

    func test_compileOnce_secondCallReusesInstance() async {
        let first = await AppleScriptHelper.shared.compiledForTesting
        let second = await AppleScriptHelper.shared.compiledForTesting
        XCTAssertNotNil(first)
        XCTAssertTrue(
            first === second,
            "ensureCompiled() must reuse the NSAppleScript instance — compile-once contract"
        )
    }

    func test_markDenied_mirrorsToSettingsStore() async {
        await AppleScriptHelper.shared.markDeniedForTesting()
        await MainActor.run {
            XCTAssertEqual(SettingsStore.shared.applescriptPermission, .denied)
        }
    }

    func test_markGranted_mirrorsToSettingsStore() async {
        await AppleScriptHelper.shared.markGrantedForTesting()
        await MainActor.run {
            XCTAssertEqual(SettingsStore.shared.applescriptPermission, .granted)
        }
    }

    func test_queueLabel_isSerial_byConvention() {
        // Indirect: source-level grep on the helper file ensures the label is correct.
        // Prevents accidental rename to a generic name.
        // Resolve helper path relative to this test's #filePath so the test does not
        // depend on xcodebuild's working directory (Rule 1 fix during 02-05 GREEN).
        let testFile = URL(fileURLWithPath: #filePath)        // .../ClaudeAlertBotTests/AppleScriptHelperTests.swift
        let projectRoot = testFile
            .deletingLastPathComponent()                       // .../ClaudeAlertBotTests
            .deletingLastPathComponent()                       // .../<repo>
        let helperURL = projectRoot
            .appendingPathComponent("App")
            .appendingPathComponent("AppleScriptHelper.swift")
        let src = (try? String(contentsOf: helperURL, encoding: .utf8)) ?? ""
        XCTAssertFalse(src.isEmpty, "Could not read App/AppleScriptHelper.swift at \(helperURL.path)")
        XCTAssertTrue(
            src.contains("com.claudealert.bot.applescript"),
            "Queue label must be com.claudealert.bot.applescript — RESEARCH Pattern 3 / Pitfall 3"
        )
    }
}
