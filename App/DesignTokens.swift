// App/DesignTokens.swift — Phase 03.1 design system foundation.
// Single source of truth for visual + motion tokens traceable to the project contract.
// Per D2-29: zero external Swift deps. All call-sites in WidgetIconView / PopoverContentView /
// PopoverRowView resolve through this module (SC#1).
// Reduce-motion gate is owned by MotionTokens factory (D4 / SC#3) — call-sites pass a Bool;
// they choose @Environment(\.accessibilityReduceMotion) (SwiftUI) or
// NSWorkspace.shared.accessibilityDisplayShouldReduceMotion (AppKit) at the call-site.
// Findings F-1, F-2, F-3 documented in 03.1-SUMMARY.md.
import SwiftUI
import AppKit

enum ColorTokens {
    // Project contract: accent (warm orange)
    static let accent: Color = makeColor(hex: 0xD97757)
    // Project contract: accent dark
    static let accentDark: Color = makeColor(hex: 0xB8492C)
    // Project contract: status success
    static let statusSuccess: Color = makeColor(hex: 0x34C759)
    // Project contract: status error
    static let statusError: Color = makeColor(hex: 0xE5484D)
    // Project contract: status waiting
    static let statusWaiting: Color = makeColor(hex: 0xF5A623)

    static func statusDot(for kind: AlertKind) -> Color {
        switch kind {
        case .success:
            return statusSuccess
        case .error:
            return statusError
        case .waiting:
            return statusWaiting
        }
    }

    // Project contract: row hover
    static func rowHover(colorScheme: ColorScheme) -> Color {
        accent.opacity(colorScheme == .dark ? 0.20 : 0.13)
    }

    /// Hex (RRGGBB) → SwiftUI Color via componentwise sRGB. Private helper, zero deps.
    fileprivate static func makeColor(hex: UInt32) -> Color {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8)  & 0xFF) / 255.0
        let b = Double( hex        & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }
}

enum GeometryTokens {
    // Project contract: popover width 255pt — WO-009 reconciles code and contract.
    static let popoverWidth: CGFloat = 255
    // Fixed toolbar row for settings and optional clear action.
    static let popoverToolbarHeight: CGFloat = 32
    // Project contract: popover corner radius 14pt
    static let popoverCornerRadius: CGFloat = 14
    // Project contract: row min height 36pt
    static let rowMinHeight: CGFloat = 36
    static let rowLastOutputPreviewExtraHeight: CGFloat = 10
    // Project contract: row horizontal padding 12pt
    static let rowHorizontalPadding: CGFloat = 12
    // Project contract: row vertical padding 8pt
    static let rowVerticalPadding: CGFloat = 8
    // Project contract: status dot diameter 7pt
    static let statusDotDiameter: CGFloat = 7
    // Project contract: hollow ring stroke 1.5pt
    static let statusDotRingStroke: CGFloat = 1.5
    // Magic animation expands vertically to keep falling stars visible outside the base 64×64 icon.
    static let magicDrawableExtraWidth: CGFloat = 30
    static let magicDrawableExtraHeight: CGFloat = 40
    static let zeldaWidgetDrawableSize = CGSize(width: 128, height: 128)
    static let widgetBadgeTopClearance: CGFloat = 12
    // Project contract: max 4 visible rows — WO-009 enforces; rows beyond scroll vertically.
    static let popoverMaxVisibleRows: Int = 4
    // Project contract: scroll fade — applied only when the list exceeds max visible rows.
    static let popoverScrollFadeHeight: CGFloat = 12
    static let widgetBaseSize = CGSize(width: 64, height: 64)

    static func widgetDrawableSize(
        idleAnimation: IdleAnimation,
        quietHoursEnabled: Bool,
        reduceMotion: Bool,
        widgetIconStyle: WidgetIconStyle = .default
    ) -> CGSize {
        if widgetIconStyle == .zelda { return zeldaWidgetDrawableSize }
        let baseDrawableSize = CGSize(
            width: widgetBaseSize.width,
            height: widgetBaseSize.height + widgetBadgeTopClearance * 2
        )
        guard !quietHoursEnabled, !reduceMotion else { return baseDrawableSize }
        guard idleAnimation == .roam || idleAnimation == .magic else { return baseDrawableSize }
        if idleAnimation == .magic {
            return CGSize(
                width: widgetBaseSize.width + magicDrawableExtraWidth,
                height: max(widgetBaseSize.height + magicDrawableExtraHeight, baseDrawableSize.height)
            )
        }
        return CGSize(
            width: widgetBaseSize.width + MotionTokens.roamRadiusX * 2,
            height: max(widgetBaseSize.height + MotionTokens.roamRadiusY * 2, baseDrawableSize.height)
        )
    }

