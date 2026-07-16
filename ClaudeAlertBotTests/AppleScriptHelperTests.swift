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
        await AppleScriptHelper.shared.restorePermissionState(.unknown)
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
        let first = await AppleScriptHelper.shared.compiledIdentifierForTesting
        let second = await AppleScriptHelper.shared.compiledIdentifierForTesting
        XCTAssertNotNil(first)
        XCTAssertEqual(
            first, second,
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

    func test_restorePermissionState_usesPersistedValue() async {
        await AppleScriptHelper.shared.restorePermissionState(.granted)

        let permission = await AppleScriptHelper.shared.lastKnownPermission
        XCTAssertEqual(permission, .granted)
    }

    func test_restorePermissionState_allowsPersistedDenialToBeRechecked() async {
        await AppleScriptHelper.shared.restorePermissionState(.denied)

        let permission = await AppleScriptHelper.shared.lastKnownPermission
        XCTAssertEqual(permission, .unknown)
    }

    func test_frontmostQueryRequiresGrantedPermission() {
        XCTAssertFalse(AppleScriptHelper.shouldQueryFrontmost(permission: .unknown))
        XCTAssertFalse(AppleScriptHelper.shouldQueryFrontmost(permission: .denied))
        XCTAssertTrue(AppleScriptHelper.shouldQueryFrontmost(permission: .granted))
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

    // MARK: - Phase 3 / 03-04: jump-by-uuid + testConnection regression

    func test_runJumpByUUID_rejectsNonUUIDInput() async {
        // T-INJECTION-01 whitelist guard: any non-UUID input bypasses script execution.
        let helper = AppleScriptHelper.shared
        let result = await helper.runJumpByUUID("not-a-uuid")
        XCTAssertEqual(result, .otherError(0),
                       "Whitelist rejection must short-circuit before NSAppleScript invocation")
    }

    func test_runJumpByUUID_rejectsAppleScriptInjectionAttempt() async {
        // The literal threat: characters that would break out of the `set targetUUID to "..."` literal.
        let helper = AppleScriptHelper.shared
        let injection = "\"; tell application \"System Events\" to do shell script \"rm -rf /\""
        let result = await helper.runJumpByUUID(injection)
        XCTAssertEqual(result, .otherError(0),
                       "Injection attempt must be rejected by isValid before substitution")
    }

    func test_jumpByUUIDTemplate_containsAppleScriptTimeout() {
        XCTAssertTrue(AppleScriptHelper.jumpRawTemplate.contains("with timeout of 3 seconds"),
                      "JUMP-04: jump-by-uuid script must declare 3-second AppleScript-side hard timeout")
        XCTAssertTrue(AppleScriptHelper.jumpRawTemplate.contains("if id of s is targetUUID"),
                      "RESEARCH Pattern 1 sdef-verified UUID equality match")
    }

    func test_jumpByUUIDTemplate_defersActivationToAccessibilityRaiser() {
        XCTAssertFalse(AppleScriptHelper.jumpRawTemplate.contains("activate"),
                       "Cross-Space jump must not activate iTerm2 before AccessibilityRaiser raises the exact target window")
    }

    func test_jumpByUUIDTemplate_selectsMatchedWindowExplicitly() throws {
        let source = AppleScriptHelper.jumpRawTemplate
        let sessionSelect = try XCTUnwrap(source.range(of: "tell s to select"))
        let windowSelect = try XCTUnwrap(source.range(of: "tell w to select"))
        let payloadReturn = try XCTUnwrap(source.range(of: "return ((id of w) as string)"))

        XCTAssertLessThan(sessionSelect.lowerBound, windowSelect.lowerBound)
        XCTAssertLessThan(windowSelect.lowerBound, payloadReturn.lowerBound)
    }

    func test_runJumpByUUID_attemptsAccessibilityRaiseWithoutMarkingMatchedSessionMissing() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let helperURL = projectRoot
            .appendingPathComponent("App")
            .appendingPathComponent("AppleScriptHelper.swift")
        let src = (try? String(contentsOf: helperURL, encoding: .utf8)) ?? ""
        XCTAssertFalse(src.isEmpty, "Could not read App/AppleScriptHelper.swift at \(helperURL.path)")
        XCTAssertFalse(
            src.contains("_ = AccessibilityRaiser.raise"),
            "runJumpByUUID must still record the AX raise result for diagnostics"
        )
        XCTAssertTrue(
            src.contains("let raised = AccessibilityRaiser.raise"),
            "runJumpByUUID should attempt AX raise after AppleScript matches a target session"
        )
        XCTAssertTrue(
            src.contains("if !raised"),
            "AX raise failure after a session match should be handled explicitly"
        )
        XCTAssertFalse(
            src.contains("guard AccessibilityRaiser.raise"),
            "A matched iTerm session must not be marked missing only because AX raise could not confirm activation"
        )
    }

    func test_runJumpByUUID_doesNotActivateArbitraryITermWindowWhenExactRaiseFails() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let helperURL = projectRoot
            .appendingPathComponent("App")
            .appendingPathComponent("AppleScriptHelper.swift")
        let src = (try? String(contentsOf: helperURL, encoding: .utf8)) ?? ""
        XCTAssertFalse(src.isEmpty, "Could not read App/AppleScriptHelper.swift at \(helperURL.path)")
        let jumpStart = try XCTUnwrap(src.range(of: "func runJumpByUUID"))
        let testConnectionStart = try XCTUnwrap(src.range(of: "func testConnection"))
        let jumpSource = String(src[jumpStart.lowerBound..<testConnectionStart.lowerBound])

        XCTAssertFalse(
            jumpSource.contains("AccessibilityRaiser.activateITerm"),
            "App-level activation can surface a different iTerm Space after an exact-window miss"
        )
    }

    func test_accessibilityRaiser_fallsBackToFocusedOrMainWindowWhenWindowListIsEmpty() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let raiserURL = projectRoot
            .appendingPathComponent("App")
            .appendingPathComponent("AccessibilityRaiser.swift")
        let src = (try? String(contentsOf: raiserURL, encoding: .utf8)) ?? ""
        XCTAssertFalse(src.isEmpty, "Could not read App/AccessibilityRaiser.swift at \(raiserURL.path)")
        XCTAssertTrue(
            src.contains("kAXFocusedWindowAttribute"),
            "iTerm2 can expose an empty kAXWindowsAttribute list; raise must fall back to the focused AX window"
        )
        XCTAssertTrue(
            src.contains("kAXMainWindowAttribute"),
            "iTerm2 can expose an empty kAXWindowsAttribute list; raise must also try the main AX window"
        )
    }

    func test_accessibilityRaiser_rejectsFocusedOrMainWindowWhenWindowIDAndTitleMiss() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let raiserURL = projectRoot
            .appendingPathComponent("App")
            .appendingPathComponent("AccessibilityRaiser.swift")
        let src = (try? String(contentsOf: raiserURL, encoding: .utf8)) ?? ""
        XCTAssertFalse(src.isEmpty, "Could not read App/AccessibilityRaiser.swift at \(raiserURL.path)")

        XCTAssertTrue(
            src.contains("let fallbackAXWindows = fallbackWindows(appElement)"),
            "Focused/main AX windows should remain exact-match candidates when the normal AX list is empty"
        )
        XCTAssertFalse(
            src.contains("matchedWindow ?? fallbackAXWindows.first"),
            "An unmatched focused/main window may belong to another Mission Control Space"
        )
        XCTAssertTrue(
            src.contains("guard let win = matchWindow(axWindows, windowID: windowID, title: title)"),
            "Accessibility raise must require an exact window match"
        )
        XCTAssertTrue(
            src.contains("if windowID == nil, let wantedTitle = title"),
            "A duplicate window title must not override a supplied target window ID"
        )
        XCTAssertFalse(
            src.contains("static func activateITerm"),
            "The unsafe app-level activation fallback must not remain as dead production code"
        )
    }

    func test_accessibilityRaiser_doesNotPromptFromJumpPath() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let projectRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let raiserURL = projectRoot
            .appendingPathComponent("App")
            .appendingPathComponent("AccessibilityRaiser.swift")
        let src = (try? String(contentsOf: raiserURL, encoding: .utf8)) ?? ""
        XCTAssertFalse(src.isEmpty, "Could not read App/AccessibilityRaiser.swift at \(raiserURL.path)")
        let raiseRange = try XCTUnwrap(src.range(of: "static func raise"))
        let raiseSource = String(src[raiseRange.lowerBound...])

        XCTAssertFalse(
            raiseSource.contains("requestTrust()"),
            "Row click jump path must not repeatedly prompt for Accessibility permission"
        )
    }

    func test_focusFrontmostSource_containsAppleScriptTimeout() {
        XCTAssertTrue(AppleScriptHelper.focusFrontmostRawSource.contains("with timeout of 3 seconds"),
                      "JUMP-04 inheritance: focus-frontmost must also declare 3-second hard timeout")
        XCTAssertTrue(AppleScriptHelper.focusFrontmostRawSource.contains("activate"),
                      "SET-05: focus-frontmost activates iTerm2")
    }

    // testConnection branch matrix (D3-16): unit-testable via lastKnownPermission seeding.
    // .granted branch is integration-only (requires live AppleScript + iTerm2 state — covered in 03-09).
    // .unknown branch invokes triggerPermissionPrompt which in turn fires NSAppleScript;
    // we cover the .denied short-circuit branch deterministically here.

    func test_testConnection_deniedShortCircuits() async {
        let helper = AppleScriptHelper.shared
        await helper.markDeniedForTesting()
        let result = await helper.testConnection()
        XCTAssertEqual(result, .permissionDenied,
                       "testConnection in .denied state must short-circuit without script execution")
    }

    func test_hookListenerPermissionPromptDecision_allowsSupportedStopEvents() {
        XCTAssertTrue(HookListener.shouldTriggerPermissionPrompt(
            permission: .unknown,
            event: HookEventFactory.stop(termProgram: "iTerm.app")
        ))
    }

    func test_hookListenerPermissionPromptDecision_preservesLegacyPayloadCompatibility() {
        XCTAssertTrue(HookListener.shouldTriggerPermissionPrompt(
            permission: .unknown,
            event: HookEventFactory.stop(termProgram: nil)
        ))
        XCTAssertTrue(HookListener.shouldTriggerPermissionPrompt(
            permission: .unknown,
            event: HookEventFactory.stop(termProgram: "")
        ))
    }

    func test_hookListenerPermissionPromptDecision_rejectsExplicitNonITermStops() {
        XCTAssertFalse(HookListener.shouldTriggerPermissionPrompt(
            permission: .unknown,
            event: HookEventFactory.stop(termProgram: "Apple_Terminal")
        ))
    }

    func test_hookListenerPermissionPromptDecision_requiresUnknownPermissionAndStopEvent() {
        XCTAssertFalse(HookListener.shouldTriggerPermissionPrompt(
            permission: .granted,
            event: HookEventFactory.stop(termProgram: "iTerm.app")
        ))
        XCTAssertFalse(HookListener.shouldTriggerPermissionPrompt(
            permission: .unknown,
            event: HookEventFactory.userPromptSubmit(sessionID: "sid-prompt", termProgram: "iTerm.app")
        ))
    }

    // MARK: - D3-04 Phase 2 D2-14/D2-15 silent-failure regression (plan-check B2 relocation)

    func test_d3_04_phase2SilentFailureRegression_postNormalizationContract() async {
        // CONTEXT D3-04 — closes the Phase 2 D2-14/D2-15 silent-failure (frontmostMatches
        // always returned false because callers passed envelope-form `wXtYpZ:UUID` while
        // AppleScript `id of session` returns UUID-only per iTerm2 sdef).
        //
        // Post-Phase-3 contract:
        //   (1) HookListener.handle normalizes via iTermSessionID.uuid(fromRaw:) BEFORE
        //       suppressIfFrontmost is invoked → frontmostMatches receives UUID-only.
        //   (2) AppleScriptHelper.scriptSource queries `id of session` (sdef-confirmed
        //       UUID-only output, RESEARCH §Pattern 1).
        //   (3) Both sides UUID-only → byte-for-byte string equality works.

        // (1) HookListener-side normalization invariant.
        let envelope = "w0t0p1:79C4699F-1234-5678-9ABC-DEF012345678"
        let normalized = iTermSessionID.uuid(fromRaw: envelope)
        XCTAssertEqual(normalized, "79C4699F-1234-5678-9ABC-DEF012345678",
                       "D3-04(1): HookListener must strip wXtYpZ: prefix before invoking AppleScriptHelper")

        // (2) AppleScriptHelper-side source contract — queries `id of` (UUID per sdef).
        let source = await AppleScriptHelper.shared.rawSource
        XCTAssertTrue(source.contains("id of"),
                      "D3-04(2): AppleScript queries `id of session` (UUID-only per iTerm2 sdef) — both sides UUID-only post-normalization")
        XCTAssertFalse(source.contains("name of") || source.contains("tty of"),
                       "D3-04(2): AppleScript must NOT query name/tty as primary key (UUID-only contract per ROADMAP locked decision + JUMP-02 single-strategy amendment)")

        // (3) Idempotency of the normalizer — already-normalized input passes through unchanged.
        let alreadyNormalized = "79C4699F-1234-5678-9ABC-DEF012345678"
        XCTAssertEqual(iTermSessionID.uuid(fromRaw: alreadyNormalized), alreadyNormalized,
                       "D3-04(3): normalizer is idempotent; SessionStore.load() migration safe to re-run")
    }
}
