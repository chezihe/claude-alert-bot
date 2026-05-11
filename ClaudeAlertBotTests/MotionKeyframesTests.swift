// MotionKeyframesTests.swift — Phase 1 motion rework.
// Drift-guard for App/MotionKeyframes.swift. Bounce cycle mirrors
// `Claude Alert Bot - Prototype v2.html` @keyframes bounce-cute (lines 117–123).
import XCTest
@testable import ClaudeAlertBot

final class MotionKeyframesTests: XCTestCase {

    // MARK: - Bounce cycle

    func test_bouncePeriod_matchesPrototype_0_9s() {
        XCTAssertEqual(MotionKeyframes.bouncePeriod, 0.9, accuracy: 0.0001)
    }

    func test_bounceCycle_startsAtPercent0_endsAtPercent100() {
        XCTAssertEqual(MotionKeyframes.bounceCycle.first?.percent, 0)
        XCTAssertEqual(MotionKeyframes.bounceCycle.last?.percent, 100)
    }

    func test_bounceCycle_percentIsMonotonicallyIncreasing() {
        let percents = MotionKeyframes.bounceCycle.map(\.percent)
        for i in 1..<percents.count {
            XCTAssertGreaterThan(percents[i], percents[i - 1],
                                 "bounceCycle[\(i)].percent must be > [\(i-1)]")
        }
    }

    func test_bounceCycle_isLoopContinuous() {
        let first = MotionKeyframes.bounceCycle.first
        let last = MotionKeyframes.bounceCycle.last
        XCTAssertEqual(first?.translateY, last?.translateY, "translateY must loop")
        XCTAssertEqual(first?.scaleX, last?.scaleX, "scaleX must loop")
        XCTAssertEqual(first?.scaleY, last?.scaleY, "scaleY must loop")
    }

    func test_bounceCycle_matchesPrototypeKeyframesExactly() {
        // HTML @keyframes bounce-cute (Claude Alert Bot - Prototype v2.html:117–123)
        let expected: [(Double, CGFloat, CGFloat, CGFloat)] = [
            (0,    0,  1.04, 0.94),
            (18,  -2,  1.01, 0.99),
            (50,  -5,  0.97, 1.05),
            (82,  -2,  1.01, 0.99),
            (100,  0,  1.04, 0.94),
        ]
        XCTAssertEqual(MotionKeyframes.bounceCycle.count, expected.count)
        for (kf, exp) in zip(MotionKeyframes.bounceCycle, expected) {
            XCTAssertEqual(kf.percent,    exp.0, accuracy: 0.0001)
            XCTAssertEqual(kf.translateY, exp.1, accuracy: 0.0001)
            XCTAssertEqual(kf.scaleX,     exp.2, accuracy: 0.0001)
            XCTAssertEqual(kf.scaleY,     exp.3, accuracy: 0.0001)
        }
    }
}
