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
    var widgetIconStyle: WidgetIconStyle = .default
    var widgetSide: WidgetSide = .right
    var alertEffect: WidgetAlertEffect = .heal

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
    @State private var lastBadgeKey: Int = -1
    @State private var isHovering: Bool = false
    @State private var rageImpactKick: CGFloat = 0
    // Magic v2: Tap-Cast cycle + wand-tip trail + burst spray.
    @State private var castCycleStartedAt: Date = .distantPast
    @State private var castCycleID: Int = 0
    @State private var trailSpawnWorkItem: DispatchWorkItem? = nil
    @State private var trailSparkles: [TrailSpark] = []
    @State private var burstSparkles: [BurstSpark] = []
    @State private var lastBurstCycleID: Int = -1
    @State private var zeldaIdleStartedAt: Date = Date()
    @State private var zeldaAlertStartedAt: Date = .distantPast

    private static let badgeOffset = CGSize(width: -2, height: 2)
    private static let zeldaHeartOffset = CGSize(width: -1, height: -18)
    private static let claudeGlyphSize = CGSize(width: 46, height: 46)
    private static let zeldaGlyphSize = CGSize(width: 92, height: 92)
    private static let zeldaIdleFrameDuration: TimeInterval = 0.45
    private static let zeldaAlertFrameDuration: TimeInterval = 0.18
    private static let fixedGlyphOffset = CGSize(width: 0, height: 8)
    private static let zeldaGlyphOffset = CGSize(width: 0, height: 18)
    // Pivot sits on the icon's right arm (the "hand") so the wand reads as held by it.
    private static let magicWandOffset = CGSize(width: 20, height: -5)
    private static let magicWandBaseRotation: Double = 32
    // Idle micro-sway amplitude (degrees). The big motion now lives in the cast cycle.
    private static let magicWandIdleSwing: Double = 2
    // Wand VStack height: orb 5 + spacing 3 + capsule 18 = 26pt (used to compute the wand-tip position).
    private static let magicWandLength: CGFloat = 26

    private var reduceMotion: Bool {
        reduceMotionPreference.effectiveReduceMotion(systemReduceMotion: systemReduceMotion)
    }

    private var widgetBoundsSize: CGSize {
        GeometryTokens.widgetDrawableSize(
            idleAnimation: idleAnimation,
            quietHoursEnabled: quietHoursEnabled,
            reduceMotion: reduceMotion,
            widgetIconStyle: widgetIconStyle
        )
    }

    private var glyphSize: CGSize {
        widgetIconStyle == .zelda ? Self.zeldaGlyphSize : Self.claudeGlyphSize
    }

    private var glyphOffset: CGSize {
        widgetIconStyle == .zelda ? Self.zeldaGlyphOffset : Self.fixedGlyphOffset
    }

    private var bounceAnimatorActive: Bool {
        widgetIconStyle == .claude && idleAnimation == .bounce && !quietHoursEnabled && !reduceMotion
    }

    private var heartAnimatorActive: Bool {
        widgetIconStyle == .claude && idleAnimation == .heart && !quietHoursEnabled && !reduceMotion
    }

    private var rageAnimatorActive: Bool {
        widgetIconStyle == .claude && idleAnimation == .rage && !quietHoursEnabled && !reduceMotion
    }

    private var ringAnimatorActive: Bool {
        widgetIconStyle == .claude && idleAnimation == .ring && !quietHoursEnabled && !reduceMotion
    }

    private var magicAnimatorActive: Bool {
        widgetIconStyle == .claude && idleAnimation == .magic && !quietHoursEnabled && !reduceMotion
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
                        KeyframeTrack(\.rotation) {
                            CubicKeyframe(MotionKeyframes.bounceCycle[1].rotation,
                                          duration: MotionKeyframes.bouncePeriod * 0.18)
                            CubicKeyframe(MotionKeyframes.bounceCycle[2].rotation,
                                          duration: MotionKeyframes.bouncePeriod * 0.32)
                            CubicKeyframe(MotionKeyframes.bounceCycle[3].rotation,
                                          duration: MotionKeyframes.bouncePeriod * 0.32)
                            CubicKeyframe(MotionKeyframes.bounceCycle[4].rotation,
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
                    // Magic v2 = "magical girl" Tap-Cast: glyph floats gently while the wand
                    // (idle sway → windup → strike → recoil) casts every magicCastInterval.
                    // Trail sparkles drift off the wand tip during idle; a radial burst fires
                    // at the strike moment. TimelineView drives all per-frame values.
                    TimelineView(.animation) { context in
                        let now = context.date.timeIntervalSinceReferenceDate
                        let hoverY = CGFloat(sin(now / MotionKeyframes.magicHoverPeriod * 2 * .pi))
                                     * MotionKeyframes.magicHoverAmplitude
                        let tiltDeg = sin(now / MotionKeyframes.magicTiltPeriod * 2 * .pi)
                                      * MotionKeyframes.magicTiltAmplitude
                        let cast = magicCastPhase(at: context.date)
                        glyph(
                            bounceValue: BounceAnimatorValue(translateY: hoverY, scaleX: 1, scaleY: 1),
                            heartScale: 1.0,
                            rageValue: RageAnimatorValue()
                        )
                        .rotationEffect(.degrees(tiltDeg), anchor: .center)
                        .overlay(alignment: .center) {
                            magicCastOverlay(now: context.date, wandAngle: cast.angle)
                        }
                        .onChange(of: cast.strikeCycleID) { _, newCycleID in
                            if newCycleID > lastBurstCycleID {
                                spawnBurstSparkles(cycleID: newCycleID, at: context.date)
                                lastBurstCycleID = newCycleID
                            }
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
                        // Indices 1–6 are the damped bell swing (10% each); 7 (70%)+8 (85%)
                        // are the micro-aftershock; 9 (100%) settles back to 0.
                        KeyframeTrack(\.rotation) {
                            CubicKeyframe(MotionKeyframes.ringCycle[1].rotation, duration: MotionKeyframes.ringPeriod * 0.10)
                            CubicKeyframe(MotionKeyframes.ringCycle[2].rotation, duration: MotionKeyframes.ringPeriod * 0.10)
                            CubicKeyframe(MotionKeyframes.ringCycle[3].rotation, duration: MotionKeyframes.ringPeriod * 0.10)
                            CubicKeyframe(MotionKeyframes.ringCycle[4].rotation, duration: MotionKeyframes.ringPeriod * 0.10)
                            CubicKeyframe(MotionKeyframes.ringCycle[5].rotation, duration: MotionKeyframes.ringPeriod * 0.10)
                            CubicKeyframe(MotionKeyframes.ringCycle[6].rotation, duration: MotionKeyframes.ringPeriod * 0.10)
                            CubicKeyframe(MotionKeyframes.ringCycle[7].rotation, duration: MotionKeyframes.ringPeriod * 0.10)
                            CubicKeyframe(MotionKeyframes.ringCycle[8].rotation, duration: MotionKeyframes.ringPeriod * 0.15)
                            CubicKeyframe(MotionKeyframes.ringCycle[9].rotation, duration: MotionKeyframes.ringPeriod * 0.15)
                        }
                    }
                } else {
                    glyph(bounceValue: BounceAnimatorValue(), heartScale: 1.0, rageValue: RageAnimatorValue())
                }
                if widgetIconStyle == .zelda {
                    if pendingCount >= 1 {
                        zeldaHeartBadgeView
                    }
                } else if pendingCount >= 2 {
                    badgeView
                }
            }
            .frame(width: GeometryTokens.widgetBaseSize.width, height: GeometryTokens.widgetBaseSize.height, alignment: .center)
        }
        // Magic biases the extra width to the right of the icon (the wand "lives" there).
        .frame(width: widgetBoundsSize.width, height: widgetBoundsSize.height, alignment: magicAnimatorActive ? .leading : .center)
        // Hover affordance — small lift + accent glow signal that the widget is clickable.
        .scaleEffect(isHovering && !reduceMotion ? 1.05 : 1.0, anchor: .center)
        .shadow(
            color: ColorTokens.accent.opacity(isHovering ? 0.35 : 0),
            radius: isHovering ? 6 : 0
        )
        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
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
        glyphImage
            .frame(width: glyphSize.width, height: glyphSize.height)
            .frame(width: GeometryTokens.widgetBaseSize.width, height: GeometryTokens.widgetBaseSize.height)
            // Heart-mode glow pulses in sync with the heartScale double-pulse (1.0→1.14).
            .shadow(
                color: ColorTokens.accent.opacity(
                    heartAnimatorActive ? max(0, Double(heartScale - 1.0)) * 4 : 0
                ),
                radius: heartAnimatorActive ? max(0, Double(heartScale - 1.0)) * 12 : 0
            )
            .scaleEffect(
                x: quietHoursEnabled ? 1.0 : bounceValue.scaleX,
                y: quietHoursEnabled ? 1.0 : bounceValue.scaleY,
                anchor: .bottom
            )
            // Bounce micro-rotation overlay — cartoon weight-shift across the hop, anchored at bottom.
            .rotationEffect(
                .degrees(quietHoursEnabled ? 0 : bounceValue.rotation),
                anchor: .bottom
            )
            .scaleEffect(quietHoursEnabled ? 1.0 : heartScale * alertPulseScale, anchor: .center)
            .rotationEffect(.degrees(quietHoursEnabled ? 0 : alertPulseRotation + ringRotation), anchor: UnitPoint(x: 0.5, y: 0.1))
            .offset(
                x: glyphOffset.width,
                y: (quietHoursEnabled ? 0 : bounceValue.translateY) + glyphOffset.height
            )
            // Rage throw-windup applied last so it dominates other transforms while looping.
            // Internal prototype transform-origin: 50% 90%.
            .scaleEffect(rageValue.scale, anchor: UnitPoint(x: 0.5, y: 0.9))
            .rotationEffect(.degrees(rageValue.rotation), anchor: UnitPoint(x: 0.5, y: 0.9))
            .offset(x: rageValue.translateX, y: rageValue.translateY)
            // Rage projectile impact aftershock — small vertical kick post-launch.
            .offset(y: rageImpactKick * 1.5)
            // Roam breathing — subtle 1.0↔1.04 scale across the 1.6s lap.
            .scaleEffect(
                idleAnimation == .roam && widgetIconStyle == .claude && !quietHoursEnabled && !reduceMotion
                    ? 1.0 + 0.04 * CGFloat(sin(roamPhase * .pi / 180))
                    : 1.0,
                anchor: .center
            )
            .modifier(RoamOffsetEffect(
                angle: roamPhase,
                radiusX: Double(MotionTokens.roamRadiusX),
                radiusY: Double(MotionTokens.roamRadiusY),
                isActive: idleAnimation == .roam && widgetIconStyle == .claude && !quietHoursEnabled && !reduceMotion
            ))
            .onAppear {
                startIdleAnimation()
                runNewAlertPulse()
                primeBadgePop()
                restartRageProjectileLoop()
                restartCastCycleLoop()
            }
            .onDisappear {
                stopRageProjectileLoop()
                stopCastCycleLoop()
            }
            .onChange(of: quietHoursEnabled) { _, _ in
                resetAlertPulse()
                restartIdleAnimation()
                restartRageProjectileLoop()
                restartCastCycleLoop()
            }
            .onChange(of: idleAnimation) { _, _ in
                restartIdleAnimation()
                restartRageProjectileLoop()
                restartCastCycleLoop()
            }
            .onChange(of: widgetIconStyle) { _, _ in
                resetAlertPulse()
                restartIdleAnimation()
                restartRageProjectileLoop()
                restartCastCycleLoop()
                zeldaIdleStartedAt = Date()
            }
            .onChange(of: reduceMotion) { _, _ in
                resetAlertPulse()
                restartIdleAnimation()
                restartRageProjectileLoop()
                restartCastCycleLoop()
            }
            .onChange(of: alertPulseID) { _, _ in
                runNewAlertPulse()
            }
            .onChange(of: pendingCount) { _, _ in
                runBadgePop()
            }
    }

    @ViewBuilder
    private var glyphImage: some View {
        if widgetIconStyle == .zelda {
            TimelineView(.animation) { context in
                zeldaImage(frameName: zeldaFrameName(at: context.date), widgetSide: widgetSide)
            }
        } else {
            Image("ClaudeCodeIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    private func zeldaFrameName(at date: Date) -> String {
        let alertFrames = ZeldaFrame.alertFrames(side: widgetSide, effect: alertEffect)
        let alertAge = date.timeIntervalSince(zeldaAlertStartedAt)
        if alertAge >= 0 {
            var elapsed: TimeInterval = 0
            for frameName in alertFrames {
                let duration = Self.zeldaAlertFrameDuration * ZeldaFrame.alertFrameDurationMultiplier(frameName: frameName)
                if alertAge < elapsed + duration {
                    return frameName
                }
                elapsed += duration
            }
        }
        let idleAge = max(0, date.timeIntervalSince(zeldaIdleStartedAt))
        let index = Int(idleAge / Self.zeldaIdleFrameDuration) % ZeldaFrame.idleFrames.count
        return ZeldaFrame.idleFrames[index]
    }

    private func zeldaImage(frameName: String, widgetSide: WidgetSide) -> some View {
        Image(nsImage: bundleImage(named: frameName, subdirectory: ZeldaFrame.pickerSubdirectory(side: widgetSide)))
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    private func bundleImage(named name: String, subdirectory: String) -> NSImage {
        if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: subdirectory),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(size: NSSize(width: 1, height: 1))
    }

    // MARK: - Magic v2 (Tap-Cast)

    private struct TrailSpark: Identifiable {
        let id = UUID()
        let spawnedAt: Date
        let origin: CGPoint
    }

    private struct BurstSpark: Identifiable {
        let id = UUID()
        let spawnedAt: Date
        let origin: CGPoint
        let angle: Double // radians
    }

    // 4-phase cycle: idle (long gentle sway) → windup → strike → recoil → idle…
    // `strikeCycleID` increases by 1 at the strike entry of each cycle so the renderer
    // can fire the burst-spray exactly once per cycle via onChange.
    private func magicCastPhase(at date: Date) -> (angle: Double, strikeCycleID: Int) {
        guard castCycleStartedAt > .distantPast else {
            return (Self.magicWandBaseRotation, 0)
        }
        let interval = MotionTokens.magicCastInterval
        let idleDur = MotionTokens.magicCastIdleDuration
        let windupDur = MotionTokens.magicCastWindupDuration
        let strikeDur = MotionTokens.magicCastStrikeDuration
        let elapsedTotal = date.timeIntervalSince(castCycleStartedAt)
        guard elapsedTotal >= 0 else {
            return (Self.magicWandBaseRotation, 0)
        }
        let cycleIndex = Int(elapsedTotal / interval)
        let local = elapsedTotal - Double(cycleIndex) * interval

        let base = Self.magicWandBaseRotation
        let windupPeak = base + 12   // pull back to 44°
        let strikeEnd = base - 20    // forward strike to 12°

        let idleSway = sin(local / idleDur * 2 * .pi) * Self.magicWandIdleSwing
        var angle: Double
        var strikeID = cycleIndex // bumps when we enter strike of the next cycle

        if local < idleDur {
            angle = base + idleSway
            strikeID = cycleIndex // strike has not fired yet this cycle
        } else if local < idleDur + windupDur {
            let t = (local - idleDur) / windupDur
            angle = lerp(from: base, to: windupPeak, t: easeInCubic(t))
            strikeID = cycleIndex
        } else if local < idleDur + windupDur + strikeDur {
            let t = (local - idleDur - windupDur) / strikeDur
            angle = lerp(from: windupPeak, to: strikeEnd, t: easeOutCubic(t))
            strikeID = cycleIndex + 1 // strike of this cycle has begun
        } else {
            let recoilElapsed = local - idleDur - windupDur - strikeDur
            let t = min(1, recoilElapsed / MotionTokens.magicCastRecoilDuration)
            angle = lerp(from: strikeEnd, to: base, t: easeOutCubic(t))
            strikeID = cycleIndex + 1
        }
        return (angle, strikeID)
    }

    private func lerp(from a: Double, to b: Double, t: Double) -> Double { a + (b - a) * t }
    private func easeInCubic(_ t: Double) -> Double { t * t * t }
    private func easeOutCubic(_ t: Double) -> Double { 1 - pow(1 - t, 3) }

    // Wand-tip coordinate relative to the overlay center (where the wand VStack is placed).
    // The VStack is offset by magicWandOffset and rotated around its bottom; the tip sits
    // magicWandLength pt above the pivot before rotation.
    private func wandTipPosition(angleDegrees: Double) -> CGPoint {
        let pivotX = Self.magicWandOffset.width
        let pivotY = Self.magicWandOffset.height
        let theta = angleDegrees * .pi / 180
        let tipX = pivotX + CGFloat(sin(theta)) * Self.magicWandLength
        let tipY = pivotY - CGFloat(cos(theta)) * Self.magicWandLength
        return CGPoint(x: tipX, y: tipY)
    }

    private func magicCastOverlay(now: Date, wandAngle: Double) -> some View {
        ZStack {
            trailLayer(now: now)
            burstLayer(now: now)
            magicWand(rotationDegrees: wandAngle)
        }
        .frame(
            width: GeometryTokens.widgetBaseSize.width + GeometryTokens.magicDrawableExtraWidth,
            height: GeometryTokens.widgetBaseSize.height + GeometryTokens.magicDrawableExtraHeight,
            alignment: .center
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func magicWand(rotationDegrees: Double) -> some View {
        VStack(spacing: 3) {
            Circle()
                .frame(width: 5, height: 5)
                .foregroundStyle(Color(red: 1, green: 0.98, blue: 0.9))
            Capsule()
                .frame(width: 2.5, height: 18)
                .foregroundStyle(Color(red: 0xEE / 255, green: 0xF7 / 255, blue: 0xFF / 255))
        }
        .offset(x: Self.magicWandOffset.width, y: Self.magicWandOffset.height)
        .rotationEffect(.degrees(rotationDegrees), anchor: .bottom)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func trailLayer(now: Date) -> some View {
        ForEach(trailSparkles) { spark in
            let age = now.timeIntervalSince(spark.spawnedAt)
            let life = MotionTokens.magicTrailLifetime
            if age >= 0, age <= life {
                let t = age / life
                let opacity = 1 - t
                let drift = CGFloat(t) * 4
                Image(systemName: "sparkle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: MotionTokens.magicTrailSize, height: MotionTokens.magicTrailSize)
                    .foregroundStyle(Color(red: 1, green: 0.96, blue: 0.78))
                    .shadow(color: Color(red: 1, green: 0.92, blue: 0.55).opacity(0.55), radius: 1.5)
                    .opacity(opacity)
                    .offset(x: spark.origin.x, y: spark.origin.y + drift)
            }
        }
    }

    @ViewBuilder
    private func burstLayer(now: Date) -> some View {
        ForEach(burstSparkles) { spark in
            let age = now.timeIntervalSince(spark.spawnedAt)
            let life = MotionTokens.magicBurstSparkDuration
            if age >= 0, age <= life {
                let t = age / life
                let eased = easeOutCubic(t)
                let r = CGFloat(eased) * MotionTokens.magicBurstSparkRadius
                let dx = CGFloat(cos(spark.angle)) * r
                let dy = CGFloat(sin(spark.angle)) * r
                let opacity = 1 - t
                Image(systemName: "sparkle")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: MotionTokens.magicBurstSparkSize, height: MotionTokens.magicBurstSparkSize)
                    .foregroundStyle(Color(red: 1, green: 0.95, blue: 0.75))
                    .shadow(color: ColorTokens.accent.opacity(0.6), radius: 2)
                    .opacity(opacity)
                    .offset(x: spark.origin.x + dx, y: spark.origin.y + dy)
            }
        }
    }

    private func spawnBurstSparkles(cycleID: Int, at date: Date) {
        guard magicAnimatorActive else { return }
        let phase = magicCastPhase(at: date)
        let tip = wandTipPosition(angleDegrees: phase.angle)
        let count = MotionTokens.magicBurstSparkCount
        let now = date
        for i in 0..<count {
            let baseAngle = Double(i) * (2 * .pi / Double(count))
            let jitter = Double.random(in: -0.087...0.087) // ±5°
            burstSparkles.append(BurstSpark(spawnedAt: now, origin: tip, angle: baseAngle + jitter))
        }
        // Trim old burst sparks to keep the array bounded.
        let lifetime = MotionTokens.magicBurstSparkDuration
        burstSparkles.removeAll { date.timeIntervalSince($0.spawnedAt) > lifetime }
    }

    @ViewBuilder
    private var badgeView: some View {
        let fill = quietHoursEnabled
            ? Color(red: 0x6B/255, green: 0x6B/255, blue: 0x75/255)
            : ColorTokens.accentDark
        Text("+\(pendingCount)")
            .font(.system(size: 10.5))
            .foregroundStyle(Color(red: 0xFF/255, green: 0xF4/255, blue: 0xEC/255))
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(
                Capsule(style: .continuous).fill(fill)
            )
            .shadow(color: .black.opacity(0.25), radius: 1.5, x: 0, y: 1)
            .scaleEffect(badgePopScale)
            .offset(x: Self.badgeOffset.width, y: Self.badgeOffset.height)
            .accessibilityHidden(true)
    }

    private var zeldaHeartFrameName: String {
        switch min(max(pendingCount, 1), 3) {
        case 1: return "heart_frame_01"
        case 2: return "heart_frame_02"
        default: return "heart_frame_03"
        }
    }

    @ViewBuilder
    private var zeldaHeartBadgeView: some View {
        HStack(alignment: .top, spacing: 0) {
            Image(nsImage: bundleImage(named: zeldaHeartFrameName, subdirectory: "zelda/heart"))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 45, height: 24)
            if pendingCount > 3 {
                zeldaHeartOverflowText
            }
        }
        .offset(x: Self.zeldaHeartOffset.width, y: Self.zeldaHeartOffset.height)
        .accessibilityHidden(true)
    }

    private var zeldaHeartOverflowText: some View {
        Text("+\(pendingCount - 3)")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.black)
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
            guard widgetIconStyle == .claude else { return }
            guard let anim = MotionTokens.roamAnimation(reduceMotion: reduceMotion) else { return }
            withAnimation(anim) {
                roamPhase = -360
            }
        case .magic:
            // Magic v2 cycle anchor is set in restartCastCycleLoop(); no SwiftUI repeatForever needed.
            return
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
        rageImpactKick = 0
    }

    private func scheduleNextRageProjectile(generation: Int, delay: TimeInterval) {
        let workItem = DispatchWorkItem {
            guard generation == rageGeneration, rageAnimatorActive else { return }
            MacBookProjectileLauncher.shared.launchFromWidget()
            kickRageImpact(generation: generation)
            scheduleNextRageProjectile(generation: generation, delay: MotionKeyframes.ragePeriod)
        }
        rageWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    // Camera-shake-style kick on the widget itself right after each projectile leaves.
    // Springs up by 1.5pt, then settles. Synced to rageGeneration so mode changes cancel it.
    private func kickRageImpact(generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard generation == rageGeneration, rageAnimatorActive else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.35)) {
                rageImpactKick = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard generation == rageGeneration else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    rageImpactKick = 0
                }
            }
        }
    }

    // Magic Tap-Cast cycle: starts the long-running cycle anchor + the per-0.18s trail spawner.
    // The cycle anchor (`castCycleStartedAt`) drives `magicCastPhase` rendering; the spawner
    // keeps pushing wand-tip sparkles while magic is active.
    private func restartCastCycleLoop() {
        stopCastCycleLoop()
        guard magicAnimatorActive else { return }
        castCycleID &+= 1
        let generation = castCycleID
        castCycleStartedAt = Date()
        lastBurstCycleID = 0
        scheduleNextTrailSpawn(generation: generation)
    }

    private func stopCastCycleLoop() {
        castCycleID &+= 1
        trailSpawnWorkItem?.cancel()
        trailSpawnWorkItem = nil
        trailSparkles.removeAll()
        burstSparkles.removeAll()
        lastBurstCycleID = -1
    }

    private func scheduleNextTrailSpawn(generation: Int) {
        let workItem = DispatchWorkItem {
            guard generation == castCycleID, magicAnimatorActive else { return }
            spawnTrailSpark()
            scheduleNextTrailSpawn(generation: generation)
        }
        trailSpawnWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + MotionTokens.magicTrailSpawnInterval,
            execute: workItem
        )
    }

    private func spawnTrailSpark() {
        let now = Date()
        let phase = magicCastPhase(at: now)
        let tip = wandTipPosition(angleDegrees: phase.angle)
        trailSparkles.append(TrailSpark(spawnedAt: now, origin: tip))
        // Trim by lifetime; cap also by max count so we never grow without bound.
        let lifetime = MotionTokens.magicTrailLifetime
        trailSparkles.removeAll { now.timeIntervalSince($0.spawnedAt) > lifetime }
        if trailSparkles.count > MotionTokens.magicTrailMaxCount {
            trailSparkles.removeFirst(trailSparkles.count - MotionTokens.magicTrailMaxCount)
        }
    }


    private func runNewAlertPulse() {
        guard alertPulseID > 0, alertPulseID != activeAlertPulseID, !quietHoursEnabled else { return }
        let pulseID = alertPulseID
        activeAlertPulseID = pulseID
        if widgetIconStyle == .zelda {
            zeldaAlertStartedAt = Date()
        }
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
            zeldaAlertStartedAt = .distantPast
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
