// ClaudeAlertBotTests/PopoverContentTests.swift — Phase 2 / Plan 02-08 Task 1
// Tests for PopoverContentRules pure namespace (display logic extracted from SwiftUI views).
// Anchors: D2-06 (same-project duplicates → time suffix), D2-07 (Clear all visible at rowCount>=2),
// D2-16 (orphan ? when durationSec == nil), UI-SPEC §"Popover row states".
import XCTest
@testable import ClaudeAlertBot

final class PopoverContentTests: XCTestCase {

    // MARK: - D2-07 Clear all gating (UI-SPEC line 89 anchor)

    func test_clearAllVisibility_oneRow_hidden() {
        XCTAssertFalse(PopoverContentRules.shouldShowClearAll(rowCount: 1))
    }

    func test_clearAllVisibility_twoRows_visible() {
        XCTAssertTrue(PopoverContentRules.shouldShowClearAll(rowCount: 2))
    }

    // MARK: - D2-06 same-project duplicates → time suffix on those rows

    func test_sameProjectDuplicates_groupedSet() {
        let s1 = mkSession(id: "a", project: "A")
        let s2 = mkSession(id: "b", project: "B")
        let s3 = mkSession(id: "c", project: "A")
        let dups = PopoverContentRules.projectsWithDuplicates([s1, s2, s3])
        XCTAssertEqual(dups, Set(["A"]))
    }

    func test_groupedListItems_collapsesThreeSameProjectSessions() {
        let queue = [
            mkSession(id: "a1", project: "Alpha", stoppedAt: Date(timeIntervalSince1970: 300)),
            mkSession(id: "b1", project: "Beta", stoppedAt: Date(timeIntervalSince1970: 250)),
            mkSession(id: "a2", project: "Alpha", stoppedAt: Date(timeIntervalSince1970: 200)),
            mkSession(id: "a3", project: "Alpha", stoppedAt: Date(timeIntervalSince1970: 100))
        ]

        let items = PopoverContentRules.groupedListItems(queue, expandedProjects: [])

        XCTAssertEqual(items.map(\.id), ["group:Alpha", "session:b1"])
        XCTAssertEqual(items.first, .group(projectName: "Alpha", count: 3, isExpanded: false))
        XCTAssertEqual(PopoverContentRules.displayRowCount(queue, expandedProjects: []), 2)
    }

    func test_groupedListItems_expandedProjectIncludesHeaderAndRows() {
        let queue = [
            mkSession(id: "a1", project: "Alpha", stoppedAt: Date(timeIntervalSince1970: 300)),
            mkSession(id: "b1", project: "Beta", stoppedAt: Date(timeIntervalSince1970: 250)),
            mkSession(id: "a2", project: "Alpha", stoppedAt: Date(timeIntervalSince1970: 200)),
            mkSession(id: "a3", project: "Alpha", stoppedAt: Date(timeIntervalSince1970: 100))
        ]

        let items = PopoverContentRules.groupedListItems(queue, expandedProjects: ["Alpha"])

        XCTAssertEqual(items.map(\.id), ["group:Alpha", "session:a1", "session:a2", "session:a3", "session:b1"])
        XCTAssertEqual(items.first, .group(projectName: "Alpha", count: 3, isExpanded: true))
        XCTAssertEqual(PopoverContentRules.displayRowCount(queue, expandedProjects: ["Alpha"]), 5)
    }

    func test_groupedListItems_keepsTwoSameProjectSessionsAsRowsWithTimeSuffix() throws {
        let queue = [
            mkSession(id: "a1", project: "Alpha", stoppedAt: Date(timeIntervalSince1970: 300)),
            mkSession(id: "a2", project: "Alpha", stoppedAt: Date(timeIntervalSince1970: 200))
        ]

        let items = PopoverContentRules.groupedListItems(queue, expandedProjects: [])

        XCTAssertEqual(items.map(\.id), ["session:a1", "session:a2"])
        guard case .session(_, let showFirstTimeSuffix)? = items.first,
              case .session(_, let showSecondTimeSuffix)? = items.last else {
            return XCTFail("Expected two session rows")
        }
        XCTAssertTrue(showFirstTimeSuffix)
        XCTAssertTrue(showSecondTimeSuffix)
    }

