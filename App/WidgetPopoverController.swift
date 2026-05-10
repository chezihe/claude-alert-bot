// App/WidgetPopoverController.swift — Phase 2 / Plan 02-08 Task 2 popover surface.
// Topology per 02-01-SPIKE-RESULT.md verdict: Pattern 8 (NSPopover with .transient behavior).
// Spike on macOS 26.4.1 confirmed NSPopover does NOT pollute Cmd-Tab or steal focus from a
// .nonactivatingPanel parent — A1 risk from RESEARCH §Pitfall #2 empirically disproven.
// Conforms to WidgetHoverDelegate (declared in App/FloatingWidgetWindowController.swift, 02-07).
// Hover-intent timing: 150ms entry delay before show, 250ms exit grace before dismiss
// (UI-SPEC §"Floating Widget" hover row — owned by 02-08 per 02-07 SUMMARY).
// Phase 3 (03-07): D2-08 placeholder superseded. onRowClick dispatches to TerminalJumper
// (D-ADAPTER seam from 03-01) and orchestrates RowState (D3-11) + popover dismiss + clearOne.
// OSLog [jump*] 4-prefix contract (D3-13) is emitted by ITerm2Jumper, not here.
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

    /// Phase 3 D-ADAPTER — TerminalJumper injected via init (default: ITerm2Jumper).
    private let jumper: any TerminalJumper

    /// Phase 3 D3-11 — per-session row state. Mutations trigger popover content reload.
    private var rowStates: [String: RowState] = [:]
    private var expandedProjects: Set<String> = []

    /// Production + tests inject the jumper explicitly. The convenience initializer below
    /// supplies the default `ITerm2Jumper()` — both `WidgetPopoverController` and `ITerm2Jumper`
    /// are `@MainActor`, so the default expression cannot be evaluated in a nonisolated
    /// init parameter context (Swift 6 strict-concurrency rule; mirrors `NotificationOrchestrator`
    /// 02-06 `convenience init(widget:)` pattern).
    init(widgetController: FloatingWidgetWindowController,
         jumper: any TerminalJumper) {
        self.widgetController = widgetController
        self.jumper = jumper
        super.init()
    }

    /// Convenience for production callers — wraps the designated init with `ITerm2Jumper()`.
    convenience init(widgetController: FloatingWidgetWindowController) {
        self.init(widgetController: widgetController, jumper: ITerm2Jumper())
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

    /// Phase 3 03-09 fix — popover surface hover. While hovering=true, cancel the
    /// widget-exit dismiss timer so traveling from the menu-bar icon onto the
    /// popover does not race the 250ms grace and dismiss the popover mid-flight.
    /// On hovering=false, restart a normal exit grace from the popover edge.
    private func onPopoverHover(_ hovering: Bool) {
        if hovering {
            exitWorkItem?.cancel(); exitWorkItem = nil
        } else {
            let exit = DispatchWorkItem { [weak self] in self?.dismissPopover() }
            exitWorkItem = exit
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250), execute: exit)
        }
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
            onClearAll: { [weak self] in self?.onClearAll() },
            onTogglePin: { [weak self] sid in self?.onTogglePin(sessionID: sid) },
            onToggleMute: { [weak self] projectName in self?.onToggleMute(projectName: projectName) },
            isProjectMuted: { projectName in
                SettingsStore.shared.isMuted(project: projectName, now: Date())
            },
            rowStates: rowStates,
            onRowMissingComplete: { [weak self] sid in
                guard let self else { return }
                Task { await SessionRegistry.shared.clearOne(sessionID: sid) }
                self.rowStates.removeValue(forKey: sid)
                self.reloadPopoverContent()
            },
            onPopoverHoverChange: { [weak self] hovering in self?.onPopoverHover(hovering) },
            onOpenSettings: {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
            expandedProjects: expandedProjects,
            onToggleGroup: { [weak self] projectName in
                self?.onToggleGroup(projectName: projectName)
            }
        )
        let pop: NSPopover
        if let existing = popover {
            pop = existing
        } else {
            pop = NSPopover()
            pop.behavior = .transient
            popover = pop
        }
        // Phase 3 03-09 fix — reuse the NSHostingController so SwiftUI sees a rootView
        // update instead of a brand-new view tree. Otherwise PopoverRowView's @State
        // (rotation/collapsed/faded) resets on every reload, and `.onChange(of: state)`
        // never fires for rows that mount with state: .missing — breaking SC#2 도리도리.
        if let host = pop.contentViewController as? NSHostingController<PopoverContentView> {
            host.rootView = content
        } else {
            pop.contentViewController = NSHostingController(rootView: content)
        }
        resizePopover(pop, queue: queue)
        pop.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: cornerToEdge())
        log.notice("popover shown rows=\(queue.count, privacy: .public)")
    }

    private func dismissPopover() {
        popover?.performClose(nil)
        log.notice("popover dismissed")
    }

    /// Re-render the popover with the current rowStates dict.
    /// NSHostingController's contentViewController reassignment is the existing
    /// reload primitive (Phase 2 02-08 line 67).
    private func reloadPopoverContent() {
        guard let pop = popover, pop.isShown else { return }
        guard let controller = widgetController else { return }
        let queue = controller.queueSnapshot
        let content = PopoverContentView(
            queue: queue,
            onRowClick: { [weak self] sid in self?.onRowClick(sessionID: sid) },
            onClearAll: { [weak self] in self?.onClearAll() },
            onTogglePin: { [weak self] sid in self?.onTogglePin(sessionID: sid) },
            onToggleMute: { [weak self] projectName in self?.onToggleMute(projectName: projectName) },
            isProjectMuted: { projectName in
                SettingsStore.shared.isMuted(project: projectName, now: Date())
            },
            rowStates: rowStates,
            onRowMissingComplete: { [weak self] sid in
                guard let self else { return }
                Task { await SessionRegistry.shared.clearOne(sessionID: sid) }
                self.rowStates.removeValue(forKey: sid)
                self.reloadPopoverContent()
            },
            onPopoverHoverChange: { [weak self] hovering in self?.onPopoverHover(hovering) },
            onOpenSettings: {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
            expandedProjects: expandedProjects,
            onToggleGroup: { [weak self] projectName in
                self?.onToggleGroup(projectName: projectName)
            }
        )
        // Phase 3 03-09 fix — same pattern as showPopover. Update rootView in place
        // so SwiftUI sees a diff (rowStates change) instead of a new tree, preserving
        // PopoverRowView @State and letting `.onChange(of: state)` fire SC#2 도리도리.
        if let host = pop.contentViewController as? NSHostingController<PopoverContentView> {
            host.rootView = content
        } else {
            pop.contentViewController = NSHostingController(rootView: content)
        }
        resizePopover(pop, queue: queue)
    }

    private func resizePopover(_ pop: NSPopover, queue: [CompletedSession]) {
        let rows = max(1, PopoverContentRules.displayRowCount(queue, expandedProjects: expandedProjects))
        let rowsClamped = min(rows, GeometryTokens.popoverMaxVisibleRows)
        let bodyHeight: CGFloat = queue.isEmpty
            ? 48  // matches EmptyStateView natural height (text 12pt + .padding(.vertical, 16))
            : GeometryTokens.rowMinHeight * CGFloat(rowsClamped)
        let chromeHeight: CGFloat = 32  // header always visible (gear + optional Clear All)
        pop.contentSize = NSSize(width: GeometryTokens.popoverWidth, height: bodyHeight + chromeHeight)
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
        // Find the session for this click; if it disappeared (clearAll race), do nothing.
        guard let session = widgetController?.queueSnapshot.first(where: { $0.sessionID == sessionID }) else {
            log.notice("[jump-missed session=\(sessionID, privacy: .public)] (no longer in queue)")
            return
        }
        // D3-11 + JUMP-05: short-circuit if already mid-jump for this row (defensive — row also self-debounces).
        if let s = rowStates[sessionID], s != .normal { return }

        rowStates[sessionID] = .jumping
        reloadPopoverContent()

        Task { [weak self] in
            guard let self else { return }
            let result = await self.jumper.jump(to: session)
            await MainActor.run {
                // ITerm2Jumper already emitted the [jump*] OSLog line. WPC's job is state + dismiss.
                switch result {
                case .ok:
                    self.rowStates.removeValue(forKey: sessionID)
                    Task { await SessionRegistry.shared.clearOne(sessionID: sessionID) }
                    self.dismissPopover()
                case .missing:
                    self.rowStates.removeValue(forKey: sessionID)
                    Task { [weak self] in
                        await SessionRegistry.shared.markUnavailable(sessionID: sessionID)
                        await MainActor.run { self?.reloadPopoverContent() }
                    }
                case .iTermNotRunning, .timeout, .otherError:
                    self.rowStates[sessionID] = .missing
                    self.reloadPopoverContent()
                    // Row's missing-animation completion will fire onRowMissingComplete → SessionRegistry.clearOne.
                case .permissionDenied:
                    self.rowStates[sessionID] = .missing
                    self.reloadPopoverContent()
                    PermissionDeepLink.openAutomationPreferences()
                    // Row's missing animation still runs → row clears from queue.
                    // Banner in SettingsView (Phase 2 PermissionBannerView) surfaces via lastKnownPermission update from AppleScriptHelper.
                }
            }
        }
    }

    private func onClearAll() {
        log.notice("popover Clear all")
        Task { await SessionRegistry.shared.clearAll() }
        dismissPopover()
    }

    private func onTogglePin(sessionID: String) {
        Task { [weak self] in
            await SessionRegistry.shared.togglePin(sessionID: sessionID)
            await MainActor.run { self?.reloadPopoverContent() }
        }
    }

    private func onToggleMute(projectName: String) {
        let settings = SettingsStore.shared
        if settings.isMuted(project: projectName, now: Date()) {
            settings.unmute(project: projectName)
        } else {
            settings.mute(project: projectName, now: Date())
        }
        reloadPopoverContent()
    }

    private func onToggleGroup(projectName: String) {
        if expandedProjects.contains(projectName) {
            let queue = widgetController?.queueSnapshot ?? []
            guard PopoverContentRules.canCollapseProjectGroup(
                projectName: projectName,
                queue: queue,
                rowStates: rowStates
            ) else { return }
            expandedProjects.remove(projectName)
        } else {
            expandedProjects.insert(projectName)
        }
        reloadPopoverContent()
    }
}
