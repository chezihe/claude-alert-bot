// App/MotionKeyframes.swift — Phase 1 motion rework.
// Pure keyframe data (no view code). Source of truth: HTML prototype
// internal motion prototype @keyframes bounce-cute (117–123),
// heartbeat (147–153), and ring (154–162). Loop-continuous; consumed by
// KeyframeIdleGlyph's KeyframeAnimator multi-track wiring via the `*Steps` tables.
import CoreGraphics
import Foundation

struct BounceKeyframe: Equatable {
    let percent: Double   // 0...100 along the cycle
    let translateY: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
    // Micro-rotation overlay (degrees) for cartoon "톡톡" feel — anchored at glyph bottom.
    let rotation: Double
}

struct HeartKeyframe: Equatable {
    let percent: Double   // 0...100 along the cycle
    let scale: CGFloat
}

struct RingKeyframe: Equatable {
    let percent: Double   // 0...100 along the cycle
    let rotation: Double  // degrees, anchored near glyph top (0.5, 0.1)
}

/// One CubicKeyframe in a KeyframeAnimator track: the target frame plus how long
/// the segment leading into it lasts. Every track of a cycle shares the same steps,
/// so each keyframe's timing is defined exactly once.
struct KeyframeStep<Frame> {
    let frame: Frame
    let duration: TimeInterval
}

struct RageKeyframe: Equatable {
    let percent: Double   // 0...100 along the 0.95s throw-windup window
    let rotation: Double  // degrees, anchored at glyph bottom-mid (0.5, 0.9)
    let translateX: CGFloat
    let translateY: CGFloat
    let scale: CGFloat
}

enum MotionKeyframes {
    // internal prototype bounce-cute is 0.9s ease-in-out infinite.
    static let bouncePeriod: TimeInterval = 0.9

    // internal prototype @keyframes bounce-cute (post 64pt-widget rescale + micro-rotation overlay).
    // Bottom squash (1.04, 0.94) → apex stretch (0.97, 1.05) → bottom squash.
    // Rotation lean (-2° → 0° → +2°) mirrors a cartoon weight-shift across the bounce.
    static let bounceCycle: [BounceKeyframe] = [
        BounceKeyframe(percent:   0, translateY:  0, scaleX: 1.04, scaleY: 0.94, rotation:  0),
        BounceKeyframe(percent:  18, translateY: -3, scaleX: 1.01, scaleY: 0.99, rotation: -2),
        BounceKeyframe(percent:  50, translateY: -7, scaleX: 0.97, scaleY: 1.05, rotation:  0),
        BounceKeyframe(percent:  82, translateY: -3, scaleX: 1.01, scaleY: 0.99, rotation:  2),
        BounceKeyframe(percent: 100, translateY:  0, scaleX: 1.04, scaleY: 0.94, rotation:  0),
    ]

    // internal prototype heartbeat is 1.4s ease-in-out infinite.
    static let heartPeriod: TimeInterval = 1.4

    // internal prototype @keyframes heartbeat.
    // Double-pulse: peak 1 at 14% (1.14), peak 2 at 42% (1.08), then idle.
    static let heartCycle: [HeartKeyframe] = [
        HeartKeyframe(percent:   0, scale: 1.00),
        HeartKeyframe(percent:  14, scale: 1.14),
        HeartKeyframe(percent:  28, scale: 1.00),
        HeartKeyframe(percent:  42, scale: 1.08),
        HeartKeyframe(percent:  56, scale: 1.00),
        HeartKeyframe(percent: 100, scale: 1.00),
    ]

    // internal prototype ring is 1.4s ease-in-out infinite.
    static let ringPeriod: TimeInterval = 1.4

