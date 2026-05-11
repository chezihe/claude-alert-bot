// App/PopoverContentView.swift — Phase 2 / Plan 02-08 popover container view.
// UI-SPEC §"Hover Popover" — fixed width, capped visible rows + ScrollView with hidden indicators,
// top-trailing clear control visible only when at least two unpinned sessions are clearable.
// D2-06 row display rules; D2-08 row click → SessionRegistry.shared.clearOne(...) + [would-jump session=<uuid>] log.
// Phase 03.1 — geometry literals consume GeometryTokens.
// PopoverContentRules is the pure-function namespace tested in PopoverContentTests.
import SwiftUI
import AppKit

// MARK: - Pure display rules (testable without SwiftUI rendering)

enum PopoverListItem: Equatable, Identifiable {
    case group(projectName: String, count: Int, isExpanded: Bool)
    case session(CompletedSession, showTimeSuffix: Bool)

    var id: String {
        switch self {
        case .group(let projectName, _, _):
            return "group:\(projectName)"
        case .session(let session, _):
            return "session:\(session.id)"
        }
    }
}

enum PopoverContentRules {
    static let agingThresholdSec: TimeInterval = 60 * 60
    static let justArrivedWindowSec: TimeInterval = 3

    static func isAged(session: CompletedSession, now: Date) -> Bool {
        now.timeIntervalSince(session.stoppedAt) > agingThresholdSec
    }

    static func isJustArrived(session: CompletedSession, now: Date) -> Bool {
        let age = now.timeIntervalSince(session.stoppedAt)
        return age >= 0 && age <= justArrivedWindowSec
    }

    /// D2-07 + UI-SPEC line 89: Clear control visible only when ≥2 clearable sessions.
    static func shouldShowClearAll(clearableCount: Int) -> Bool { clearableCount >= 2 }

    static func clearableSessionCount(_ queue: [CompletedSession]) -> Int {
        queue.filter { !$0.pinned }.count
    }

    static func clearAllButtonLabel(queue: [CompletedSession]) -> String {
        queue.contains { $0.pinned } ? "Clear Unpinned" : "Clear All"
    }

    static func shouldShowEmptyState(queue: [CompletedSession], everHadAlerts: Bool) -> Bool {
        queue.isEmpty && !everHadAlerts
    }

    static func visibleQueue(displayQueue: [CompletedSession],
                             incomingQueue: [CompletedSession],
                             hasAppeared: Bool) -> [CompletedSession] {
        if !hasAppeared && displayQueue.isEmpty {
            return incomingQueue
        }
        return displayQueue
    }

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

    static func groupedListItems(_ queue: [CompletedSession], expandedProjects: Set<String>) -> [PopoverListItem] {
        let ordered = orderedByPinnedThenStoppedAt(queue)
        var counts: [String: Int] = [:]
        for session in queue { counts[session.projectName, default: 0] += 1 }
        let groupedByProject = Dictionary(grouping: ordered, by: \.projectName)
        let duplicateProjects = projectsWithDuplicates(queue)
        var emittedGroups: Set<String> = []
        var items: [PopoverListItem] = []

        for session in ordered {
            let count = counts[session.projectName, default: 0]
            if count >= 3 {
                guard !emittedGroups.contains(session.projectName) else { continue }
                emittedGroups.insert(session.projectName)
                let isExpanded = expandedProjects.contains(session.projectName)
                items.append(.group(projectName: session.projectName, count: count, isExpanded: isExpanded))
                if isExpanded {
                    for groupedSession in groupedByProject[session.projectName, default: []] {
                        items.append(.session(groupedSession, showTimeSuffix: true))
                    }
                }
            } else {
                items.append(.session(session, showTimeSuffix: duplicateProjects.contains(session.projectName)))
            }
        }

        return items
    }

    static func displayRowCount(_ queue: [CompletedSession], expandedProjects: Set<String>) -> Int {
        groupedListItems(queue, expandedProjects: expandedProjects).count
    }

    static func canCollapseProjectGroup(projectName: String,
                                        queue: [CompletedSession],
                                        rowStates: [String: RowState]) -> Bool {
        !queue.contains { session in
            session.projectName == projectName &&
            rowStates[session.id, default: .normal] != .normal
        }
    }

    static func scrollFadeVisibility(contentMinY: CGFloat,
                                     contentMaxY: CGFloat,
                                     viewportHeight: CGFloat,
                                     isScrollable: Bool) -> (top: Bool, bottom: Bool) {
        guard isScrollable, viewportHeight > 0 else { return (false, false) }
        let epsilon: CGFloat = 0.5
        return (
            top: contentMinY < -epsilon,
            bottom: contentMaxY > viewportHeight + epsilon
        )
    }
}