    static func widgetPositioningAnchor(
        idleAnimation: IdleAnimation,
        quietHoursEnabled: Bool,
        reduceMotion: Bool,
        widgetIconStyle: WidgetIconStyle = .default,
        widgetSide: WidgetSide = .right
    ) -> CGPoint {
        if widgetIconStyle == .zelda {
            switch widgetSide {
            case .left:
                return CGPoint(x: 41, y: 60)
            case .right:
                return CGPoint(x: 87, y: 60)
            }
        }

        let size = widgetDrawableSize(
            idleAnimation: idleAnimation,
            quietHoursEnabled: quietHoursEnabled,
            reduceMotion: reduceMotion,
            widgetIconStyle: widgetIconStyle
        )
        if idleAnimation == .magic && !quietHoursEnabled && !reduceMotion {
            return CGPoint(x: widgetBaseSize.width / 2, y: size.height / 2)
        }
        return CGPoint(x: size.width / 2, y: size.height / 2)
    }
}

enum EffectTokens {
    static let agedSaturation: Double = 0.4
}

enum MotionTokens {
    // Bounce, Heart, Ring, and Rage live in MotionKeyframes (keyframe-based, HTML-faithful);
    // see App/MotionKeyframes.swift. Removed legacy single-scalar tokens here.

    // Project contract: roam (running track) — 1.6s linear loop on a 32×8pt ellipse (post 64pt-widget rescale).
    static let roamDuration: TimeInterval = 1.6
    static let roamRadiusX: CGFloat = 16
    static let roamRadiusY: CGFloat = 4
    // Magic idle v2 — "magical girl" Tap-Cast: wand 4-phase cycle + wand-tip trail + radial burst.
    // Each cycle: idle (long, gentle wand sway) → windup (pull back) → strike (cast!) → recoil.
    static let magicCastInterval: TimeInterval = 4.0
    static let magicCastIdleDuration: TimeInterval = 3.0
    static let magicCastWindupDuration: TimeInterval = 0.3
    static let magicCastStrikeDuration: TimeInterval = 0.2
    static let magicCastRecoilDuration: TimeInterval = 0.5
    // Wand-tip trail — small sparkles drift off the wand tip during idle motion.
    static let magicTrailSpawnInterval: TimeInterval = 0.18
    static let magicTrailLifetime: TimeInterval = 0.6
    static let magicTrailMaxCount: Int = 6
    static let magicTrailSize: CGFloat = 4
    // Burst spray — radial sparkles fired from the wand tip at the strike moment.
    static let magicBurstSparkCount: Int = 8
    static let magicBurstSparkRadius: CGFloat = 20
    static let magicBurstSparkDuration: TimeInterval = 0.6
    static let magicBurstSparkSize: CGFloat = 5
    // Project contract: rage — 950ms throw-windup looped every 2.4s.
    static let ragePeriod: TimeInterval = 2.4
    static let rageWindupDuration: TimeInterval = 0.95
    // Project contract: new-alert pulse and sonar wave.
    static let newAlertPulseDuration: TimeInterval = 0.45
    static let newAlertPulsePeakScale: CGFloat = 1.14
    static let newAlertPulseSquashScale: CGFloat = 0.96
    static let newAlertPulseSettleScale: CGFloat = 1.06
    static let newAlertPulseRotation: Double = 7
    static let sonarDuration: TimeInterval = 0.75
    static let sonarStartScale: CGFloat = 0.5
    static let sonarEndScale: CGFloat = 3.0
    // Keep the 3x sonar wave inside WidgetIconView's fixed 64pt drawable area (18 * 3 = 54pt).
    static let sonarBaseDiameter: CGFloat = 18
    static let sonarStartOpacity: Double = 0.75
    // Project contract: status dot ripple (just-arrived).
    static let statusDotRippleDuration: TimeInterval = 1.0
    static let statusDotRippleEndScale: CGFloat = 2.4
    static let statusDotRippleStartOpacity: Double = 0.6
    static let statusDotRippleRepeatCount: Int = 3
    // Internal prototype `.status-dot.waiting` attention pulse — 1.6s easeInOut opacity 1.0↔0.5.
    static let waitingDotPulseDuration: TimeInterval = 1.6
    static let waitingDotPulseMinOpacity: Double = 0.5
    static let reduceMotionFadeDuration: TimeInterval = 0.15

    static func roamAnimation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .linear(duration: roamDuration).repeatForever(autoreverses: false)
    }
}
