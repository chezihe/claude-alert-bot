// MotionKeyframesTests.swift — Phase 1 motion rework.
// Drift-guard for App/MotionKeyframes.swift. Bounce / Heart / Ring cycles mirror
// internal motion prototype @keyframes blocks.
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
        // internal prototype @keyframes bounce-cute (post 64pt widget rescale + rotation overlay)
        let expected: [(Double, CGFloat, CGFloat, CGFloat, Double)] = [
            (0,    0,  1.04, 0.94,  0),
            (18,  -3,  1.01, 0.99, -2),
            (50,  -7,  0.97, 1.05,  0),
            (82,  -3,  1.01, 0.99,  2),
            (100,  0,  1.04, 0.94,  0),
        ]
        XCTAssertEqual(MotionKeyframes.bounceCycle.count, expected.count)
        for (kf, exp) in zip(MotionKeyframes.bounceCycle, expected) {
            XCTAssertEqual(kf.percent,    exp.0, accuracy: 0.0001)
            XCTAssertEqual(kf.translateY, exp.1, accuracy: 0.0001)
            XCTAssertEqual(kf.scaleX,     exp.2, accuracy: 0.0001)
            XCTAssertEqual(kf.scaleY,     exp.3, accuracy: 0.0001)
            XCTAssertEqual(kf.rotation,   exp.4, accuracy: 0.0001)
        }
    }

    // MARK: - Heart cycle

    func test_heartPeriod_matchesPrototype_1_4s() {
        XCTAssertEqual(MotionKeyframes.heartPeriod, 1.4, accuracy: 0.0001)
    }

    func test_heartCycle_startsAtPercent0_endsAtPercent100() {
        XCTAssertEqual(MotionKeyframes.heartCycle.first?.percent, 0)
        XCTAssertEqual(MotionKeyframes.heartCycle.last?.percent, 100)
    }

    func test_heartCycle_percentIsMonotonicallyIncreasing() {
        let percents = MotionKeyframes.heartCycle.map(\.percent)
        for i in 1..<percents.count {
            XCTAssertGreaterThan(percents[i], percents[i - 1])
        }
    }

    func test_heartCycle_isLoopContinuous() {
        let first = MotionKeyframes.heartCycle.first
        let last = MotionKeyframes.heartCycle.last
        XCTAssertEqual(first?.scale, last?.scale)
    }

    func test_heartCycle_matchesPrototypeKeyframesExactly() {
        // internal prototype @keyframes heartbeat.
        let expected: [(Double, CGFloat)] = [
            (0,   1.00),
            (14,  1.14),
            (28,  1.00),
            (42,  1.08),
            (56,  1.00),
            (100, 1.00),
        ]
        XCTAssertEqual(MotionKeyframes.heartCycle.count, expected.count)
        for (kf, exp) in zip(MotionKeyframes.heartCycle, expected) {
            XCTAssertEqual(kf.percent, exp.0, accuracy: 0.0001)
            XCTAssertEqual(kf.scale,   exp.1, accuracy: 0.0001)
        }
    }

    // MARK: - Ring cycle

    func test_ringPeriod_matchesPrototype_1_4s() {
        XCTAssertEqual(MotionKeyframes.ringPeriod, 1.4, accuracy: 0.0001)
    }

    func test_ringCycle_startsAtPercent0_endsAtPercent100() {
        XCTAssertEqual(MotionKeyframes.ringCycle.first?.percent, 0)
        XCTAssertEqual(MotionKeyframes.ringCycle.last?.percent, 100)
    }

    func test_ringCycle_percentIsMonotonicallyIncreasing() {
        let percents = MotionKeyframes.ringCycle.map(\.percent)
        for i in 1..<percents.count {
            XCTAssertGreaterThan(percents[i], percents[i - 1])
        }
    }

    func test_ringCycle_isLoopContinuous() {
        let first = MotionKeyframes.ringCycle.first
        let last = MotionKeyframes.ringCycle.last
        XCTAssertEqual(first?.rotation, last?.rotation)
    }

    func test_ringCycle_matchesPrototypeKeyframesExactly() {
        // internal prototype @keyframes ring + micro-aftershock at 70%/85% (post 64pt rescale).
        let expected: [(Double, Double)] = [
            (0,     0),
            (10,  -14),
            (20,   12),
            (30,   -9),
            (40,    7),
            (50,   -4),
            (60,    2),
            (70,  -1.2),
            (85,   0.6),
            (100,   0),
        ]
        XCTAssertEqual(MotionKeyframes.ringCycle.count, expected.count)
        for (kf, exp) in zip(MotionKeyframes.ringCycle, expected) {
            XCTAssertEqual(kf.percent,   exp.0, accuracy: 0.0001)
            XCTAssertEqual(kf.rotation,  exp.1, accuracy: 0.0001)
        }
    }
}
