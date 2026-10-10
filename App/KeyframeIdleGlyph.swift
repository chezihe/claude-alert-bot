// App/KeyframeIdleGlyph.swift — KeyframeAnimator-driven idle motions (bounce / heart / rage / ring).
// Bounce: 0.9s HTML-faithful 4-track squash-and-stretch (translateY + scaleX + scaleY + rotation).
// Heart: 1.4s single scale track, double-pulse at 14% / 42%.
// Rage: 0.95s throw-windup + 1.45s hold = 2.4s loop (projectile lives in RageProjectileLoop).
// Ring: 1.4s damped bell swing + micro-aftershock.
// Each KeyframeAnimator owns its own lifecycle: switching idle modes unmounts the branch,
// so there is never a leaked `.repeatForever` to cancel.
import SwiftUI

/// Per-frame transform inputs for the widget glyph. Defaults are the at-rest values.
struct GlyphMotion {
    var bounce = BounceAnimatorValue()
    var heartScale: CGFloat = 1.0
    var rage = RageAnimatorValue()
    var ringRotation: Double = 0
}

struct KeyframeIdleGlyph<Content: View>: View {
    let idle: IdleAnimation
    @ViewBuilder let content: (GlyphMotion) -> Content

    var body: some View {
        switch idle {
        case .bounce:
            KeyframeAnimator(initialValue: BounceAnimatorValue(), repeating: true) { value in
                content(GlyphMotion(bounce: value))
            } keyframes: { _ in
                KeyframeTrack(\.translateY) {
                    for step in MotionKeyframes.bounceSteps {
                        CubicKeyframe(step.frame.translateY, duration: step.duration)
                    }
                }
                KeyframeTrack(\.scaleX) {
                    for step in MotionKeyframes.bounceSteps {
                        CubicKeyframe(step.frame.scaleX, duration: step.duration)
                    }
                }
                KeyframeTrack(\.scaleY) {
                    for step in MotionKeyframes.bounceSteps {
                        CubicKeyframe(step.frame.scaleY, duration: step.duration)
                    }
                }
                KeyframeTrack(\.rotation) {
                    for step in MotionKeyframes.bounceSteps {
                        CubicKeyframe(step.frame.rotation, duration: step.duration)
                    }
                }
            }
        case .heart:
            KeyframeAnimator(initialValue: HeartAnimatorValue(), repeating: true) { value in
                content(GlyphMotion(heartScale: value.scale))
            } keyframes: { _ in
                KeyframeTrack(\.scale) {
                    for step in MotionKeyframes.heartSteps {
                        CubicKeyframe(step.frame.scale, duration: step.duration)
                    }
                }
            }
        case .rage:
            KeyframeAnimator(initialValue: RageAnimatorValue(), repeating: true) { value in
                content(GlyphMotion(rage: value))
            } keyframes: { (_: RageAnimatorValue) in
                KeyframeTrack(\.rotation) {
                    for step in MotionKeyframes.rageSteps {
                        CubicKeyframe(step.frame.rotation, duration: step.duration)
                    }
                }
                KeyframeTrack(\.translateX) {
                    for step in MotionKeyframes.rageSteps {
                        CubicKeyframe(step.frame.translateX, duration: step.duration)
                    }
                }
                KeyframeTrack(\.translateY) {
                    for step in MotionKeyframes.rageSteps {
                        CubicKeyframe(step.frame.translateY, duration: step.duration)
                    }
                }
                KeyframeTrack(\.scale) {
                    for step in MotionKeyframes.rageSteps {
                        CubicKeyframe(step.frame.scale, duration: step.duration)
                    }
                }
            }
        case .ring:
            KeyframeAnimator(initialValue: RingAnimatorValue(), repeating: true) { value in
                content(GlyphMotion(ringRotation: value.rotation))
            } keyframes: { (_: RingAnimatorValue) in
                KeyframeTrack(\.rotation) {
                    for step in MotionKeyframes.ringSteps {
                        CubicKeyframe(step.frame.rotation, duration: step.duration)
                    }
                }
            }
        case .roam:
            // Not keyframe-driven; see RoamIdleMotion.
            content(GlyphMotion())
        }
    }
}

struct BounceAnimatorValue {
    var translateY: CGFloat = MotionKeyframes.bounceCycle[0].translateY
    var scaleX: CGFloat = MotionKeyframes.bounceCycle[0].scaleX
    var scaleY: CGFloat = MotionKeyframes.bounceCycle[0].scaleY
    var rotation: Double = MotionKeyframes.bounceCycle[0].rotation
}

struct HeartAnimatorValue {
    var scale: CGFloat = MotionKeyframes.heartCycle[0].scale
}

struct RageAnimatorValue {
    var rotation: Double = MotionKeyframes.rageCycle[0].rotation
    var translateX: CGFloat = MotionKeyframes.rageCycle[0].translateX
    var translateY: CGFloat = MotionKeyframes.rageCycle[0].translateY
    var scale: CGFloat = MotionKeyframes.rageCycle[0].scale
}

struct RingAnimatorValue {
    var rotation: Double = 0
}
