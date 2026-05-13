// App/WidgetIconView.swift — Phase 2 WIDG-03 (icon + project name location).
// UI-SPEC: 36pt Claude Code glyph, 4pt internal padding (44pt total).
// +N badge: 16pt-min capsule, accent-dark fill (gray in Quiet Hours), white SF Pro 9.5pt text.
// Anchored top-trailing inside the panel bounds to avoid clipping at screen edges.
// Bounce: 0.9s HTML-faithful KeyframeAnimator (translateY + scaleX + scaleY 3-track).
//         Mirrors @keyframes bounce-cute squash-and-stretch; suppressed when Reduce Motion / Quiet Hours.
// Breathe: 2.4s scale 1.0↔1.06, autoreverse forever; default idle animation for WO-012.
// Heart: 1.4s HTML-faithful KeyframeAnimator (single scale track) anchored at center.
//        Mirrors @keyframes heartbeat double-pulse at 14% / 42%; suppressed in Quiet Hours / Reduce Motion.
// Ring: 1.4s HTML-faithful damped bell swing from near-top anchor; suppressed when Reduce Motion is on.
// Roam: 1.6s counter-clockwise 24×6pt ellipse, linear forever; suppressed when Reduce Motion is on.
// Drift: 6s random jitter within 14×16pt, easeInOut forever; suppressed when Reduce Motion is on.
// New-alert pulse: scale/rotate glyph + one sonar ring; suppressed in Quiet Hours.
import SwiftUI
import AppKit

struct WidgetIconView: View {
    let pendingCount: Int
    var idleAnimation: IdleAnimation = .default
    var alertPulseID: Int = 0
    var quietHoursEnabled: Bool = false
    var reduceMotionPreference: ReduceMotionPreference = .system

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var roamPhase: Double = 0
    @State private var rageGeneration: Int = 0
    @State private var rageActive: Bool = false
    @State private var rageWorkItem: DispatchWorkItem?
    @State private var alertPulseScale: CGFloat = 1.0
    @State private var alertPulseRotation: Double = 0
    @State private var sonarScale: CGFloat = MotionTokens.sonarStartScale
    @State private var sonarOpacity: Double = 0
    @State private var activeAlertPulseID: Int = 0
    @State private var alertPulseGeneration: Int = 0
    @State private var badgePopScale: CGFloat = 1.0
    @State private var magicProgress: Double = 0
    @State private var magicBurstID: Int = 0
    @State private var magicBurstActive: Bool = false
    @State private var magicBurstStartedAt: Date = .distantPast
    @State private var magicBurstWorkItem: DispatchWorkItem? = nil
    @State private var lastBadgeKey: Int = -1

    private static let badgeOffset = CGSize(width: -1, height: 1)
    private static let fixedGlyphOffset = CGSize(width: 0, height: 6)
    // Pivot sits on the icon's right arm (the "hand") so the wand reads as held by it.
    private static let magicWandOffset = CGSize(width: 16, height: -4)
    private static let magicWandBaseRotation: Double = 32
    private static let magicWandSwingAmplitude: Double = 12
    private static let magicStarCount: Int = 6
    // Seeded horizontal offsets keep stars spread across the icon without runtime RNG.
    private static let magicStarHorizontalOffsets: [CGFloat] = [-14, 8, -4, 12, -10, 2]

    private var reduceMotion: Bool {
        reduceMotionPreference.effectiveReduceMotion(systemReduceMotion: systemReduceMotion)
    }

    private var widgetBoundsSize: CGSize {
        GeometryTokens.widgetDrawableSize(
            idleAnimation: idleAnimation,
            quietHoursEnabled: quietHoursEnabled,
            reduceMotion: reduceMotion
        )
    }

    private var bounceAnimatorActive: Bool {
        idleAnimation == .bounce && !quietHoursEnabled && !reduceMotion
    }

    private var heartAnimatorActive: Bool {
        idleAnimation == .heart && !quietHoursEnabled && !reduceMotion
    }

    private var rageAnimatorActive: Bool {
        idleAnimation == .rage && !quietHoursEnabled && !reduceMotion
    }

