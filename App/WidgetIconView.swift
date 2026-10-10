// App/WidgetIconView.swift — Phase 2 WIDG-03 (icon + project name location).
// UI-SPEC: 36pt Claude Code glyph, 4pt internal padding (44pt total).
// +N badge: 16pt-min capsule, accent-dark fill (gray in Quiet Hours), white SF Pro 9.5pt text.
// Anchored top-trailing inside the panel bounds to avoid clipping at screen edges.
// Idle motions (Claude icon only; suppressed in Quiet Hours / Reduce Motion — see `activeIdle`):
//   bounce / heart / rage / ring → KeyframeIdleGlyph (+ RageProjectileLoop for rage),
//   roam → RoamIdleMotion.
// Zelda icon + heart badge → ZeldaGlyph.swift.
// New-alert pulse: scale/rotate glyph + one sonar ring; suppressed in Quiet Hours.
//
// Lifecycle: the hooks below are attached once to the outer view. Each idle mode is a
// self-contained subview whose state and timers start on its own mount and die with it,
// so switching modes needs no restart bookkeeping and is independent of appear/disappear order.
import SwiftUI

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
    @State private var alertPulseScale: CGFloat = 1.0
    @State private var alertPulseRotation: Double = 0
    @State private var sonarScale: CGFloat = MotionTokens.sonarStartScale
    @State private var sonarOpacity: Double = 0
    @State private var activeAlertPulseID: Int = 0
    @State private var alertPulseGeneration: Int = 0
    @State private var badgePopScale: CGFloat = 1.0
    @State private var lastBadgeKey: Int = -1
    @State private var isHovering: Bool = false
    @State private var zeldaIdleStartedAt: Date = Date()
    @State private var zeldaAlertStartedAt: Date = .distantPast

    private var reduceMotion: Bool {
        reduceMotionPreference.effectiveReduceMotion(systemReduceMotion: systemReduceMotion)
    }

    private var activeIdle: IdleAnimation? {
        Self.activeIdle(
            idleAnimation: idleAnimation,
            widgetIconStyle: widgetIconStyle,
            quietHoursEnabled: quietHoursEnabled,
            reduceMotion: reduceMotion
        )
    }

    private var widgetBoundsSize: CGSize {
        GeometryTokens.widgetDrawableSize(
            idleAnimation: idleAnimation,
            quietHoursEnabled: quietHoursEnabled,
            reduceMotion: reduceMotion,
            widgetIconStyle: widgetIconStyle
        )
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
                animatedGlyph
                switch Self.badgeKind(widgetIconStyle: widgetIconStyle, pendingCount: pendingCount) {
                case .hearts: ZeldaHeartBadge(pendingCount: pendingCount)
                case .count: badgeView
                case .none: EmptyView()
                }
            }
            .frame(width: GeometryTokens.widgetBaseSize.width, height: GeometryTokens.widgetBaseSize.height, alignment: .center)
        }
        .frame(width: widgetBoundsSize.width, height: widgetBoundsSize.height)
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
        .accessibilityLabel(Self.accessibilityLabel(pendingCount: pendingCount, quietHoursEnabled: quietHoursEnabled))
        .accessibilityAddTraits(.isButton)
        .onAppear {
            runNewAlertPulse()
            primeBadgePop()
        }
        .onChange(of: quietHoursEnabled) { _, _ in resetAlertPulse() }
        .onChange(of: reduceMotion) { _, _ in resetAlertPulse() }
        .onChange(of: widgetIconStyle) { _, _ in
            resetAlertPulse()
            zeldaIdleStartedAt = Date()
        }
        .onChange(of: alertPulseID) { _, _ in runNewAlertPulse() }
        .onChange(of: pendingCount) { _, _ in runBadgePop() }
    }

    // One branch per idle mode; each branch owns its animation state, so leaving it
    // (idle switch, Quiet Hours, Reduce Motion, icon style) tears the motion down.
    @ViewBuilder
    private var animatedGlyph: some View {
        switch activeIdle {
        case .rage:
            KeyframeIdleGlyph(idle: .rage) { glyph($0) }
                .modifier(RageProjectileLoop())
        case .roam:
            glyph(GlyphMotion())
                .modifier(RoamIdleMotion())
        case .some(let idle):
            KeyframeIdleGlyph(idle: idle) { glyph($0) }
        case nil:
            glyph(GlyphMotion())
        }
    }

    private func glyph(_ motion: GlyphMotion) -> some View {
        let bounce = motion.bounce
        let heartGlow = activeIdle == .heart ? max(0, Double(motion.heartScale - 1.0)) : 0
        let glyphSize = Self.glyphSize(for: widgetIconStyle)
        let glyphOffset = Self.glyphOffset(for: widgetIconStyle)
        return glyphImage
            .frame(width: glyphSize.width, height: glyphSize.height)
            .frame(width: GeometryTokens.widgetBaseSize.width, height: GeometryTokens.widgetBaseSize.height)
            // Heart-mode glow pulses in sync with the heartScale double-pulse (1.0→1.14).
            .shadow(color: ColorTokens.accent.opacity(heartGlow * 4), radius: heartGlow * 12)
            .scaleEffect(
                x: quietHoursEnabled ? 1.0 : bounce.scaleX,
                y: quietHoursEnabled ? 1.0 : bounce.scaleY,
                anchor: .bottom
            )
            // Bounce micro-rotation overlay — cartoon weight-shift across the hop, anchored at bottom.
            .rotationEffect(.degrees(quietHoursEnabled ? 0 : bounce.rotation), anchor: .bottom)
            // Heart anchors at center (HTML transform-origin 50% 50%); ring swings from near-top.
            .scaleEffect(quietHoursEnabled ? 1.0 : motion.heartScale * alertPulseScale, anchor: .center)
            .rotationEffect(.degrees(quietHoursEnabled ? 0 : alertPulseRotation + motion.ringRotation), anchor: UnitPoint(x: 0.5, y: 0.1))
            .offset(
                x: glyphOffset.width,
                y: (quietHoursEnabled ? 0 : bounce.translateY) + glyphOffset.height
            )
            // Rage throw-windup applied last so it dominates other transforms while looping.
            // Internal prototype transform-origin: 50% 90%.
            .scaleEffect(motion.rage.scale, anchor: UnitPoint(x: 0.5, y: 0.9))
            .rotationEffect(.degrees(motion.rage.rotation), anchor: UnitPoint(x: 0.5, y: 0.9))
            .offset(x: motion.rage.translateX, y: motion.rage.translateY)
    }

    @ViewBuilder
    private var glyphImage: some View {
        if widgetIconStyle == .zelda {
            ZeldaGlyph(
                widgetSide: widgetSide,
                alertEffect: alertEffect,
                idleStartedAt: zeldaIdleStartedAt,
                alertStartedAt: zeldaAlertStartedAt
            )
        } else {
            Image("ClaudeCodeIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    private var badgeView: some View {
        // Quiet Hours swaps the HTML-proto accent-dark fill (#B8492C) for gray (#6B6B75).
        let fill = quietHoursEnabled
            ? Color(red: 0x6B/255, green: 0x6B/255, blue: 0x75/255)
            : ColorTokens.accentDark
        return Text(Self.badgeText(pendingCount: pendingCount))
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

    // MARK: - Badge pop

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

    // MARK: - New-alert pulse

    private func runNewAlertPulse() {
        guard Self.shouldRunAlertPulse(
            alertPulseID: alertPulseID,
            activeAlertPulseID: activeAlertPulseID,
            quietHoursEnabled: quietHoursEnabled
        ) else { return }
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
