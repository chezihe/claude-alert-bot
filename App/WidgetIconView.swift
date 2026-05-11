// App/WidgetIconView.swift — Phase 2 WIDG-03 (icon + project name location).
// UI-SPEC: 36pt Claude Code glyph, 4pt internal padding (44pt total).
// +N badge: 16pt × 16pt circle, systemRed fill (systemGray in Quiet Hours), white SF Pro Semibold 11pt numeral.
// Anchored top-trailing with -4/-4 overhang per UI-SPEC.
// Bounce: 0.9s HTML-faithful KeyframeAnimator (translateY + scaleX + scaleY 3-track).
//         Mirrors @keyframes bounce-cute squash-and-stretch; suppressed when Reduce Motion / Quiet Hours.
// Breathe: 2.4s scale 1.0↔1.06, autoreverse forever; default idle animation for WO-012.
// Heart: HTML-faithful KeyframeAnimator (single scale track), double-pulse at 14% / 42%.
// Ring: 0.55s ±10° top-anchor rotation, autoreverse forever; suppressed when Reduce Motion is on.
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
    @State private var breatheScale: CGFloat = 1.0
    @State private var heartScale: CGFloat = 1.0
    @State private var heartGeneration: Int = 0
    @State private var idleRotation: Double = 0
    @State private var roamPhase: Double = 0
    @State private var driftOffset: CGSize = .zero
    @State private var driftGeneration: Int = 0
    @State private var driftWorkItem: DispatchWorkItem?
    @State private var alertPulseScale: CGFloat = 1.0
    @State private var alertPulseRotation: Double = 0
    @State private var sonarScale: CGFloat = MotionTokens.sonarStartScale
    @State private var sonarOpacity: Double = 0
    @State private var activeAlertPulseID: Int = 0
    @State private var alertPulseGeneration: Int = 0

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

    var body: some View {
        ZStack(alignment: .center) {
            ZStack(alignment: .topTrailing) {
                if sonarOpacity > 0, !quietHoursEnabled {
                    Circle()
                        .strokeBorder(ColorTokens.accent.opacity(sonarOpacity), lineWidth: 1.5)
                        .frame(width: MotionTokens.sonarBaseDiameter, height: MotionTokens.sonarBaseDiameter)
                        .scaleEffect(sonarScale)
                        .frame(width: 44, height: 44, alignment: .center)
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
                        glyph(bounceValue: value)
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
                } else {
                    glyph(bounceValue: BounceAnimatorValue())
                }
                if pendingCount >= 2 {
                    Text("+\(pendingCount - 1)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(
                            Circle().fill(quietHoursEnabled ? Color(NSColor.systemGray) : Color(NSColor.systemRed))
                        )
                        .offset(x: 4, y: -4)        // top-trailing -4/-4 overhang
                        .accessibilityHidden(true)  // count is announced via the parent label
                }
                if quietHoursEnabled {
                    Text("Zzz")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .offset(x: 5, y: pendingCount >= 2 ? 11 : -6)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: 44, height: 44, alignment: .center)
        }
        .frame(width: widgetBoundsSize.width, height: widgetBoundsSize.height, alignment: .center)
        .accessibilityElement()
        .accessibilityLabel(widgetAccessibilityLabel)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private func glyph(bounceValue: BounceAnimatorValue) -> some View {
        Image("ClaudeCodeIcon")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 36, height: 36)
            .frame(width: 44, height: 44)
            .scaleEffect(
                x: quietHoursEnabled ? 1.0 : bounceValue.scaleX,
                y: quietHoursEnabled ? 1.0 : bounceValue.scaleY,
                anchor: .bottom
            )
            .scaleEffect(quietHoursEnabled ? 1.0 : heartScale * breatheScale * alertPulseScale)
            .rotationEffect(.degrees(quietHoursEnabled ? 0 : alertPulseRotation + idleRotation), anchor: .top)
            .offset(
                x: quietHoursEnabled ? 0 : driftOffset.width,
                y: quietHoursEnabled ? 0 : bounceValue.translateY + driftOffset.height
            )
            .modifier(RoamOffsetEffect(
                angle: roamPhase,
                radiusX: Double(MotionTokens.roamRadiusX),
                radiusY: Double(MotionTokens.roamRadiusY),
                isActive: idleAnimation == .roam && !quietHoursEnabled && !reduceMotion
            ))
            .onAppear {
                startIdleAnimation()
                runNewAlertPulse()
            }
            .onDisappear {
                stopDriftAnimation()
                stopHeartAnimation()
            }
            .onChange(of: quietHoursEnabled) { _, _ in
                resetAlertPulse()
                restartIdleAnimation()
            }
            .onChange(of: idleAnimation) { _, _ in
                restartIdleAnimation()
            }
            .onChange(of: reduceMotion) { _, _ in
                resetAlertPulse()
                restartIdleAnimation()
            }
            .onChange(of: alertPulseID) { _, _ in
                runNewAlertPulse()
            }
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
        case .bounce:
            // Bounce is driven by the KeyframeAnimator wrapper around the glyph
            // (see `body`). startIdleAnimation has nothing to set up here.
            return
        case .breathe:
            guard let anim = MotionTokens.breatheAnimation(reduceMotion: reduceMotion) else { return }
            withAnimation(anim) {
                breatheScale = MotionTokens.breatheScale
            }
        case .heart:
            startHeartAnimation()
        case .ring:
            guard let anim = MotionTokens.ringAnimation(reduceMotion: reduceMotion) else { return }
            idleRotation = -MotionTokens.ringRotation
            withAnimation(anim) {
                idleRotation = MotionTokens.ringRotation
            }
        case .roam:
            guard let anim = MotionTokens.roamAnimation(reduceMotion: reduceMotion) else { return }
            withAnimation(anim) {
                roamPhase = -360
            }
        case .drift:
            guard MotionTokens.driftAnimation(reduceMotion: reduceMotion) != nil else { return }
            startDriftAnimation()
        }
    }

    private func restartIdleAnimation() {
        stopDriftAnimation()
        stopHeartAnimation()
        breatheScale = 1.0
        heartScale = 1.0
        idleRotation = 0
        roamPhase = 0
        startIdleAnimation()
    }

    private func startHeartAnimation() {
        heartGeneration += 1
        runHeartBeat(generation: heartGeneration)
    }

    private func stopHeartAnimation() {
        heartGeneration += 1
        heartScale = 1.0
    }

    private func runHeartBeat(generation: Int) {
        guard
            idleAnimation == .heart,
            !quietHoursEnabled,
            generation == heartGeneration,
            let anim = MotionTokens.heartBeatAnimation(reduceMotion: reduceMotion)
        else { return }

        withAnimation(anim) {
            heartScale = MotionTokens.heartPeakScale
        }
        scheduleHeartBeat(after: MotionTokens.heartBeatStepDuration, generation: generation, scale: 1.0)
        scheduleHeartBeat(after: MotionTokens.heartBeatStepDuration * 2, generation: generation, scale: MotionTokens.heartSecondScale)
        scheduleHeartBeat(after: MotionTokens.heartBeatStepDuration * 3, generation: generation, scale: 1.0)
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionTokens.heartDuration) {
            guard generation == heartGeneration else { return }
            runHeartBeat(generation: generation)
        }
    }

    private func scheduleHeartBeat(after delay: TimeInterval, generation: Int, scale: CGFloat) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard generation == heartGeneration else { return }
            guard let anim = MotionTokens.heartBeatAnimation(reduceMotion: reduceMotion) else { return }
            withAnimation(anim) {
                heartScale = scale
            }
        }
    }

    private func startDriftAnimation() {
        cancelDriftWorkItem()
        driftGeneration += 1
        runDriftStep(generation: driftGeneration)
    }

    private func stopDriftAnimation() {
        cancelDriftWorkItem()
        driftGeneration += 1
        driftOffset = .zero
    }

    private func cancelDriftWorkItem() {
        driftWorkItem?.cancel()
        driftWorkItem = nil
    }

    private func runDriftStep(generation: Int) {
        guard
            idleAnimation == .drift,
            !quietHoursEnabled,
            generation == driftGeneration,
            let anim = MotionTokens.driftAnimation(reduceMotion: reduceMotion)
        else { return }

        withAnimation(anim) {
            driftOffset = makeDriftTarget()
        }
        let workItem = DispatchWorkItem {
            guard generation == driftGeneration else { return }
            driftWorkItem = nil
            runDriftStep(generation: generation)
        }
        driftWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + MotionTokens.driftDuration, execute: workItem)
    }

    private func makeDriftTarget() -> CGSize {
        CGSize(
            width: CGFloat(Double.random(in: -MotionTokens.driftRadiusX...MotionTokens.driftRadiusX)),
            height: CGFloat(Double.random(in: -MotionTokens.driftRadiusY...MotionTokens.driftRadiusY))
        )
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
