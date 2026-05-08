// ClaudeAlertBotTests/PopoverContentTests.swift — Phase 2 / Plan 02-08 Task 1
// Tests for PopoverContentRules pure namespace (display logic extracted from SwiftUI views).
// Anchors: D2-06 (same-project duplicates → time suffix), D2-07 (Clear all visible at rowCount>=2),
// D2-16 (orphan ? when durationSec == nil), UI-SPEC §"Popover row states".
import XCTest
@testable import ClaudeAlertBot

final class PopoverContentTests: XCTestCase {

    // MARK: - D2-07 Clear all gating (UI-SPEC line 89 anchor)

    func test_clearAllVisibility_oneRow_hidden() {
        XCTAssertFalse(PopoverContentRules.shouldShowClearAll(rowCount: 1))
    }

    func test_clearAllVisibility_twoRows_visible() {
        XCTAssertTrue(PopoverContentRules.shouldShowClearAll(rowCount: 2))
    }

    // MARK: - D2-06 same-project duplicates → time suffix on those rows

    func test_sameProjectDuplicates_groupedSet() {
        let s1 = mkSession(id: "a", project: "A")
        let s2 = mkSession(id: "b", project: "B")
        let s3 = mkSession(id: "c", project: "A")
        let dups = PopoverContentRules.projectsWithDuplicates([s1, s2, s3])
        XCTAssertEqual(dups, Set(["A"]))
    }

    func test_timeSuffix_format_hhmm() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 7
        comps.hour = 10; comps.minute = 42; comps.second = 33
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let s = PopoverContentRules.timeSuffix(for: date)
        // Format only — exact wall-clock value depends on dev TZ.
        let regex = try! NSRegularExpression(pattern: "^[0-9]{2}:[0-9]{2}$")
        let range = NSRange(s.startIndex..., in: s)
        XCTAssertNotNil(regex.firstMatch(in: s, options: [], range: range), "Got: \(s)")
    }

    // MARK: - D2-16 orphan indicator

    func test_orphanIndicator_durationSecNil() {
        XCTAssertTrue(PopoverContentRules.showsOrphanIndicator(
            session: mkSession(id: "x", project: "P", duration: nil)))
        XCTAssertFalse(PopoverContentRules.showsOrphanIndicator(
            session: mkSession(id: "y", project: "P", duration: 42)))
    }

    // MARK: - helpers

    private func mkSession(id: String, project: String, duration: Int? = 31) -> CompletedSession {
        CompletedSession(
            sessionID: id,
            projectName: project,
            stoppedAt: Date(),
            durationSec: duration,
            itermSessionID: nil,
            tty: nil,
            cwd: nil
        )
    }
}
