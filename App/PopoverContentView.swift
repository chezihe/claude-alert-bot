// App/PopoverContentView.swift — Phase 2 / Plan 02-08 popover container view.
// UI-SPEC §"Hover Popover" — 280pt fixed width, max 8 visible rows + ScrollView with hidden indicators,
// top-trailing "모두 지우기" (Clear all) visible only when rowCount>=2 (D2-07; non-destructive — no confirm).
// D2-06 row display rules; D2-08 row click → SessionRegistry.shared.clearOne(...) + [would-jump session=<uuid>] log.
// Phase 03.1 — geometry literals consume GeometryTokens (F-1: token = 280, code SoT, not SPEC's 270).
// PopoverContentRules is the pure-function namespace tested in PopoverContentTests.
import SwiftUI
import AppKit

// MARK: - Pure display rules (testable without SwiftUI rendering)

enum PopoverContentRules {
    static let agingThresholdSec: TimeInterval = 60 * 60

    static func isAged(session: CompletedSession, now: Date) -> Bool {
        now.timeIntervalSince(session.stoppedAt) > agingThresholdSec
    }

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

    static func orderedByPinnedThenStoppedAt(_ queue: [CompletedSession]) -> [CompletedSession] {
        queue.enumerated().sorted { lhs, rhs in
            let left = lhs.element
            let right = rhs.element
            if left.pinned != right.pinned { return left.pinned && !right.pinned }
            if left.stoppedAt != right.stoppedAt { return left.stoppedAt > right.stoppedAt }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

// MARK: - SwiftUI container

struct PopoverContentView: View {
    let queue: [CompletedSession]
    let onRowClick: (String) -> Void   // sessionID
    let onClearAll: () -> Void
    var onTogglePin: (String) -> Void = { _ in }
    var onToggleMute: (String) -> Void = { _ in }
    var isProjectMuted: (String) -> Bool = { _ in false }
    /// Phase 3 D3-11 — state map keyed by sessionID. Default empty → all rows render in `.normal`.
    /// Owned by WidgetPopoverController (03-07); content view stays pure (no @State).
    var rowStates: [String: RowState] = [:]
    /// Phase 3 D3-11 — fired after a row's `.missing` collapse animation completes.
    /// Forwarded to `SessionRegistry.shared.clearOne(sessionID:)` by the parent.
    var onRowMissingComplete: (String) -> Void = { _ in }
    /// Phase 3 03-09 fix — hover state change for the popover surface itself.
    /// Parent (WidgetPopoverController) cancels its widget-exit dismiss timer while
    /// hovering=true so the user can travel from the menu-bar icon onto the popover
    /// without the 250ms widget exit grace dismissing the popover mid-flight.
    var onPopoverHoverChange: (Bool) -> Void = { _ in }

    private var dupProjects: Set<String> {
        PopoverContentRules.projectsWithDuplicates(queue)
    }

    private var orderedQueue: [CompletedSession] {
        PopoverContentRules.orderedByPinnedThenStoppedAt(queue)
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
                    ForEach(orderedQueue) { session in
                        PopoverRowView(
                            session: session,
                            showTimeSuffix: dupProjects.contains(session.projectName),
                            state: rowStates[session.sessionID, default: .normal],
                            isMuted: isProjectMuted(session.projectName),
                            onClick: { onRowClick(session.sessionID) },
                            onTogglePin: { onTogglePin(session.sessionID) },
                            onToggleMute: { onToggleMute(session.projectName) },
                            onMissingComplete: { onRowMissingComplete(session.sessionID) }
                        )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: GeometryTokens.rowMinHeight * CGFloat(GeometryTokens.popoverMaxVisibleRows))
        }
        .frame(width: GeometryTokens.popoverWidth)
        .background(.thinMaterial)
        .onHover { hovering in onPopoverHoverChange(hovering) }
    }
}