// MARK: - SwiftUI container

struct PopoverContentView: View {
    let queue: [CompletedSession]
    let onRowClick: (String) -> Void   // alertID
    let onClearAll: () -> Void
    var onTogglePin: (String) -> Void = { _ in }
    var onToggleMute: (String) -> Void = { _ in }
    var isProjectMuted: (String) -> Bool = { _ in false }
    /// Phase 3 D3-11 — state map keyed by sessionID. Default empty → all rows render in `.normal`.
    /// Owned by WidgetPopoverController (03-07); content view stays pure (no @State).
    var rowStates: [String: RowState] = [:]
    /// Phase 3 D3-11 — fired after a row's `.missing` collapse animation completes.
    /// Forwarded to `SessionRegistry.shared.clearOne(alertID:)` by the parent.
    var onRowMissingComplete: (String) -> Void = { _ in }
    /// Phase 3 03-09 fix — hover state change for the popover surface itself.
    /// Parent (WidgetPopoverController) cancels its widget-exit dismiss timer while
    /// hovering=true so the user can travel from the menu-bar icon onto the popover
    /// without the 250ms widget exit grace dismissing the popover mid-flight.
    var onPopoverHoverChange: (Bool) -> Void = { _ in }
    var onOpenSettings: () -> Void = {}
    var expandedProjects: Set<String> = []
    var widgetCorner: WidgetCorner = .topRight
    var onToggleGroup: (String) -> Void = { _ in }
    var everHadAlerts: Bool = false

    @State private var displayQueue: [CompletedSession] = []
    @State private var hasAppeared: Bool = false
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var scrollContentFrame: CGRect = .zero

    /// Anchor for the spring entry scale. The popover should appear to
    /// expand outward from the widget glyph that triggered it.
    private var entryAnchor: UnitPoint {
        switch widgetCorner {
        case .topLeft:     return .topLeading
        case .topRight:    return .topTrailing
        case .bottomLeft:  return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    private static let scrollCoordinateSpaceName = "PopoverScrollView"

    private var visibleQueue: [CompletedSession] {
        PopoverContentRules.visibleQueue(
            displayQueue: displayQueue,
            incomingQueue: queue,
            hasAppeared: hasAppeared
        )
    }

    private var listItems: [PopoverListItem] {
        PopoverContentRules.groupedListItems(visibleQueue, expandedProjects: expandedProjects)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Spacer()
                let clearableSessionCount = PopoverContentRules.clearableSessionCount(displayQueue)
                let clearAllLabel = PopoverContentRules.clearAllButtonLabel(queue: displayQueue)
                if PopoverContentRules.shouldShowClearAll(clearableCount: clearableSessionCount) {
                    Button(clearAllLabel, action: onClearAll)
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .accessibilityLabel(clearAllLabel)
                }
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Settings")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if PopoverContentRules.shouldShowEmptyState(queue: visibleQueue, everHadAlerts: everHadAlerts) {
                EmptyStateView()
            } else if !visibleQueue.isEmpty {
                let isScrollable = listItems.count > GeometryTokens.popoverMaxVisibleRows
                let fades = PopoverContentRules.scrollFadeVisibility(
                    contentMinY: scrollContentFrame.minY,
                    contentMaxY: scrollContentFrame.maxY,
                    viewportHeight: scrollViewportHeight,
                    isScrollable: isScrollable
                )
                ScrollView {
                    VStack(spacing: 0) {
                        HideScrollerIntrospector()
                            .frame(width: 0, height: 0)
                        ForEach(listItems) { item in
                            Group {
                                switch item {
                                case .group(let projectName, let count, let isExpanded):
                                    ProjectGroupHeaderView(
                                        projectName: projectName,
                                        count: count,
                                        isExpanded: isExpanded,
                                        isMuted: isProjectMuted(projectName),
                                        onClick: { onToggleGroup(projectName) },
                                        onToggleMute: { onToggleMute(projectName) }
                                    )
                                case .session(let session, let showTimeSuffix):
                                    PopoverRowView(
                                        session: session,
                                        showTimeSuffix: showTimeSuffix,
                                        state: rowStates[session.id, default: .normal],
                                        isMuted: isProjectMuted(session.projectName),
                                        onClick: { onRowClick(session.id) },
                                        onTogglePin: { onTogglePin(session.id) },
                                        onToggleMute: { onToggleMute(session.projectName) },
                                        onMissingComplete: { onRowMissingComplete(session.id) }
                                    )
                                }
                            }
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .move(edge: .trailing).combined(with: .opacity)
                            ))
                        }
                    }
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: PopoverScrollContentFramePreferenceKey.self,
                                value: proxy.frame(in: .named(Self.scrollCoordinateSpaceName))
                            )
                        }
                    )
                }
                .scrollIndicators(.never)
                .frame(maxHeight: CGFloat(min(
                    PopoverContentRules.displayRowCount(visibleQueue, expandedProjects: expandedProjects),
                    GeometryTokens.popoverMaxVisibleRows
                )) * GeometryTokens.rowMinHeight)
                .coordinateSpace(name: Self.scrollCoordinateSpaceName)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: PopoverScrollViewportHeightPreferenceKey.self,
                            value: proxy.size.height
                        )
                    }
                )
                .onPreferenceChange(PopoverScrollViewportHeightPreferenceKey.self) { height in
                    scrollViewportHeight = height
                }
                .onPreferenceChange(PopoverScrollContentFramePreferenceKey.self) { frame in
                    scrollContentFrame = frame
                }
                .mask(PopoverScrollFadeMask(showsTopFade: fades.top, showsBottomFade: fades.bottom))
            }
        }
        .scaleEffect(hasAppeared ? 1.0 : 0.85, anchor: entryAnchor)
        .opacity(hasAppeared ? 1.0 : 0.0)
        .onAppear {
            displayQueue = queue
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                hasAppeared = true
            }
        }
        .onChange(of: queue) { _, newQueue in
            withAnimation(.easeIn(duration: 0.32)) {
                displayQueue = newQueue
            }
        }
        .frame(width: GeometryTokens.popoverWidth)
        .background(PopoverMaterialBackground())
        .onHover { hovering in onPopoverHoverChange(hovering) }
    }
}