    private var ringAnimatorActive: Bool {
        idleAnimation == .ring && !quietHoursEnabled && !reduceMotion
    }

    private var magicAnimatorActive: Bool {
        idleAnimation == .magic && !quietHoursEnabled && !reduceMotion
    }

    var body: some View {
        ZStack(alignment: .center) {
            ZStack(alignment: .topTrailing) {
                if sonarOpacity > 0, !quietHoursEnabled {
                    Circle()
                        .strokeBorder(ColorTokens.accent.opacity(sonarOpacity), lineWidth: 1.5)
                        .frame(width: MotionTokens.sonarBaseDiameter, height: MotionTokens.sonarBaseDiameter)
                        .scaleEffect(sonarScale)
                        .frame(width: GeometryTokens.widgetBaseSize.width, height: GeometryTokens.widgetBaseSize.height, alignment: .center)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                // Non-SPEC literals retained per Finding F-2 (see 03.1-01-SUMMARY.md):
                // floating-widget topology differs from SPEC §3 NSStatusItem 22pt-in-28pt + badge offsets.
                if bounceAnimatorActive {
                    KeyframeAnimator(
                        initialValue: BounceAnimatorValue(),
                        repeating: true
                    ) { value in
                        glyph(bounceValue: value, heartScale: 1.0, rageValue: RageAnimatorValue())
                    } keyframes: { _ in
                        KeyframeTrack(\.translateY) {
                            CubicKeyframe(MotionKeyframes.bounceCycle[1].translateY,
                                          duration: MotionKeyframes.bouncePeriod * 0.18)
                            CubicKeyframe(MotionKeyframes.bounceCycle[2].translateY,
                                          duration: MotionKeyframes.bouncePeriod * 0.32)
                            CubicKeyframe(MotionKeyframes.bounceCycle[3].translateY,
                                          duration: MotionKeyframes.bouncePeriod * 0.32)
                            CubicKeyframe(MotionKeyframes.bounceCycle[4].translateY,
                                          duration: MotionKeyframes.bouncePeriod * 0.18)
                        }
                        KeyframeTrack(\.scaleX) {
                            CubicKeyframe(MotionKeyframes.bounceCycle[1].scaleX,
                                          duration: MotionKeyframes.bouncePeriod * 0.18)
                            CubicKeyframe(MotionKeyframes.bounceCycle[2].scaleX,
                                          duration: MotionKeyframes.bouncePeriod * 0.32)
                            CubicKeyframe(MotionKeyframes.bounceCycle[3].scaleX,
                                          duration: MotionKeyframes.bouncePeriod * 0.32)
                            CubicKeyframe(MotionKeyframes.bounceCycle[4].scaleX,
                                          duration: MotionKeyframes.bouncePeriod * 0.18)
                        }
                        KeyframeTrack(\.scaleY) {
                            CubicKeyframe(MotionKeyframes.bounceCycle[1].scaleY,
                                          duration: MotionKeyframes.bouncePeriod * 0.18)
                            CubicKeyframe(MotionKeyframes.bounceCycle[2].scaleY,
                                          duration: MotionKeyframes.bouncePeriod * 0.32)
                            CubicKeyframe(MotionKeyframes.bounceCycle[3].scaleY,
                                          duration: MotionKeyframes.bouncePeriod * 0.32)
                            CubicKeyframe(MotionKeyframes.bounceCycle[4].scaleY,
                                          duration: MotionKeyframes.bouncePeriod * 0.18)
                        }
                    }
                } else if heartAnimatorActive {
                    KeyframeAnimator(
                        initialValue: HeartAnimatorValue(),
                        repeating: true
                    ) { value in
                        glyph(bounceValue: BounceAnimatorValue(), heartScale: value.scale, rageValue: RageAnimatorValue())
                    } keyframes: { _ in
                        KeyframeTrack(\.scale) {
                            CubicKeyframe(MotionKeyframes.heartCycle[1].scale,
                                          duration: MotionKeyframes.heartPeriod * 0.14)
                            CubicKeyframe(MotionKeyframes.heartCycle[2].scale,
                                          duration: MotionKeyframes.heartPeriod * 0.14)
                            CubicKeyframe(MotionKeyframes.heartCycle[3].scale,
                                          duration: MotionKeyframes.heartPeriod * 0.14)
                            CubicKeyframe(MotionKeyframes.heartCycle[4].scale,
                                          duration: MotionKeyframes.heartPeriod * 0.14)
                            CubicKeyframe(MotionKeyframes.heartCycle[5].scale,
                                          duration: MotionKeyframes.heartPeriod * 0.44)
                        }
                    }
                } else if rageAnimatorActive {
                    KeyframeAnimator(
                        initialValue: RageAnimatorValue(),
                        repeating: true
                    ) { value in
                        glyph(bounceValue: BounceAnimatorValue(), heartScale: 1.0, rageValue: value)
                    } keyframes: { (_: RageAnimatorValue) in
                        // 7 throw-windup keyframes (0–100%) spread across 0.95s,
                        // followed by a 1.45s hold at identity so the cycle loops at HTML's 2.4s rage interval.
                        KeyframeTrack(\.rotation) {
                            CubicKeyframe(MotionKeyframes.rageCycle[1].rotation, duration: MotionKeyframes.rageWindupDuration * 0.18)
                            CubicKeyframe(MotionKeyframes.rageCycle[2].rotation, duration: MotionKeyframes.rageWindupDuration * 0.12)
                            CubicKeyframe(MotionKeyframes.rageCycle[3].rotation, duration: MotionKeyframes.rageWindupDuration * 0.14)
                            CubicKeyframe(MotionKeyframes.rageCycle[4].rotation, duration: MotionKeyframes.rageWindupDuration * 0.14)
                            CubicKeyframe(MotionKeyframes.rageCycle[5].rotation, duration: MotionKeyframes.rageWindupDuration * 0.20)
                            CubicKeyframe(MotionKeyframes.rageCycle[6].rotation, duration: MotionKeyframes.rageWindupDuration * 0.22)
                            CubicKeyframe(MotionKeyframes.rageCycle[6].rotation, duration: MotionKeyframes.rageHoldDuration)
                        }
                        KeyframeTrack(\.translateX) {
                            CubicKeyframe(MotionKeyframes.rageCycle[1].translateX, duration: MotionKeyframes.rageWindupDuration * 0.18)
                            CubicKeyframe(MotionKeyframes.rageCycle[2].translateX, duration: MotionKeyframes.rageWindupDuration * 0.12)
                            CubicKeyframe(MotionKeyframes.rageCycle[3].translateX, duration: MotionKeyframes.rageWindupDuration * 0.14)
                            CubicKeyframe(MotionKeyframes.rageCycle[4].translateX, duration: MotionKeyframes.rageWindupDuration * 0.14)
                            CubicKeyframe(MotionKeyframes.rageCycle[5].translateX, duration: MotionKeyframes.rageWindupDuration * 0.20)
                            CubicKeyframe(MotionKeyframes.rageCycle[6].translateX, duration: MotionKeyframes.rageWindupDuration * 0.22)
                            CubicKeyframe(MotionKeyframes.rageCycle[6].translateX, duration: MotionKeyframes.rageHoldDuration)
                        }
                        KeyframeTrack(\.translateY) {
                            CubicKeyframe(MotionKeyframes.rageCycle[1].translateY, duration: MotionKeyframes.rageWindupDuration * 0.18)
                            CubicKeyframe(MotionKeyframes.rageCycle[2].translateY, duration: MotionKeyframes.rageWindupDuration * 0.12)
                            CubicKeyframe(MotionKeyframes.rageCycle[3].translateY, duration: MotionKeyframes.rageWindupDuration * 0.14)
                            CubicKeyframe(MotionKeyframes.rageCycle[4].translateY, duration: MotionKeyframes.rageWindupDuration * 0.14)
                            CubicKeyframe(MotionKeyframes.rageCycle[5].translateY, duration: MotionKeyframes.rageWindupDuration * 0.20)
                            CubicKeyframe(MotionKeyframes.rageCycle[6].translateY, duration: MotionKeyframes.rageWindupDuration * 0.22)
                            CubicKeyframe(MotionKeyframes.rageCycle[6].translateY, duration: MotionKeyframes.rageHoldDuration)
                        }
                        KeyframeTrack(\.scale) {
                            CubicKeyframe(MotionKeyframes.rageCycle[1].scale, duration: MotionKeyframes.rageWindupDuration * 0.18)
                            CubicKeyframe(MotionKeyframes.rageCycle[2].scale, duration: MotionKeyframes.rageWindupDuration * 0.12)
                            CubicKeyframe(MotionKeyframes.rageCycle[3].scale, duration: MotionKeyframes.rageWindupDuration * 0.14)
                            CubicKeyframe(MotionKeyframes.rageCycle[4].scale, duration: MotionKeyframes.rageWindupDuration * 0.14)
                            CubicKeyframe(MotionKeyframes.rageCycle[5].scale, duration: MotionKeyframes.rageWindupDuration * 0.20)
                            CubicKeyframe(MotionKeyframes.rageCycle[6].scale, duration: MotionKeyframes.rageWindupDuration * 0.22)
                            CubicKeyframe(MotionKeyframes.rageCycle[6].scale, duration: MotionKeyframes.rageHoldDuration)
                        }
                    }
                } else if magicAnimatorActive {
                    // Magic = Float Sway (sin hover + sin tilt) with a Sparkle Burst accent
                    // every magicBurstInterval seconds: 360° CCW spin + 12 radial stars.
                    // TimelineView drives per-frame sin values; burst rotation/stars derive
                    // from magicBurstStartedAt + magicBurstActive (scheduled by DispatchQueue).
                    TimelineView(.animation) { context in
                        let now = context.date.timeIntervalSinceReferenceDate
                        let hoverY = CGFloat(sin(now / MotionKeyframes.magicHoverPeriod * 2 * .pi))
                                     * MotionKeyframes.magicHoverAmplitude
                        let tiltDeg = sin(now / MotionKeyframes.magicTiltPeriod * 2 * .pi)
                                      * MotionKeyframes.magicTiltAmplitude
                        let burstPhase = currentMagicBurstPhase(at: context.date)
                        // Ease-in-out so the spin doesn't snap at start/end.
                        let easedSpin = burstSpinEase(burstPhase)
                        let burstRotation = easedSpin * MotionKeyframes.magicBurstRotation
                        glyph(
                            bounceValue: BounceAnimatorValue(translateY: hoverY, scaleX: 1, scaleY: 1),
                            heartScale: 1.0,
                            rageValue: RageAnimatorValue()
                        )
                        // Tilt stays on the in-plane axis (subtle lean), burst spins on Y
                        // (vertical axis) so the icon turns like a figure-skater / magical-girl
                        // transformation — side → back → side → front — not like a clock hand.
                        .rotationEffect(.degrees(tiltDeg), anchor: .center)
                        .rotation3DEffect(
                            .degrees(burstRotation),
                            axis: (x: 0, y: 1, z: 0),
                            anchor: .center,
                            perspective: 0.6
                        )
                        .overlay(alignment: .center) {
                            magicAnimationOverlay
                        }
                    }
                } else if ringAnimatorActive {
                    // KeyframeAnimator owns its own lifecycle, so switching idle to anything else
                    // removes this branch and the rotation snaps back to 0 (no leaked `.repeatForever`).
                    KeyframeAnimator(
                        initialValue: RingAnimatorValue(),
                        repeating: true
                    ) { value in
                        glyph(bounceValue: BounceAnimatorValue(), heartScale: 1.0, rageValue: RageAnimatorValue(), ringRotation: value.rotation)
                    } keyframes: { (_: RingAnimatorValue) in
                        KeyframeTrack(\.rotation) {
                            CubicKeyframe(MotionKeyframes.ringCycle[1].rotation, duration: MotionKeyframes.ringPeriod * 0.10)
                            CubicKeyframe(MotionKeyframes.ringCycle[2].rotation, duration: MotionKeyframes.ringPeriod * 0.10)
                            CubicKeyframe(MotionKeyframes.ringCycle[3].rotation, duration: MotionKeyframes.ringPeriod * 0.10)
                            CubicKeyframe(MotionKeyframes.ringCycle[4].rotation, duration: MotionKeyframes.ringPeriod * 0.10)
                            CubicKeyframe(MotionKeyframes.ringCycle[5].rotation, duration: MotionKeyframes.ringPeriod * 0.10)
                            CubicKeyframe(MotionKeyframes.ringCycle[6].rotation, duration: MotionKeyframes.ringPeriod * 0.10)
                            CubicKeyframe(MotionKeyframes.ringCycle[7].rotation, duration: MotionKeyframes.ringPeriod * 0.40)
                        }
                    }
                } else {
                    glyph(bounceValue: BounceAnimatorValue(), heartScale: 1.0, rageValue: RageAnimatorValue())
                }
                if pendingCount >= 2 {
                    badgeView
                }
            }
            .frame(width: GeometryTokens.widgetBaseSize.width, height: GeometryTokens.widgetBaseSize.height, alignment: .center)
        }
        // Magic biases the extra width to the right of the icon (the wand "lives" there).
        .frame(width: widgetBoundsSize.width, height: widgetBoundsSize.height, alignment: magicAnimatorActive ? .leading : .center)
        .accessibilityElement()
        .accessibilityLabel(widgetAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func glyph(
        bounceValue: BounceAnimatorValue,
        heartScale: CGFloat,
        rageValue: RageAnimatorValue,
        ringRotation: Double = 0
    ) -> some View {
        Image("ClaudeCodeIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 36, height: 36)
            .frame(width: GeometryTokens.widgetBaseSize.width, height: GeometryTokens.widgetBaseSize.height)
            .scaleEffect(
                x: quietHoursEnabled ? 1.0 : bounceValue.scaleX,
                y: quietHoursEnabled ? 1.0 : bounceValue.scaleY,
                anchor: .bottom
            )
            .scaleEffect(quietHoursEnabled ? 1.0 : heartScale * alertPulseScale, anchor: .center)
            .rotationEffect(.degrees(quietHoursEnabled ? 0 : alertPulseRotation + ringRotation), anchor: UnitPoint(x: 0.5, y: 0.1))
            .offset(
                x: Self.fixedGlyphOffset.width,
                y: (quietHoursEnabled ? 0 : bounceValue.translateY) + Self.fixedGlyphOffset.height
            )
            // Rage throw-windup applied last so it dominates other transforms while looping.
            // Internal prototype transform-origin: 50% 90%.
            .scaleEffect(rageValue.scale, anchor: UnitPoint(x: 0.5, y: 0.9))
            .rotationEffect(.degrees(rageValue.rotation), anchor: UnitPoint(x: 0.5, y: 0.9))
            .offset(x: rageValue.translateX, y: rageValue.translateY)
            .modifier(RoamOffsetEffect(
                angle: roamPhase,
                radiusX: Double(MotionTokens.roamRadiusX),
                radiusY: Double(MotionTokens.roamRadiusY),
                isActive: idleAnimation == .roam && !quietHoursEnabled && !reduceMotion
            ))
            .onAppear {
                startIdleAnimation()
                runNewAlertPulse()
                primeBadgePop()
                restartRageProjectileLoop()
                restartMagicBurstLoop()
            }
            .onDisappear {
                stopRageProjectileLoop()
                stopMagicBurstLoop()
            }
            .onChange(of: quietHoursEnabled) { _, _ in
                resetAlertPulse()
                restartIdleAnimation()
                restartRageProjectileLoop()
                restartMagicBurstLoop()
            }
            .onChange(of: idleAnimation) { _, _ in
                restartIdleAnimation()
                restartRageProjectileLoop()
                restartMagicBurstLoop()
            }
            .onChange(of: reduceMotion) { _, _ in
                resetAlertPulse()
                restartIdleAnimation()
                restartRageProjectileLoop()
                restartMagicBurstLoop()
            }
            .onChange(of: alertPulseID) { _, _ in
                runNewAlertPulse()
            }
            .onChange(of: pendingCount) { _, _ in
                runBadgePop()
            }
    }

    private var magicAnimationOverlay: some View {
        let swing = sin((magicProgress * 2 * .pi) - (.pi / 2))
        let swingRotation = (swing * Self.magicWandSwingAmplitude) + Self.magicWandBaseRotation
        return ZStack {
            magicFallingStars
            magicWand(rotationDegrees: swingRotation)
        }
        .frame(
            width: GeometryTokens.widgetBaseSize.width + GeometryTokens.magicDrawableExtraWidth,
            height: GeometryTokens.widgetBaseSize.height + GeometryTokens.magicDrawableExtraHeight,
            alignment: .center
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func currentMagicBurstPhase(at date: Date) -> Double {
        guard magicBurstActive else { return 0 }
        let elapsed = date.timeIntervalSince(magicBurstStartedAt)
        guard elapsed >= 0 else { return 0 }
        return min(1, elapsed / MotionKeyframes.magicBurstDuration)
    }

    // Smooth ease-in-out (cosine) so the spin starts and ends without a jolt.
    private func burstSpinEase(_ phase: Double) -> Double {
        guard phase > 0, phase < 1 else { return phase }
        return (1 - cos(phase * .pi)) / 2
    }

    private func magicWand(rotationDegrees: Double) -> some View {
        VStack(spacing: 3) {
            Circle()
                .frame(width: 4, height: 4)
                .foregroundStyle(Color(red: 1, green: 0.98, blue: 0.9))
            Capsule()
                .frame(width: 2, height: 14)
                .foregroundStyle(Color(red: 0xEE / 255, green: 0xF7 / 255, blue: 0xFF / 255))
        }
        .offset(x: Self.magicWandOffset.width, y: Self.magicWandOffset.height)
        .rotationEffect(.degrees(rotationDegrees), anchor: .bottom)
        .allowsHitTesting(false)
    }

    // Six bright sparkles drift downward through the icon on a 3s loop, staggered so two
    // or three are visible at any moment (medium-intensity preset). TimelineView drives
    // continuous redraws — the parent overlay already gates render on magicAnimatorActive,
    // so Reduce Motion / Quiet Hours unmount this entirely.
    private var magicFallingStars: some View {
        TimelineView(.animation) { context in
            let now = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<Self.magicStarCount, id: \.self) { index in
                    magicStar(index: index, now: now)
                }
            }
        }
    }

    private func magicStar(index: Int, now: TimeInterval) -> some View {
        let period = MotionTokens.magicAnimationDuration
        let stagger = Double(index) / Double(Self.magicStarCount)
        let raw = (now / period) + stagger
        let phase = raw - floor(raw)
        let yOffset = MotionTokens.magicStarStartOffset + CGFloat(phase) * MotionTokens.magicStarTravelDistance
        let xOffset = Self.magicStarHorizontalOffsets[index % Self.magicStarHorizontalOffsets.count]
        // sin(πφ) → fades in for the first half of the fall and fades out by the end.
        let opacity = sin(phase * .pi)
        return Image(systemName: "sparkle")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: MotionTokens.magicStarSize, height: MotionTokens.magicStarSize)
            .foregroundStyle(Color(red: 1, green: 0.96, blue: 0.78))
            .shadow(color: Color(red: 1, green: 0.92, blue: 0.55).opacity(0.55), radius: 1.5)
            .opacity(opacity)
            .offset(x: xOffset, y: yOffset)
    }

    @ViewBuilder
    private var badgeView: some View {
        let fill = quietHoursEnabled
            ? Color(red: 0x6B/255, green: 0x6B/255, blue: 0x75/255)
            : ColorTokens.accentDark
        Text("+\(pendingCount)")
            .font(.system(size: 9.5))
            .foregroundStyle(Color(red: 0xFF/255, green: 0xF4/255, blue: 0xEC/255))
            .padding(.horizontal, 4)
            .frame(minWidth: 16, minHeight: 16)
            .background(
                Capsule(style: .continuous).fill(fill)
            )
            .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 1)
            .scaleEffect(badgePopScale)
            .offset(x: Self.badgeOffset.width, y: Self.badgeOffset.height)
            .accessibilityHidden(true)
    }

    private var widgetAccessibilityLabel: String {
        let sessionCount = pendingCount == 1 ? "1 pending session" : "\(pendingCount) pending sessions"
        let quietSuffix = quietHoursEnabled ? ". Quiet Hours" : ""
        return "Claude alert. \(sessionCount)\(quietSuffix)"
    }

    private func startIdleAnimation() {
        guard !quietHoursEnabled else { return }
        // Phase 03.1: consume MotionTokens (SC#1, SC#3 uniform reduce-motion gate).
        switch idleAnimation {
        case .bounce, .heart, .rage, .ring:
            // Bounce / Heart / Rage / Ring are driven by KeyframeAnimator wrappers around the
            // glyph (see `body`). They own their own lifecycle so switching idle modes unmounts
            // the previous branch and there is no lingering animation to cancel.
            return
        case .roam:
            guard let anim = MotionTokens.roamAnimation(reduceMotion: reduceMotion) else { return }
            withAnimation(anim) {
                roamPhase = -360
            }
        case .magic:
            guard !reduceMotion else {
                magicProgress = 0
                return
            }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                magicProgress = 1
            }
        }
    }

    private func restartIdleAnimation() {
        // Roam's `.repeatForever` keeps interpolating `roamPhase` even after the user switches
        // idle styles. Snapping the reset through a `nil` transaction cancels the in-flight
        // animation on that property. (Ring used to leak the same way; Phase-2 fix migrated
        // Ring to a KeyframeAnimator branch that unmounts cleanly, so no rotation reset is
        // needed here any more.)
        withTransaction(Transaction(animation: nil)) {
            roamPhase = 0
            magicProgress = 0
        }
        startIdleAnimation()
    }

    // HTML @keyframes badge-pop — scale 0→1 with cubic-bezier(.34,1.6,.5,1).
    // SwiftUI spring (response 0.22, damping 0.55) reproduces the overshoot tail.
    private func primeBadgePop() {
        lastBadgeKey = pendingCount
        if pendingCount >= 2 {
            badgePopScale = 0
            withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) {
                badgePopScale = 1
            }
        } else {
            badgePopScale = 1
        }
    }

