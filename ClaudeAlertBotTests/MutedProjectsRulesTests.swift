// ClaudeAlertBotTests/MutedProjectsRulesTests.swift — WO-007 Settings muted-projects rules.
import XCTest
@testable import ClaudeAlertBot

final class MutedProjectsRulesTests: XCTestCase {
    func test_activeMutes_emptyDictionary_returnsEmptyArray() {
        let now = Date(timeIntervalSince1970: 1000)

        let active = MutedProjectsRules.activeMutes([:], now: now)

        XCTAssertTrue(active.isEmpty)
    }

    func test_activeMutes_allExpired_returnsEmptyArray() {
        let now = Date(timeIntervalSince1970: 1000)

        let active = MutedProjectsRules.activeMutes([
            "alpha": now.addingTimeInterval(-1),
            "beta": now
        ], now: now)

        XCTAssertTrue(active.isEmpty)
    }

    func test_activeMutes_mixedExpiredAndActive_returnsOnlyActive() {
        let now = Date(timeIntervalSince1970: 1000)

        let active = MutedProjectsRules.activeMutes([
            "expired": now.addingTimeInterval(-1),
            "alpha": now.addingTimeInterval(60),
            "beta": now.addingTimeInterval(120)
        ], now: now)

        XCTAssertEqual(active.map(\.project), ["alpha", "beta"])
        XCTAssertEqual(active.map(\.expiresAt), [
            now.addingTimeInterval(60),
            now.addingTimeInterval(120)
        ])
    }

    func test_activeMutes_excludesExactExpirationBoundary() {
        let now = Date(timeIntervalSince1970: 1000)

        let active = MutedProjectsRules.activeMutes(["alpha": now], now: now)

        XCTAssertTrue(active.isEmpty)
    }

    func test_activeMutes_sortsAlphabeticallyByProject() {
        let now = Date(timeIntervalSince1970: 1000)

        let active = MutedProjectsRules.activeMutes([
            "zulu": now.addingTimeInterval(60),
            "alpha": now.addingTimeInterval(60),
            "mango": now.addingTimeInterval(60)
        ], now: now)

        XCTAssertEqual(active.map(\.project), ["alpha", "mango", "zulu"])
    }

    func test_remainingMinutesLabel_formatsBoundaryCases() {
        let now = Date(timeIntervalSince1970: 1000)

        XCTAssertEqual(MutedProjectsRules.remainingMinutesLabel(expiresAt: now, now: now), "<1 min left")
        XCTAssertEqual(MutedProjectsRules.remainingMinutesLabel(expiresAt: now.addingTimeInterval(59), now: now), "<1 min left")
        XCTAssertEqual(MutedProjectsRules.remainingMinutesLabel(expiresAt: now.addingTimeInterval(60), now: now), "1 min left")
        XCTAssertEqual(MutedProjectsRules.remainingMinutesLabel(expiresAt: now.addingTimeInterval(119), now: now), "1 min left")
        XCTAssertEqual(MutedProjectsRules.remainingMinutesLabel(expiresAt: now.addingTimeInterval(3599), now: now), "59 min left")
        XCTAssertEqual(MutedProjectsRules.remainingMinutesLabel(expiresAt: now.addingTimeInterval(3600), now: now), "1h left")
        XCTAssertEqual(MutedProjectsRules.remainingMinutesLabel(expiresAt: now.addingTimeInterval(4 * 3600 + 15 * 60), now: now), "4h 15m left")
    }

    func test_muteDuration_fixedOptions_addExpectedInterval() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        XCTAssertEqual(MuteDuration.fifteenMinutes.expiresAt(from: now), now.addingTimeInterval(15 * 60))
        XCTAssertEqual(MuteDuration.oneHour.expiresAt(from: now), now.addingTimeInterval(3600))
        XCTAssertEqual(MuteDuration.fourHours.expiresAt(from: now), now.addingTimeInterval(4 * 3600))
    }

    func test_muteDuration_restOfToday_expiresAtNextLocalMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 23, minute: 30))!
        let midnight = calendar.date(from: DateComponents(year: 2026, month: 10, day: 11))!

        XCTAssertEqual(MuteDuration.restOfToday.expiresAt(from: now, calendar: calendar), midnight)
    }
}
