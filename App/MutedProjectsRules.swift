// App/MutedProjectsRules.swift — WO-007 Settings muted-projects section rules.
import Foundation

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

    /// Minimal English remaining-time label, floored to minutes.
    static func remainingMinutesLabel(expiresAt: Date, now: Date) -> String {
        let secs = expiresAt.timeIntervalSince(now)
        let mins = Int(secs / 60)
        if mins < 1 { return "<1 min left" }
        return "\(mins) min left"
    }
}