    func test_canCollapseProjectGroup_blocksJumpingChildRows() {
        let queue = [
            mkSession(id: "a1", project: "Alpha"),
            mkSession(id: "a2", project: "Alpha"),
            mkSession(id: "a3", project: "Alpha")
        ]

        XCTAssertFalse(PopoverContentRules.canCollapseProjectGroup(
            projectName: "Alpha",
            queue: queue,
            rowStates: ["a2": .jumping]
        ))
    }

    func test_canCollapseProjectGroup_blocksMissingChildRows() {
        let queue = [
            mkSession(id: "a1", project: "Alpha"),
            mkSession(id: "a2", project: "Alpha"),
            mkSession(id: "a3", project: "Alpha")
        ]

        XCTAssertFalse(PopoverContentRules.canCollapseProjectGroup(
            projectName: "Alpha",
            queue: queue,
            rowStates: ["a2": .missing]
        ))
    }

    func test_canCollapseProjectGroup_allowsNormalAndOtherProjectRows() {
        let queue = [
            mkSession(id: "a1", project: "Alpha"),
            mkSession(id: "a2", project: "Alpha"),
            mkSession(id: "a3", project: "Alpha"),
            mkSession(id: "b1", project: "Beta")
        ]

        XCTAssertTrue(PopoverContentRules.canCollapseProjectGroup(
            projectName: "Alpha",
            queue: queue,
            rowStates: ["a2": .normal, "b1": .jumping]
        ))
    }

    func test_shouldShowEmptyState_onlyBeforeFirstAlert() {
        XCTAssertTrue(PopoverContentRules.shouldShowEmptyState(queue: [], everHadAlerts: false))
        XCTAssertFalse(PopoverContentRules.shouldShowEmptyState(queue: [], everHadAlerts: true))
        XCTAssertFalse(PopoverContentRules.shouldShowEmptyState(
            queue: [mkSession(id: "a1", project: "Alpha")],
            everHadAlerts: false
        ))
    }

