// App/DesignTokens.swift — Phase 03.1 design system foundation.
// Single source of truth for visual + motion tokens traceable to SPEC.md §3 + §4.
// Per D2-29: zero external Swift deps. All call-sites in WidgetIconView / PopoverContentView /
// PopoverRowView resolve through this module (SC#1).
// Reduce-motion gate is owned by MotionTokens factory (D4 / SC#3) — call-sites pass a Bool;
// they choose @Environment(\.accessibilityReduceMotion) (SwiftUI) or
// NSWorkspace.shared.accessibilityDisplayShouldReduceMotion (AppKit) at the call-site.
// Findings F-1, F-2, F-3 documented in 03.1-SUMMARY.md.
import SwiftUI
import AppKit

enum ColorTokens {
    // SPEC.md §3 row "Accent (warm orange)"
    static let accent: Color = makeColor(hex: 0xD97757)
    // SPEC.md §3 row "Accent dark"
    static let accentDark: Color = makeColor(hex: 0xB8492C)
    // SPEC.md §3 row "Status: success"
    static let statusSuccess: Color = makeColor(hex: 0xD97757)
    // SPEC.md §3 row "Status: error"
    static let statusError: Color = makeColor(hex: 0xE5484D)
    // SPEC.md §3 row "Status: waiting"
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

    // SPEC.md §3 row "Row hover"
    static func rowHover(colorScheme: ColorScheme) -> Color {
        statusSuccess.opacity(colorScheme == .dark ? 0.20 : 0.13)
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
    // SPEC.md §3 row "Popover: 270pt wide" — WO-009 reconciles code/spec.
    static let popoverWidth: CGFloat = 270
    // SPEC.md §3 row "Popover: 14pt corner radius"
    static let popoverCornerRadius: CGFloat = 14
    // SPEC.md §3 row "Row: 36pt min height"
    static let rowMinHeight: CGFloat = 36
    // SPEC.md §3 row "12pt horizontal padding"
    static let rowHorizontalPadding: CGFloat = 12
    // SPEC.md §3 row "8pt vertical padding"
    static let rowVerticalPadding: CGFloat = 8
    // SPEC.md §3 row "Status dot: 7pt"
    static let statusDotDiameter: CGFloat = 7
    // SPEC.md §3 row "hollow ring stroke 1.5pt"
    static let statusDotRingStroke: CGFloat = 1.5
    // FEATURES.md §3 row "최대 4행 표시" — WO-009 enforces; rows beyond scroll vertically.
    static let popoverMaxVisibleRows: Int = 4
    static let widgetBaseSize = CGSize(width: 44, height: 44)

    static func widgetDrawableSize(
        idleAnimation: IdleAnimation,
        quietHoursEnabled: Bool,
        reduceMotion: Bool
    ) -> CGSize {
        guard idleAnimation == .roam, !quietHoursEnabled, !reduceMotion else { return widgetBaseSize }
        return CGSize(
            width: widgetBaseSize.width + MotionTokens.roamRadiusX * 2,
            height: widgetBaseSize.height + MotionTokens.roamRadiusY * 2
        )
    }
}

enum EffectTokens {
    static let agedSaturation: Double = 0.4
}

enum MotionTokens {
    // SPEC.md §4 row "Bounce (idle)" — 0.45s duration, 5pt vertical, easeInOut, autoreverse, infinite.
    static let bounceDuration: TimeInterval = 0.45
    static let bounceOffset: CGFloat = 5
    static let bounceStretchScale: CGFloat = 1.04
    static let bounceSquashScale: CGFloat = 0.94
    // SPEC.md §4 row "Breathe" — 2.4s, autoreverse, infinite, easeInOut, scale 1.0↔1.06.
    static let breatheDuration: TimeInterval = 2.4
    static let breatheScale: CGFloat = 1.06
    // SPEC.md §4 row "Ring (bell)" — 0.55s, easeInOut, rotate ±10° from top anchor.
    static let ringDuration: TimeInterval = 0.55
    static let ringRotation: Double = 10
    // SPEC.md §4 row "Roam (running track)" — 1.6s linear loop on a 24×6pt ellipse.
    static let roamDuration: TimeInterval = 1.6
    static let roamRadiusX: CGFloat = 12
    static let roamRadiusY: CGFloat = 3
    // SPEC.md §4 rows "New-alert pulse" and "Sonar wave".
    static let newAlertPulseDuration: TimeInterval = 0.45
    static let newAlertPulsePeakScale: CGFloat = 1.14
    static let newAlertPulseSquashScale: CGFloat = 0.96
    static let newAlertPulseSettleScale: CGFloat = 1.06
    static let newAlertPulseRotation: Double = 7
    static let sonarDuration: TimeInterval = 0.75
    static let sonarStartScale: CGFloat = 0.5
    static let sonarEndScale: CGFloat = 3.0
    // Keep the 3x sonar wave inside WidgetIconView's fixed 44pt drawable area.
    static let sonarBaseDiameter: CGFloat = 14
    static let sonarStartOpacity: Double = 0.75
    // SPEC.md §4 row "Status dot ripple (just-arrived)".
    static let statusDotRippleDuration: TimeInterval = 1.0
    static let statusDotRippleEndScale: CGFloat = 2.4
    static let statusDotRippleStartOpacity: Double = 0.6
    static let statusDotRippleRepeatCount: Int = 3
    static let reduceMotionFadeDuration: TimeInterval = 0.15

    /// D4 (SC#3) — uniform reduce-motion gate. Returns nil when reduce-motion is on so call-sites
    /// can `if let anim = MotionTokens.bounceAnimation(...) { withAnimation(anim) { ... } }`.
    /// Caller passes the Bool from whichever native API is natural (SwiftUI Environment / NSWorkspace).
    static func bounceAnimation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: bounceDuration).repeatForever(autoreverses: true)
    }

    static func breatheAnimation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: breatheDuration).repeatForever(autoreverses: true)
    }

    static func ringAnimation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .easeInOut(duration: ringDuration).repeatForever(autoreverses: true)
    }

    static func roamAnimation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        return .linear(duration: roamDuration).repeatForever(autoreverses: false)
    }
}
