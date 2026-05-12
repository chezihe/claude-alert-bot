// App/MotionKeyframes.swift — Phase 1 motion rework.
// Pure keyframe data (no view code). Source of truth: HTML prototype
// `Claude Alert Bot - Prototype v2.html` @keyframes bounce-cute (117–123),
// heartbeat (147–153), and ring (154–162). Loop-continuous; consumed by
// WidgetIconView's KeyframeAnimator multi-track wiring.
import CoreGraphics
import Foundation

struct BounceKeyframe: Equatable {
    let percent: Double   // 0...100 along the cycle
    let translateY: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
}

struct HeartKeyframe: Equatable {
    let percent: Double   // 0...100 along the cycle
    let scale: CGFloat
}

struct RingKeyframe: Equatable {
    let percent: Double   // 0...100 along the cycle
    let rotation: Double  // degrees, anchored near glyph top (0.5, 0.1)
}

struct RageKeyframe: Equatable {
    let percent: Double   // 0...100 along the 0.95s throw-windup window
    let rotation: Double  // degrees, anchored at glyph bottom-mid (0.5, 0.9)
    let translateX: CGFloat
    let translateY: CGFloat
    let scale: CGFloat
}

enum MotionKeyframes {
    // HTML bounce-cute is 0.9s ease-in-out infinite (Prototype v2 line 101).
    static let bouncePeriod: TimeInterval = 0.9

    // HTML @keyframes bounce-cute (Prototype v2 lines 117–123).
    // Bottom squash (1.04, 0.94) → apex stretch (0.97, 1.05) → bottom squash.
    static let bounceCycle: [BounceKeyframe] = [
        BounceKeyframe(percent:   0, translateY:  0, scaleX: 1.04, scaleY: 0.94),
        BounceKeyframe(percent:  18, translateY: -2, scaleX: 1.01, scaleY: 0.99),
        BounceKeyframe(percent:  50, translateY: -5, scaleX: 0.97, scaleY: 1.05),
        BounceKeyframe(percent:  82, translateY: -2, scaleX: 1.01, scaleY: 0.99),
        BounceKeyframe(percent: 100, translateY:  0, scaleX: 1.04, scaleY: 0.94),
    ]

    // HTML heartbeat is 1.4s ease-in-out infinite (Prototype v2 line 106).
    static let heartPeriod: TimeInterval = 1.4

    // HTML @keyframes heartbeat (Prototype v2 lines 147–153).
    // Double-pulse: peak 1 at 14% (1.14), peak 2 at 42% (1.08), then idle.
    static let heartCycle: [HeartKeyframe] = [
        HeartKeyframe(percent:   0, scale: 1.00),
        HeartKeyframe(percent:  14, scale: 1.14),
        HeartKeyframe(percent:  28, scale: 1.00),
        HeartKeyframe(percent:  42, scale: 1.08),
        HeartKeyframe(percent:  56, scale: 1.00),
        HeartKeyframe(percent: 100, scale: 1.00),
    ]

    // HTML ring is 1.4s ease-in-out infinite (Prototype v2 line 107).
    static let ringPeriod: TimeInterval = 1.4

    // HTML @keyframes ring (Prototype v2 lines 154–162).
    // Damped bell swing; starts and ends at 0 so the loop does not snap.
    static let ringCycle: [RingKeyframe] = [
        RingKeyframe(percent:   0, rotation:   0),
        RingKeyframe(percent:  10, rotation: -14),
        RingKeyframe(percent:  20, rotation:  12),
        RingKeyframe(percent:  30, rotation:  -9),
        RingKeyframe(percent:  40, rotation:   7),
        RingKeyframe(percent:  50, rotation:  -4),
        RingKeyframe(percent:  60, rotation:   2),
        RingKeyframe(percent: 100, rotation:   0),
    ]

    // HTML throw-windup is 950ms cubic-bezier(.5, 0, .3, 1) (Prototype v2 line 655),
    // looped on a 2.4s rage interval (line 1346). Transform origin: 50% 90% (line 656).
    static let rageWindupDuration: TimeInterval = 0.95
    static let ragePeriod: TimeInterval = 2.4
    static let rageHoldDuration: TimeInterval = ragePeriod - rageWindupDuration // 1.45s rest

    // HTML @keyframes throw-windup (Prototype v2 lines 658–666).
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
}
