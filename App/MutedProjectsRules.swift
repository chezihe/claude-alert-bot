// App/MutedProjectsRules.swift — WO-007 Settings muted-projects section rules.
import Foundation

/// Context-menu mute choices. Muted alerts are dropped (not queued), so there is
/// deliberately no open-ended "until unmuted" option.
enum MuteDuration: CaseIterable, Identifiable {
    case fifteenMinutes
    case oneHour
    case fourHours
    case restOfToday

    var id: Self { self }

    var label: String {
        switch self {
        case .fifteenMinutes: return "For 15 Minutes"
        case .oneHour: return "For 1 Hour"
        case .fourHours: return "For 4 Hours"
        case .restOfToday: return "For Rest of Today"
        }
    }

    func expiresAt(from now: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .fifteenMinutes: return now.addingTimeInterval(15 * 60)
        case .oneHour: return now.addingTimeInterval(60 * 60)
        case .fourHours: return now.addingTimeInterval(4 * 60 * 60)
        case .restOfToday:
            let startOfToday = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now.addingTimeInterval(24 * 60 * 60)
        }
    }
}

struct MutedEntry: Equatable {
    let project: String
    let expiresAt: Date
}

/// Pure-function namespace for SettingsView muted-projects section.
/// Tested without SwiftUI rendering.
enum MutedProjectsRules {
    /// Active, unexpired mutes sorted alphabetically by project. Expiry is strict `>` now.
    static func activeMutes(_ mutes: [String: Date], now: Date) -> [MutedEntry] {
        mutes
            .filter { $0.value > now }
            .map { MutedEntry(project: $0.key, expiresAt: $0.value) }
            .sorted { $0.project < $1.project }
    }

    /// Single source of the mute-expiry rule; shared by SettingsStore and SessionRegistry.
    static func isMuted(_ mutes: [String: Date], project: String, now: Date) -> Bool {
        (mutes[project] ?? .distantPast) > now
    }

    /// Minimal English remaining-time label, floored to minutes; switches to hours at 60 min.
    static func remainingMinutesLabel(expiresAt: Date, now: Date) -> String {
        let secs = expiresAt.timeIntervalSince(now)
        let mins = Int(secs / 60)
        if mins < 1 { return "<1 min left" }
        if mins < 60 { return "\(mins) min left" }
        let hours = mins / 60
        let rest = mins % 60
        return rest == 0 ? "\(hours)h left" : "\(hours)h \(rest)m left"
    }
}
