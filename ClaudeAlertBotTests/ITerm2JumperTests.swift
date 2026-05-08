// ITerm2JumperTests.swift — Phase 3 / 03-05.
// Scope: nil/invalid-UUID short-circuit. Live-AppleScript paths covered by 03-09 e2e.
import XCTest
@testable import ClaudeAlertBot

@MainActor
final class ITerm2JumperTests: XCTestCase {

    func test_jump_nilItermSessionID_returnsMissingWithoutScriptRun() async {
        let session = CompletedSession(
            sessionID: "test-nil-iterm",
            projectName: "T",
            stoppedAt: Date(),
            durationSec: 31,
            itermSessionID: nil,            // ← the trigger
            tty: nil,
            cwd: nil
        )
        let jumper = ITerm2Jumper()         // default helper = .shared (not invoked)
        let result = await jumper.jump(to: session)
        XCTAssertEqual(result, .missing)
    }

    func test_jump_invalidUUID_returnsMissingWithoutScriptRun() async {
        let session = CompletedSession(
            sessionID: "test-bad-iterm",
            projectName: "T",
            stoppedAt: Date(),
            durationSec: 31,
            itermSessionID: "not-a-uuid",   // ← the trigger
            tty: nil,
            cwd: nil
        )
        let jumper = ITerm2Jumper()
        let result = await jumper.jump(to: session)
        XCTAssertEqual(result, .missing)
    }

    func test_jump_envelopeFormatItermID_isStrippedAndValidated() async {
        // D3-04 silent-failure regression: pre-Phase-3 the envelope-form colon-prefixed
        // value would have been passed verbatim, missing the AppleScript match. Now,
        // ITerm2Jumper applies iTermSessionID.uuid(fromRaw:) and reaches the AppleScript
        // helper with the UUID-only form.
        //
        // We cannot deterministically force the helper into a short-circuit branch —
        // runJumpByUUID(_:) does NOT consult lastKnownPermission (only testConnection() does);
        // it always executes AppleScript and returns whatever the system yields. Thus the
        // observed result depends on the test environment (no iTerm2 → .timeout / -1743 /
        // .missing). The invariant we DO verify is: the input must reach AppleScript at
        // all — i.e. result MUST NOT be `.otherError(0)`, which is the helper's signature
        // for "isValid(_:) rejected the input before substitution" (AppleScriptHelper.swift
        // line 144). Any of .ok / .missing / .permissionDenied / .timeout proves the
        // envelope value was stripped and reached the helper successfully.
        let session = CompletedSession(
            sessionID: "test-envelope",
            projectName: "T",
            stoppedAt: Date(),
            durationSec: 31,
            itermSessionID: "w0t0p1:79C4699F-1234-5678-9ABC-DEF012345678",
            tty: nil, cwd: nil
        )
        let jumper = ITerm2Jumper()
        let result = await jumper.jump(to: session)
        XCTAssertNotEqual(result, .otherError(0),
                          "D3-04 regression: envelope-form value must be stripped + pass the isValid(_:) gate. .otherError(0) means the input was rejected before substitution.")
    }

    func test_jump_conformsToTerminalJumper() {
        // Static type-check sentinel.
        let jumper: any TerminalJumper = ITerm2Jumper()
        _ = jumper   // silence unused warning
    }
}