    private func runBadgePop() {
        guard pendingCount >= 2 else {
            badgePopScale = 1
            lastBadgeKey = pendingCount
            return
        }
        // Re-pop only when the visible "+N" string would change, matching HTML's behaviour:
        // the badge does not bounce on every queue mutation, only when the displayed number moves.
        if lastBadgeKey != pendingCount {
            lastBadgeKey = pendingCount
            badgePopScale = 0
            withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) {
                badgePopScale = 1
            }
        }
    }

    // Internal prototype rage loop: every 2.4s while idleAnimation == .rage,
    // throw a MacBook projectile. The glyph KeyframeAnimator already loops the throw-windup
    // on its own; this helper handles the separate window-level projectile + impact burst.
    // Timed to fire at peak forward whip (44% of windup ≈ 418ms after each cycle start).
    private func restartRageProjectileLoop() {
        stopRageProjectileLoop()
        guard rageAnimatorActive else { return }
        rageGeneration += 1
        let generation = rageGeneration
        scheduleNextRageProjectile(generation: generation, delay: MotionKeyframes.rageWindupDuration * 0.44)
    }

    private func stopRageProjectileLoop() {
        rageGeneration += 1
        rageWorkItem?.cancel()
        rageWorkItem = nil
    }

    private func scheduleNextRageProjectile(generation: Int, delay: TimeInterval) {
        let workItem = DispatchWorkItem {
            guard generation == rageGeneration, rageAnimatorActive else { return }
            MacBookProjectileLauncher.shared.launchFromWidget()
            scheduleNextRageProjectile(generation: generation, delay: MotionKeyframes.ragePeriod)
        }
        rageWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    // Magic burst loop: every magicBurstInterval seconds, mark a burst window magicBurstDuration
    // long. The body's TimelineView reads magicBurstActive / magicBurstStartedAt to drive the
    // CCW 360° spin and the 12 radial sparkles. Mirrors restartRageProjectileLoop's generation
    // pattern so toggling idle modes can't leak a stale work item.
    private func restartMagicBurstLoop() {
        stopMagicBurstLoop()
        guard magicAnimatorActive else { return }
        magicBurstID &+= 1
        let generation = magicBurstID
        scheduleNextMagicBurst(generation: generation, delay: MotionKeyframes.magicBurstInterval)
    }

    private func stopMagicBurstLoop() {
        magicBurstID &+= 1
        magicBurstWorkItem?.cancel()
        magicBurstWorkItem = nil
        magicBurstActive = false
    }

    private func scheduleNextMagicBurst(generation: Int, delay: TimeInterval) {
        let workItem = DispatchWorkItem {
            guard generation == magicBurstID, magicAnimatorActive else { return }
            triggerMagicBurst(generation: generation)
            scheduleNextMagicBurst(generation: generation, delay: MotionKeyframes.magicBurstInterval)
        }
        magicBurstWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func triggerMagicBurst(generation: Int) {
        magicBurstStartedAt = Date()
        magicBurstActive = true
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionKeyframes.magicBurstDuration) {
            guard generation == magicBurstID else { return }
            magicBurstActive = false
        }
    }


    private func runNewAlertPulse() {
        guard alertPulseID > 0, alertPulseID != activeAlertPulseID, !quietHoursEnabled else { return }
        let pulseID = alertPulseID
        activeAlertPulseID = pulseID
        alertPulseGeneration += 1
        let pulseGeneration = alertPulseGeneration
        alertPulseScale = 1.0
        alertPulseRotation = 0
        sonarScale = MotionTokens.sonarStartScale
        sonarOpacity = MotionTokens.sonarStartOpacity

        if reduceMotion {
            withAnimation(.linear(duration: MotionTokens.reduceMotionFadeDuration)) {
                sonarOpacity = 0
            }
            return
        }

        withAnimation(.easeOut(duration: MotionTokens.sonarDuration)) {
            sonarScale = MotionTokens.sonarEndScale
            sonarOpacity = 0
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
            alertPulseScale = MotionTokens.newAlertPulsePeakScale
            alertPulseRotation = MotionTokens.newAlertPulseRotation
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionTokens.newAlertPulseDuration * 0.25) {
            guard activeAlertPulseID == pulseID, alertPulseGeneration == pulseGeneration else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                alertPulseScale = MotionTokens.newAlertPulseSquashScale
                alertPulseRotation = -MotionTokens.newAlertPulseRotation
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionTokens.newAlertPulseDuration * 0.5) {
            guard activeAlertPulseID == pulseID, alertPulseGeneration == pulseGeneration else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                alertPulseScale = MotionTokens.newAlertPulseSettleScale
                alertPulseRotation = MotionTokens.newAlertPulseRotation * 0.5
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionTokens.newAlertPulseDuration) {
            guard activeAlertPulseID == pulseID, alertPulseGeneration == pulseGeneration else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                alertPulseScale = 1.0
                alertPulseRotation = 0
            }
        }
    }

    private func resetAlertPulse() {
        alertPulseGeneration += 1
        withTransaction(Transaction(animation: nil)) {
            alertPulseScale = 1.0
            alertPulseRotation = 0
            sonarScale = MotionTokens.sonarStartScale
            sonarOpacity = 0
        }
    }
}

struct BounceAnimatorValue {
    var translateY: CGFloat = MotionKeyframes.bounceCycle[0].translateY
    var scaleX: CGFloat = MotionKeyframes.bounceCycle[0].scaleX
    var scaleY: CGFloat = MotionKeyframes.bounceCycle[0].scaleY
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

private struct RoamOffsetEffect: GeometryEffect {
    var angle: Double
    let radiusX: Double
    let radiusY: Double
    let isActive: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard isActive else { return ProjectionTransform(CGAffineTransform.identity) }
        let radians = angle * Double.pi / 180
        let x = cos(radians) * radiusX
        let y = sin(radians) * radiusY
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }
}
