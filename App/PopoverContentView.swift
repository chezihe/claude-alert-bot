// App/PopoverContentView.swift — Phase 2 / Plan 02-08 popover container view.
// UI-SPEC §"Hover Popover" — 280pt fixed width, max 8 visible rows + ScrollView with hidden indicators,
// top-trailing "모두 지우기" (Clear all) visible only when rowCount>=2 (D2-07; non-destructive — no confirm).
// D2-06 row display rules; D2-08 row click → SessionRegistry.shared.clearOne(...) + [would-jump session=<uuid>] log.
// PopoverContentRules is the pure-function namespace tested in PopoverContentTests.
import SwiftUI
import AppKit

// MARK: - Pure display rules (testable without SwiftUI rendering)

enum PopoverContentRules {
    /// D2-07 + UI-SPEC line 89: Clear all visible only when ≥2 rows.
    static func shouldShowClearAll(rowCount: Int) -> Bool { rowCount >= 2 }

    /// D2-06: same-project duplicates → time suffix on those rows only.
    /// Returns the set of project names that appear ≥2 times in the queue.
    static func projectsWithDuplicates(_ queue: [CompletedSession]) -> Set<String> {
        var counts: [String: Int] = [:]
        for s in queue { counts[s.projectName, default: 0] += 1 }
        return Set(counts.filter { $0.value >= 2 }.keys)
    }

    /// "HH:mm" formatter for the secondary time-suffix label.
    static func timeSuffix(for date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// D2-16: durationSec == nil → orphan stop, show trailing `?` indicator.
    static func showsOrphanIndicator(session: CompletedSession) -> Bool {
        session.durationSec == nil
    }

    /// Phase 3 ITermBridge marks a session unavailable when its iTerm2 session UUID
    /// no longer resolves (closed window/tab). The popover surface stays mounted —
    /// we do not auto-clear, since the alert itself is still informational.
    static func isUnavailable(sessionID: String, in set: Set<String>) -> Bool {
        set.contains(sessionID)
    }

    /// Locked copy for the unavailable trailing label. Asserted by PopoverContentTests.
    /// Minimal English + "session" terminology per project UI tone.
    static let unavailableLabelText = "Session unavailable"
}

// MARK: - SwiftUI container

struct PopoverContentView: View {
    let queue: [CompletedSession]
    let onRowClick: (String) -> Void   // sessionID
    let onClearAll: () -> Void
    /// Phase 3 ITermBridge populates this on jump failure; defaulted empty until then.
    var unavailableSessionIDs: Set<String> = []

    private var dupProjects: Set<String> {
        PopoverContentRules.projectsWithDuplicates(queue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if PopoverContentRules.shouldShowClearAll(rowCount: queue.count) {
                HStack {
                    Spacer()
                    Button("모두 지우기", action: onClearAll)
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .accessibilityLabel("모든 알림 지우기")
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(queue) { session in
                        PopoverRowView(
                            session: session,
                            showTimeSuffix: dupProjects.contains(session.projectName),
                            isAvailable: !PopoverContentRules.isUnavailable(
                                sessionID: session.sessionID,
                                in: unavailableSessionIDs
                            ),
                            onClick: { onRowClick(session.sessionID) }
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 36 * 8)   // UI-SPEC: max 8 visible rows
        }
        .frame(width: 280)
        .background(.thinMaterial)
    }
}