    func test_timeSuffix_format_hhmm() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 5; comps.day = 7
        comps.hour = 10; comps.minute = 42; comps.second = 33
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        let s = PopoverContentRules.timeSuffix(for: date)
        // Format only — exact wall-clock value depends on dev TZ.
        let regex = try! NSRegularExpression(pattern: "^[0-9]{2}:[0-9]{2}$")
        let range = NSRange(s.startIndex..., in: s)
        XCTAssertNotNil(regex.firstMatch(in: s, options: [], range: range), "Got: \(s)")
    }

    // MARK: - D2-16 orphan indicator

    func test_orphanIndicator_durationSecNil() {
        XCTAssertTrue(PopoverContentRules.showsOrphanIndicator(
            session: mkSession(id: "x", project: "P", duration: nil)))
        XCTAssertFalse(PopoverContentRules.showsOrphanIndicator(
            session: mkSession(id: "y", project: "P", duration: 42)))
    }

    func test_orderedQueue_placesPinnedFirstThenStoppedAtDescending() {
        let oldPinned = mkSession(id: "old-pinned", project: "P",
                                  stoppedAt: Date(timeIntervalSince1970: 100),
                                  pinned: true)
        let newPinned = mkSession(id: "new-pinned", project: "P",
                                  stoppedAt: Date(timeIntervalSince1970: 300),
                                  pinned: true)
        let newestUnpinned = mkSession(id: "newest-unpinned", project: "P",
                                       stoppedAt: Date(timeIntervalSince1970: 400))
        let olderUnpinned = mkSession(id: "older-unpinned", project: "P",
                                      stoppedAt: Date(timeIntervalSince1970: 200))

        let ordered = PopoverContentRules.orderedByPinnedThenStoppedAt([
            olderUnpinned, oldPinned, newestUnpinned, newPinned
        ])

        XCTAssertEqual(ordered.map(\.sessionID), [
            "new-pinned", "old-pinned", "newest-unpinned", "older-unpinned"
        ])
    }

    // MARK: - WO-010 aging threshold

    func test_isAged_usesStrictSixtyMinuteThreshold() {
        let now = Date(timeIntervalSince1970: 3_600)

        XCTAssertFalse(PopoverContentRules.isAged(
            session: mkSession(id: "now", project: "P", stoppedAt: now),
            now: now
        ))
        XCTAssertFalse(PopoverContentRules.isAged(
            session: mkSession(id: "fifty-nine-minutes", project: "P", stoppedAt: now.addingTimeInterval(-59 * 60)),
            now: now
        ))
        XCTAssertFalse(PopoverContentRules.isAged(
            session: mkSession(id: "exactly-sixty-minutes", project: "P", stoppedAt: now.addingTimeInterval(-60 * 60)),
            now: now
        ))
        XCTAssertTrue(PopoverContentRules.isAged(
            session: mkSession(id: "sixty-minutes-one-second", project: "P", stoppedAt: now.addingTimeInterval(-(60 * 60 + 1))),
            now: now
        ))
    }

    // MARK: - Just-arrived ripple

    func test_isJustArrived_usesThreeSecondWindow() {
        let now = Date(timeIntervalSince1970: 10)

        XCTAssertTrue(PopoverContentRules.isJustArrived(
            session: mkSession(id: "now", project: "P", stoppedAt: now),
            now: now
        ))
        XCTAssertTrue(PopoverContentRules.isJustArrived(
            session: mkSession(id: "three-seconds", project: "P", stoppedAt: now.addingTimeInterval(-3)),
            now: now
        ))
        XCTAssertFalse(PopoverContentRules.isJustArrived(
            session: mkSession(id: "old", project: "P", stoppedAt: now.addingTimeInterval(-3.1)),
            now: now
        ))
        XCTAssertFalse(PopoverContentRules.isJustArrived(
            session: mkSession(id: "future", project: "P", stoppedAt: now.addingTimeInterval(1)),
            now: now
        ))
    }

    // MARK: - WO-009 empty state + settings gear contract (source-level audit)

    func test_popoverContentView_rendersEmptyStateWhenQueueIsEmpty() {
        let src = readPopoverContentViewSource()

        XCTAssertTrue(src.contains("var everHadAlerts: Bool = false"))
        XCTAssertTrue(src.contains("PopoverContentRules.shouldShowEmptyState(queue: queue, everHadAlerts: everHadAlerts)"))
        XCTAssertTrue(src.contains("EmptyStateView()"))
    }

    func test_widgetPopoverController_passesEverHadAlertsStateToContent() {
        let src = readWidgetPopoverControllerSource()

        XCTAssertTrue(src.contains("everHadAlerts: SettingsStore.shared.everHadAlerts"))
    }

    func test_popoverContentView_alwaysRendersHeaderWithSettingsGear() {
        let src = readPopoverContentViewSource()

        XCTAssertTrue(src.contains("var onOpenSettings: () -> Void = {}"))
        XCTAssertTrue(src.contains(#"Image(systemName: "gearshape")"#))
        XCTAssertTrue(src.contains(#".accessibilityLabel("Open Settings")"#))
    }

    func test_popoverContentView_usesNativePopoverMaterialBackground() {
        let src = readPopoverContentViewSource()

        XCTAssertTrue(src.contains("private struct PopoverMaterialBackground: NSViewRepresentable"))
        XCTAssertTrue(src.contains("NSVisualEffectView"))
        XCTAssertTrue(src.contains("view.material = .popover"))
        XCTAssertTrue(src.contains("view.blendingMode = .behindWindow"))
        XCTAssertTrue(src.contains("view.state = .active"))
        XCTAssertTrue(src.contains(".background(PopoverMaterialBackground())"))
        XCTAssertFalse(src.contains(".background(.thinMaterial)"))
    }

    func test_widgetPopoverController_sizingUsesPopoverGeometryTokens() {
        let src = readWidgetPopoverControllerSource()

        XCTAssertTrue(src.contains("PopoverContentRules.displayRowCount(queue, expandedProjects: expandedProjects)"))
        XCTAssertTrue(src.contains("let rowsClamped = min(rows, GeometryTokens.popoverMaxVisibleRows)"))
        XCTAssertTrue(src.contains("GeometryTokens.rowMinHeight * CGFloat(rowsClamped)"))
        XCTAssertTrue(src.contains("let chromeHeight: CGFloat = 32"))
        XCTAssertTrue(src.contains("NSSize(width: GeometryTokens.popoverWidth, height: bodyHeight + chromeHeight)"))
    }

    func test_widgetPopoverController_wiresProjectGroupExpansion() {
        let src = readWidgetPopoverControllerSource()

        XCTAssertTrue(src.contains("private var expandedProjects: Set<String> = []"))
        XCTAssertTrue(src.contains("expandedProjects: expandedProjects"))
        XCTAssertTrue(src.contains("onToggleGroup: {"))
        XCTAssertTrue(src.contains("private func onToggleGroup(projectName: String)"))
    }

    func test_widgetPopoverController_blocksCollapsingGroupWithPendingChildRows() {
        let src = readWidgetPopoverControllerSource()

        XCTAssertTrue(src.contains("PopoverContentRules.canCollapseProjectGroup("))
        XCTAssertTrue(src.contains("rowStates: rowStates"))
    }

    func test_widgetPopoverController_wiresOpenSettingsCallback() {
        let src = readWidgetPopoverControllerSource()

        XCTAssertTrue(src.contains("onOpenSettings: {"))
        XCTAssertTrue(src.contains("NSApp.activate(ignoringOtherApps: true)"))
        XCTAssertTrue(src.contains(#"NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)"#))
    }

    // MARK: - helpers
    // Phase 3 / 03-06: removed `test_isUnavailable_membershipCheck`,
    // `test_isUnavailable_emptySet_neverUnavailable`, and
    // `test_unavailableLabelText_minimalEnglishCopy_locked` — the underlying
    // PopoverContentRules.isUnavailable / unavailableLabelText symbols were
    // Phase 2 placeholders superseded by the RowState `.missing` flow (D3-11/12).

    private func mkSession(id: String,
                           project: String,
                           duration: Int? = 31,
                           stoppedAt: Date = Date(),
                           pinned: Bool = false) -> CompletedSession {
        CompletedSession(
            sessionID: id,
            projectName: project,
            stoppedAt: stoppedAt,
            durationSec: duration,
            itermSessionID: nil,
            tty: nil,
            cwd: nil,
            pinned: pinned
        )
    }

    private func readPopoverContentViewSource(_ thisFile: StaticString = #filePath) -> String {
        let here = URL(fileURLWithPath: "\(thisFile)")
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/PopoverContentView.swift")
        guard let data = try? String(contentsOf: target, encoding: .utf8) else {
            XCTFail("Could not read App/PopoverContentView.swift at \(target.path)")
            return ""
        }
        return data
    }

    private func readWidgetPopoverControllerSource(_ thisFile: StaticString = #filePath) -> String {
        let here = URL(fileURLWithPath: "\(thisFile)")
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/WidgetPopoverController.swift")
        guard let data = try? String(contentsOf: target, encoding: .utf8) else {
            XCTFail("Could not read App/WidgetPopoverController.swift at \(target.path)")
            return ""
        }
        return data
    }
}
