// App/WidgetPopoverController.swift — Phase 2 / Plan 02-08 Task 2 popover surface.
// Topology per 02-01-SPIKE-RESULT.md verdict: Pattern 8 (NSPopover with .transient behavior).
// Spike on macOS 26.4.1 confirmed NSPopover does NOT pollute Cmd-Tab or steal focus from a
// .nonactivatingPanel parent — A1 risk from RESEARCH §Pitfall #2 empirically disproven.
// Conforms to WidgetHoverDelegate (declared in App/FloatingWidgetWindowController.swift, 02-07).
// Hover-intent timing: 150ms entry delay before show, 250ms exit grace before dismiss
// (UI-SPEC §"Floating Widget" hover row — owned by 02-08 per 02-07 SUMMARY).
// D2-08: row click site emits OSLog `[would-jump session=<uuid>]` verbatim — Phase 3 ITermBridge
// inherits this signature without reformatting.
import AppKit
import SwiftUI
import os

@MainActor
final class WidgetPopoverController: NSObject, WidgetHoverDelegate {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "widget")
    private weak var widgetController: FloatingWidgetWindowController?
    private var entryWorkItem: DispatchWorkItem?
    private var exitWorkItem: DispatchWorkItem?

    // Pattern 8 — NSPopover. (Pattern 8a sibling-NSPanel branch retired by 02-01 spike verdict.)
    private var popover: NSPopover?

    init(widgetController: FloatingWidgetWindowController) {
        self.widgetController = widgetController
        super.init()
    }

    // MARK: - WidgetHoverDelegate

    func widgetMouseEntered() {
        // Re-entering during exit grace cancels the pending dismiss (UI-SPEC).
        exitWorkItem?.cancel(); exitWorkItem = nil
        let intent = DispatchWorkItem { [weak self] in self?.showPopover() }
        entryWorkItem = intent
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(150), execute: intent)
    }

    func widgetMouseExited() {
        // Leaving before the 150ms intent cancels the pending show.
        entryWorkItem?.cancel(); entryWorkItem = nil
        let exit = DispatchWorkItem { [weak self] in self?.dismissPopover() }
        exitWorkItem = exit
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: exit)
    }

    // MARK: - present / dismiss (Pattern 8)

    private func showPopover() {
        guard let controller = widgetController,
              let panel = controller.window,
              let anchor = panel.contentView else { return }
        let queue = controller.queueSnapshot
        let content = PopoverContentView(
            queue: queue,
            onRowClick: { [weak self] sid in self?.onRowClick(sessionID: sid) },
            onClearAll: { [weak self] in self?.onClearAll() }
        )
        let pop: NSPopover
        if let existing = popover {
            pop = existing
        } else {
            pop = NSPopover()
            pop.behavior = .transient
            popover = pop
        }
        pop.contentViewController = NSHostingController(rootView: content)
        // Width fixed at 280pt (UI-SPEC); height grows with row count up to 8 rows
        // plus an extra 32pt strip when the Clear-all chrome is visible.
        let rows = max(1, queue.count)
        let bodyHeight = min(36 * rows, 36 * 8)
        let chromeHeight = PopoverContentRules.shouldShowClearAll(rowCount: queue.count) ? 32 : 0
        pop.contentSize = NSSize(width: 280, height: bodyHeight + chromeHeight)
        pop.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: cornerToEdge())
        log.notice("popover shown rows=\(queue.count, privacy: .public)")
    }

    private func dismissPopover() {
        popover?.performClose(nil)
        log.notice("popover dismissed")
    }

    /// UI-SPEC: popover slides away from the widget's corner.
    /// Top-half corners → popover lives below the widget (.minY).
    /// Bottom-half corners → popover lives above the widget (.maxY).
    private func cornerToEdge() -> NSRectEdge {
        switch SettingsStore.shared.widgetCorner {
        case .topRight, .topLeft: return .minY
        case .bottomRight, .bottomLeft: return .maxY
        }
    }

    // MARK: - actions (D2-08 + D2-07)

    private func onRowClick(sessionID: String) {
        // D2-08 verbatim — Phase 3 ITermBridge inherits the [would-jump session=<uuid>] format.
        log.notice("[would-jump session=\(sessionID, privacy: .public)]")
        Task { await SessionRegistry.shared.clearOne(sessionID: sessionID) }
        dismissPopover()
    }

    private func onClearAll() {
        log.notice("popover Clear all")
        Task { await SessionRegistry.shared.clearAll() }
        dismissPopover()
    }
}