private struct PopoverScrollFadeMask: View {
    let showsTopFade: Bool
    let showsBottomFade: Bool

    var body: some View {
        let fadeHeight = GeometryTokens.popoverScrollFadeHeight
        VStack(spacing: 0) {
            if showsTopFade {
                LinearGradient(colors: [.clear, .black],
                               startPoint: .top,
                               endPoint: .bottom)
                    .frame(height: fadeHeight)
            } else {
                Rectangle().fill(.black)
                    .frame(height: fadeHeight)
            }
            Rectangle().fill(.black)
            if showsBottomFade {
                LinearGradient(colors: [.black, .clear],
                               startPoint: .top,
                               endPoint: .bottom)
                    .frame(height: fadeHeight)
            } else {
                Rectangle().fill(.black)
                    .frame(height: fadeHeight)
            }
        }
    }
}

private struct PopoverScrollViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct PopoverScrollContentFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Walks up the AppKit hierarchy from the SwiftUI ScrollView's content view to
/// find the enclosing NSScrollView and (a) disable its scrollers outright and
/// (b) make its background fully transparent so the popover's material shows
/// through. `.scrollIndicators(.never)` and SwiftUI's clear background do not
/// reliably handle either on macOS.
private struct HideScrollerIntrospector: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let probe = NSView(frame: .zero)
        DispatchQueue.main.async { [weak probe] in
            guard let scrollView = probe?.enclosingScrollView else { return }
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.borderType = .noBorder
            scrollView.contentView.drawsBackground = false
        }
        return probe
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

private struct PopoverMaterialBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
    }
}

private struct ProjectGroupHeaderView: View {
    let projectName: String
    let count: Int
    let isExpanded: Bool
    let isMuted: Bool
    let onClick: () -> Void
    let onToggleMute: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .frame(width: 7, height: 7)
                Text(projectName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(NSColor.labelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(minWidth: 18, minHeight: 16)
                    .background(
                        Capsule().fill(Color(NSColor.systemGray))
                    )
            }
            .padding(.vertical, GeometryTokens.rowVerticalPadding)
            .padding(.horizontal, GeometryTokens.rowHorizontalPadding)
            .frame(minHeight: GeometryTokens.rowMinHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovered ? ColorTokens.rowHover(colorScheme: colorScheme) : Color.clear
            )
            .opacity(isMuted ? 0.6 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(isMuted ? "Unmute This Project" : "Mute this project for 1h") { onToggleMute() }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel("\(projectName), \(count) sessions, \(isExpanded ? "expanded" : "collapsed")")
    }
}
