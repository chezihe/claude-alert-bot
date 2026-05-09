// ClaudeAlertBotTests/PopoverRowStateTests.swift — Phase 3 / Plan 03-06 (D3-14 regression guard).
// Scope: RowState case identity + source-level invariants for the missing animation contract.
// SwiftUI animation timing is NOT unit-tested (the orchestration lives inside SwiftUI internals);
// integration verification of the actual animation lands in the 03-09 manual checkpoint.
//
// CONTEXT D3-14 anchor: "애니메이션 시각 자체는 단위 테스트 안 함; state 전이 + clearOne 호출 + OSLog
// 시그니처만 검증." This file covers the static `state algebra` half of that contract; the runtime
// behaviour (clearOne + OSLog) lands in the WidgetPopoverController tests in 03-07.
import XCTest
@testable import ClaudeAlertBot

@MainActor
final class PopoverRowStateTests: XCTestCase {

    // MARK: - D3-11 RowState case identity

    func test_RowState_caseIdentity() {
        // Brittle-by-design — bumping cases requires CONTEXT amendment.
        let normal: RowState = .normal
        let jumping: RowState = .jumping
        let missing: RowState = .missing
        XCTAssertNotEqual(normal, jumping)
        XCTAssertNotEqual(jumping, missing)
        XCTAssertNotEqual(normal, missing)
    }

    // MARK: - JUMP-05 row self-debounce contract (source-level audit)

    func test_clickHandler_isNoOpInJumpingState() {
        // The row's Button action must short-circuit when state != .normal. We can't easily
        // unit-test the closure without a SwiftUI host; assert via source-level audit instead.
        let src = readPopoverRowViewSource()
        XCTAssertTrue(
            src.contains("guard state == .normal else { return }"),
            "JUMP-05: PopoverRowView click handler must short-circuit when state != .normal"
        )
    }

    // MARK: - D3-11 onMissingComplete dispatch contract (source-level audit)

    func test_missingAnimation_callsOnMissingCompleteCallback() {
        // Both branches of runMissingAnimation (reduced-motion + full-animation) must invoke
        // onMissingComplete() in the animation completion closure so the parent can clearOne.
        let src = readPopoverRowViewSource()
        // String.components(separatedBy:) returns count = (occurrences + 1).
        let occurrences = src.components(separatedBy: "onMissingComplete()").count - 1
        XCTAssertGreaterThanOrEqual(
            occurrences, 2,
            "D3-11: onMissingComplete() must be invoked in BOTH reduce-motion and full-animation branches of runMissingAnimation (found \(occurrences) call sites)"
        )
    }

    // MARK: - WO-005 status dot rendering contract (source-level audit)

    func test_statusDot_usesAlertKindColorForFillAndUnavailableRing() {
        let src = readPopoverRowViewSource()

        XCTAssertTrue(
            src.contains("let dotColor = ColorTokens.statusDot(for: session.kind)"),
            "WO-005: PopoverRowView.statusDot must derive its color from session.kind"
        )
        XCTAssertTrue(
            src.contains(".fill(dotColor)"),
            "WO-005: available rows must fill the status dot with the kind color"
        )
        XCTAssertTrue(
            src.contains(".stroke(dotColor, lineWidth: GeometryTokens.statusDotRingStroke)"),
            "WO-005: unavailable rows must keep the hollow ring path while using the kind color"
        )
    }

    // MARK: - WO-006 context menu contract (source-level audit)

    func test_contextMenu_wiresPinAndMuteCallbacks() {
        let src = readPopoverRowViewSource()

        XCTAssertTrue(src.contains(".contextMenu {"), "WO-006: row must expose a context menu")
        XCTAssertTrue(src.contains("Button(session.pinned ? \"Unpin\" : \"Pin\")"),
                      "WO-006: context menu must branch Pin/Unpin from session.pinned")
        XCTAssertTrue(src.contains("Button(isMuted ? \"Unmute This Project\" : \"Mute this project for 1h\")"),
                      "WO-006: context menu must branch Mute/Unmute from isMuted")
        XCTAssertTrue(src.contains("onTogglePin()"),
                      "WO-006: Pin menu item must dispatch through the row callback")
        XCTAssertTrue(src.contains("onToggleMute()"),
                      "WO-006: Mute menu item must dispatch through the row callback")
    }

    // MARK: - WO-011 pinned row indicator contract (source-level audit)

    func test_pinnedRowIndicator_usesPinFillSymbol() {
        let src = readPopoverRowViewSource()

        XCTAssertTrue(
            src.contains("Image(systemName: \"pin.fill\")"),
            "WO-011: pinned rows must render the SF Symbol pin.fill"
        )
    }

    func test_pinnedRowIndicator_isGatedBySessionPinnedNearby() {
        let src = readPopoverRowViewSource()
        let lines = src.components(separatedBy: .newlines)

        guard let symbolLine = lines.firstIndex(where: { $0.contains("Image(systemName: \"pin.fill\")") }) else {
            XCTFail("WO-011: could not find pin.fill indicator")
            return
        }

        let start = max(0, symbolLine - 5)
        let end = min(lines.count - 1, symbolLine + 5)
        let nearby = lines[start...end].joined(separator: "\n")
        XCTAssertTrue(
            nearby.contains("if session.pinned"),
            "WO-011: pin.fill indicator must be conditionally rendered by session.pinned near the indicator"
        )
    }

    func test_pinnedRowIndicator_hasAccessibilityLabel() {
        let src = readPopoverRowViewSource()

        XCTAssertTrue(
            src.contains(".accessibilityLabel(\"Pinned\")"),
            "WO-011: pinned row indicator must expose a Pinned accessibility label"
        )
    }

    // MARK: - helpers

    /// Resolve App/PopoverRowView.swift relative to *this* test file's source location so
    /// the test is independent of xcodebuild's working directory.
    private func readPopoverRowViewSource(_ thisFile: StaticString = #filePath) -> String {
        let here = URL(fileURLWithPath: "\(thisFile)")
        // .../ClaudeAlertBotTests/PopoverRowStateTests.swift → repo root → App/PopoverRowView.swift
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/PopoverRowView.swift")
        guard let data = try? String(contentsOf: target, encoding: .utf8) else {
            XCTFail("Could not read App/PopoverRowView.swift at \(target.path)")
            return ""
        }
        return data
    }
}
