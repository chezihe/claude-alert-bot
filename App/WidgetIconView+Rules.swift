// App/WidgetIconView+Rules.swift — pure layout / gating rules for WidgetIconView.
// Kept free of view state so the idle gate, badge selection, glyph geometry and
// accessibility copy can be unit-tested directly.
import SwiftUI

extension WidgetIconView {
    static let badgeOffset = CGSize(width: -2, height: -10)
    static let claudeGlyphSize = CGSize(width: 46, height: 46)
    static let zeldaGlyphSize = CGSize(width: 92, height: 92)
    static let fixedGlyphOffset = CGSize(width: 0, height: 8)
    static let zeldaGlyphOffset = CGSize(width: 0, height: 18)

    enum BadgeKind: Equatable {
        case none
        case count      // "+N" capsule (Claude icon, 2+ sessions)
        case hearts     // Zelda heart strip (1+ sessions)
    }

    /// The idle motion that should actually run, or nil when the glyph must stay still.
    /// Idle motions are Claude-icon only and suppressed by Quiet Hours and Reduce Motion.
    static func activeIdle(
        idleAnimation: IdleAnimation,
        widgetIconStyle: WidgetIconStyle,
        quietHoursEnabled: Bool,
        reduceMotion: Bool
    ) -> IdleAnimation? {
        guard widgetIconStyle == .claude, !quietHoursEnabled, !reduceMotion else { return nil }
        return idleAnimation
    }

    static func badgeKind(widgetIconStyle: WidgetIconStyle, pendingCount: Int) -> BadgeKind {
        if widgetIconStyle == .zelda {
            return pendingCount >= 1 ? .hearts : .none
        }
        return pendingCount >= 2 ? .count : .none
    }

    /// "+N" shows the total pending session count (not the count beyond the first).
    static func badgeText(pendingCount: Int) -> String {
        "+\(pendingCount)"
    }

    static func glyphSize(for style: WidgetIconStyle) -> CGSize {
        style == .zelda ? zeldaGlyphSize : claudeGlyphSize
    }

    static func glyphOffset(for style: WidgetIconStyle) -> CGSize {
        style == .zelda ? zeldaGlyphOffset : fixedGlyphOffset
    }

    static func shouldRunAlertPulse(alertPulseID: Int, activeAlertPulseID: Int, quietHoursEnabled: Bool) -> Bool {
        alertPulseID > 0 && alertPulseID != activeAlertPulseID && !quietHoursEnabled
    }

    static func accessibilityLabel(pendingCount: Int, quietHoursEnabled: Bool) -> String {
        let sessionCount = pendingCount == 1 ? "1 pending session" : "\(pendingCount) pending sessions"
        let quietSuffix = quietHoursEnabled ? ". Quiet Hours" : ""
        return "Claude alert. \(sessionCount)\(quietSuffix)"
    }
}
