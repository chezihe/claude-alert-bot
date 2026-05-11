// App/MotionKeyframes.swift — Phase 1 motion rework.
// Pure keyframe data (no view code). Source of truth: HTML prototype
// `Claude Alert Bot - Prototype v2.html` @keyframes bounce-cute (117–123)
// and @keyframes heartbeat (147–153). Loop-continuous; consumed by
// WidgetIconView's KeyframeAnimator multi-track wiring.
import CoreGraphics
import Foundation

struct BounceKeyframe: Equatable {
    let percent: Double   // 0...100 along the cycle
    let translateY: CGFloat
    let scaleX: CGFloat
    let scaleY: CGFloat
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
}