    // internal prototype @keyframes ring (with added micro-aftershock at 70%/85% for "톡톡" finish).
    // Damped bell swing; starts and ends at 0 so the loop does not snap.
    static let ringCycle: [RingKeyframe] = [
        RingKeyframe(percent:   0, rotation:   0),
        RingKeyframe(percent:  10, rotation: -14),
        RingKeyframe(percent:  20, rotation:  12),
        RingKeyframe(percent:  30, rotation:  -9),
        RingKeyframe(percent:  40, rotation:   7),
        RingKeyframe(percent:  50, rotation:  -4),
        RingKeyframe(percent:  60, rotation:   2),
        RingKeyframe(percent:  70, rotation: -1.2),
        RingKeyframe(percent:  85, rotation:  0.6),
        RingKeyframe(percent: 100, rotation:   0),
    ]

    // internal prototype throw-windup is 950ms cubic-bezier(.5, 0, .3, 1),
    // looped on a 2.4s rage interval. Transform origin: 50% 90%.
    static let rageWindupDuration: TimeInterval = 0.95
    static let ragePeriod: TimeInterval = 2.4
    static let rageHoldDuration: TimeInterval = ragePeriod - rageWindupDuration // 1.45s rest
    // The MacBook projectile leaves at peak forward whip (the 44% windup keyframe ≈ 418ms).
    static let rageReleaseOffset: TimeInterval = rageWindupDuration * 0.44

    // internal prototype @keyframes throw-windup.
    // Wind back → hold → whip forward → settle.
    static let rageCycle: [RageKeyframe] = [
        RageKeyframe(percent:   0, rotation:   0, translateX:  0, translateY:  0, scale: 1.00),
        RageKeyframe(percent:  18, rotation:  28, translateX:  3, translateY:  2, scale: 1.02),
        RageKeyframe(percent:  30, rotation:  34, translateX:  4, translateY:  2, scale: 1.04),
        RageKeyframe(percent:  44, rotation: -32, translateX: -7, translateY: -3, scale: 0.96),
        RageKeyframe(percent:  58, rotation: -18, translateX: -3, translateY: -1, scale: 1.00),
        RageKeyframe(percent:  78, rotation:   8, translateX:  1, translateY:  1, scale: 1.00),
        RageKeyframe(percent: 100, rotation:   0, translateX:  0, translateY:  0, scale: 1.00),
    ]

    // MARK: - KeyframeAnimator steps
    // Segment durations are derived from each cycle's `percent` column, so the
    // fractions (bounce 0.18/0.32/0.32/0.18, heart 0.14×4/0.44, ring 0.10×6/0.15×2,
    // rage 0.18/0.12/0.14/0.14/0.20/0.22) live only in the tables above.

    static let bounceSteps = steps(bounceCycle, percent: \.percent, period: bouncePeriod)
    static let heartSteps = steps(heartCycle, percent: \.percent, period: heartPeriod)
    static let ringSteps = steps(ringCycle, percent: \.percent, period: ringPeriod)
    // 6 throw-windup segments spread across 0.95s, then a 1.45s hold at the final
    // (identity) frame so the loop matches the prototype's 2.4s rage interval.
    static let rageSteps = steps(rageCycle, percent: \.percent, period: rageWindupDuration)
        + [KeyframeStep(frame: rageCycle[rageCycle.count - 1], duration: rageHoldDuration)]

    /// Fraction of the cycle spent travelling into each keyframe after the first.
    static func segmentFractions(_ percents: [Double]) -> [Double] {
        zip(percents.dropFirst(), percents).map { ($0 - $1) / 100 }
    }

    /// Steps for keyframes 1...n of `cycle`; keyframe 0 is the animator's initial value.
    static func steps<Frame>(
        _ cycle: [Frame],
        percent: KeyPath<Frame, Double>,
        period: TimeInterval
    ) -> [KeyframeStep<Frame>] {
        let fractions = segmentFractions(cycle.map { $0[keyPath: percent] })
        return zip(cycle.dropFirst(), fractions).map {
            KeyframeStep(frame: $0, duration: period * $1)
        }
    }
}
