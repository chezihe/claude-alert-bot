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
final class WidgetPopoverController: NSObject, WidgetHoverDelegate, NSPopoverDelegate {
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
            onRowClick: { [weak self] alertID in self?.onRowClick(alertID: alertID) },
            onClearAll: { [weak self] in self?.onClearAll() },
            onTogglePin: { [weak self] alertID in self?.onTogglePin(alertID: alertID) },
            onToggleMute: { [weak self] projectName in self?.onToggleMute(projectName: projectName) },
            isProjectMuted: { projectName in
                SettingsStore.shared.isMuted(project: projectName, now: Date())
            },
            rowStates: rowStates,
            onRowMissingComplete: { [weak self] alertID in
                guard let self else { return }
                Task { await SessionRegistry.shared.clearOne(alertID: alertID) }
                self.rowStates.removeValue(forKey: alertID)
                self.reloadPopoverContent()
            },
            onPopoverHoverChange: { [weak self] hovering in self?.onPopoverHover(hovering) },
            onOpenSettings: {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
            expandedProjects: expandedProjects,
            widgetCorner: SettingsStore.shared.widgetCorner,
            onToggleGroup: { [weak self] projectName in
                self?.onToggleGroup(projectName: projectName)
            },
            everHadAlerts: SettingsStore.shared.everHadAlerts
        )
        let pop: NSPopover
        if let existing = popover {
            pop = existing
        } else {
            pop = NSPopover()
            pop.behavior = .transient
            pop.delegate = self
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
        applyHostCornerRadius(pop)
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
            onRowClick: { [weak self] alertID in self?.onRowClick(alertID: alertID) },
            onClearAll: { [weak self] in self?.onClearAll() },
            onTogglePin: { [weak self] alertID in self?.onTogglePin(alertID: alertID) },
            onToggleMute: { [weak self] projectName in self?.onToggleMute(projectName: projectName) },
            isProjectMuted: { projectName in
                SettingsStore.shared.isMuted(project: projectName, now: Date())
            },
            rowStates: rowStates,
            onRowMissingComplete: { [weak self] alertID in
                guard let self else { return }
                Task { await SessionRegistry.shared.clearOne(alertID: alertID) }
                self.rowStates.removeValue(forKey: alertID)
                self.reloadPopoverContent()
            },
            onPopoverHoverChange: { [weak self] hovering in self?.onPopoverHover(hovering) },
            onOpenSettings: {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            },
            expandedProjects: expandedProjects,
            widgetCorner: SettingsStore.shared.widgetCorner,
            onToggleGroup: { [weak self] projectName in
                self?.onToggleGroup(projectName: projectName)
            },
            everHadAlerts: SettingsStore.shared.everHadAlerts
        )
        // Phase 3 03-09 fix — same pattern as showPopover. Update rootView in place
        // so SwiftUI sees a diff (rowStates change) instead of a new tree, preserving
        // PopoverRowView @State and letting `.onChange(of: state)` fire SC#2 도리도리.
        if let host = pop.contentViewController as? NSHostingController<PopoverContentView> {
            host.rootView = content
        } else {
            pop.contentViewController = NSHostingController(rootView: content)
        }
        applyHostCornerRadius(pop)
        resizePopover(pop, queue: queue)
    }

    /// Apply the panel corner radius directly to the hosting view's layer so
    /// SwiftUI row backgrounds (especially hover fills) are clipped flush with
    /// the NSPopover frame's rounded edges instead of bleeding into the panel's
    /// curved corner gutter. NSPopover's frame view is drawn by AppKit and its
    /// internal radius cannot be queried; clipping the hosting view to the same
    /// radius the SPEC documents (14pt) keeps the SwiftUI content aligned with
    /// the visible panel edge across macOS 14+ revisions.
    /// NSPopover frame radius — macOS 14–26 measure ≈ 12pt around the panel
    /// edge (the SPEC's 14pt is conceptual; AppKit overrides it). Matching this
    /// value keeps SwiftUI row backgrounds flush with the visible panel corner.
    private static let nsPopoverFrameCornerRadius: CGFloat = 12

    private func applyHostCornerRadius(_ pop: NSPopover) {
        guard let view = pop.contentViewController?.view else { return }
        view.wantsLayer = true
        view.layer?.cornerRadius = Self.nsPopoverFrameCornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        // The SwiftUI .background(HideScrollerIntrospector()) probe sometimes
        // attaches outside the NSScrollView subtree, so its enclosingScrollView
        // is nil. Walk the actual AppKit view tree the popover hosts and force
        // every NSScrollView's drawsBackground off — that is what was painting
        // the faint blue strips above/below the row. Defer one runloop tick so
        // NSHostingController has materialised the SwiftUI content into AppKit.
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            Self.flattenScrollViews(in: view)
        }
    }

    // MARK: - NSPopoverDelegate

    nonisolated func popoverDidShow(_ notification: Notification) {
        // NSScrollView is materialised lazily after `show(relativeTo:...)` returns,
        // so the async tick scheduled inside applyHostCornerRadius can fire too early
        // (introspector finds no NSScrollView in the subtree) — leaving the panel
        // with default `drawsBackground=true` and the faint blue strips visible.
        // popoverDidShow is dispatched after the hosted view tree is on-screen and
        // its NSScrollView children exist; repeat the sweep here as a guaranteed
        // second pass.
        Task { @MainActor in
            guard let pop = notification.object as? NSPopover,
                  let view = pop.contentViewController?.view else { return }
            Self.flattenScrollViews(in: view)
        }
    }

    private static func flattenScrollViews(in view: NSView) {
        if let scrollView = view as? NSScrollView {
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.autohidesScrollers = true
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.borderType = .noBorder
            scrollView.contentView.drawsBackground = false
            scrollView.wantsLayer = true
            scrollView.layer?.backgroundColor = NSColor.clear.cgColor
            scrollView.contentView.wantsLayer = true
            scrollView.contentView.layer?.backgroundColor = NSColor.clear.cgColor
        }
        for subview in view.subviews {
            flattenScrollViews(in: subview)
        }
    }

    private func resizePopover(_ pop: NSPopover, queue: [CompletedSession]) {
        let height = PopoverContentRules.popoverHeight(
            queue: queue,
            expandedProjects: expandedProjects,
            everHadAlerts: SettingsStore.shared.everHadAlerts
        )
        pop.contentSize = NSSize(width: GeometryTokens.popoverWidth, height: height)
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

    private func onRowClick(alertID: String) {
        // Find the session for this click; if it disappeared (clearAll race), do nothing.
        guard let session = widgetController?.queueSnapshot.first(where: { $0.id == alertID }) else {
            log.notice("[jump-missed alert=\(alertID, privacy: .public)] (no longer in queue)")
            return
        }
        // D3-11 + JUMP-05: short-circuit if already mid-jump for this row (defensive — row also self-debounces).
        if let s = rowStates[alertID], s != .normal { return }

        guard session.available else {
            rowStates.removeValue(forKey: alertID)
            Task { [weak self] in
                await SessionRegistry.shared.clearOne(alertID: alertID)
                await MainActor.run { self?.reloadPopoverContent() }
            }
            return
        }

        rowStates[alertID] = .jumping
        reloadPopoverContent()

        Task { [weak self] in
            guard let self else { return }
            let result = await self.jumper.jump(to: session)
            await MainActor.run {
                // ITerm2Jumper already emitted the [jump*] OSLog line. WPC's job is state + dismiss.
                switch result {
                case .ok:
                    self.rowStates.removeValue(forKey: alertID)
                    Task { await SessionRegistry.shared.clearOne(alertID: alertID) }
                    self.dismissPopover()
                case .missing:
                    self.rowStates.removeValue(forKey: alertID)
                    Task { [weak self] in
                        await SessionRegistry.shared.markUnavailable(alertID: alertID)
                        await MainActor.run { self?.reloadPopoverContent() }
                    }
                case .iTermNotRunning, .timeout, .otherError:
                    self.rowStates[alertID] = .missing
                    self.reloadPopoverContent()
                    // Row's missing-animation completion will fire onRowMissingComplete → SessionRegistry.clearOne.
                case .permissionDenied:
                    self.rowStates[alertID] = .missing
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

    private func onTogglePin(alertID: String) {
        Task { [weak self] in
            await SessionRegistry.shared.togglePin(alertID: alertID)
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
