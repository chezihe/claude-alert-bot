// App/WidgetPopoverController.swift — Phase 2 / Plan 02-08 Task 2 popover surface.
// The prototype panel has no native popover arrow, so this controller presents a borderless
// sibling NSPanel and keeps the SwiftUI content responsible for the panel body.
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

    private var popoverPanel: NSPanel?
    private var popoverHostView: NSHostingView<PopoverContentView>?
    private var globalEventMonitor: Any?
    private var localEventMonitor: Any?

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

    func widgetMouseClicked() {
        entryWorkItem?.cancel(); entryWorkItem = nil
        exitWorkItem?.cancel(); exitWorkItem = nil
        guard let queue = widgetController?.queueSnapshot else { return }
        if queue.count == 1, popoverPanel?.isVisible != true, let session = queue.first {
            onRowClick(alertID: session.id)
            return
        }
        showPopover()
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

    // MARK: - present / dismiss

    private func showPopover() {
        guard let controller = widgetController,
              let widgetPanel = controller.window else { return }
        let queue = controller.queueSnapshot
        if queue.count == 1, popoverPanel?.isVisible != true { return }
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
        let panel = popoverPanel ?? makePopoverPanel()
        popoverPanel = panel
        // Phase 3 03-09 fix — reuse the NSHostingView so SwiftUI sees a rootView
        // update instead of a brand-new view tree. Otherwise PopoverRowView's @State
        // (rotation/collapsed/faded) resets on every reload, and `.onChange(of: state)`
        // never fires for rows that mount with state: .missing — breaking SC#2 도리도리.
        if let host = popoverHostView {
            host.rootView = content
        } else {
            let host = NSHostingView(rootView: content)
            popoverHostView = host
            panel.contentView = host
        }
        if panel.parent == nil {
            widgetPanel.addChildWindow(panel, ordered: .above)
        }
        guard let host = popoverHostView else { return }
        applyHostCornerRadius(host)
        resizePopover(panel, hostView: host, queue: queue)
        panel.orderFront(nil)
        installEventMonitors()
        DispatchQueue.main.async { [weak host] in
            guard let host else { return }
            Self.flattenScrollViews(in: host)
        }
        log.notice("popover shown rows=\(queue.count, privacy: .public)")
    }

    private func dismissPopover() {
        popoverPanel?.orderOut(nil)
        removeEventMonitors()
        log.notice("popover dismissed")
    }

    /// Re-render the popover with the current rowStates dict.
    private func reloadPopoverContent() {
        guard let panel = popoverPanel, panel.isVisible else { return }
        guard let host = popoverHostView else { return }
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
        host.rootView = content
        applyHostCornerRadius(host)
        resizePopover(panel, hostView: host, queue: queue)
    }

    private func makePopoverPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.acceptsMouseMovedEvents = true
        panel.isRestorable = false
        return panel
    }

    /// Apply the panel corner radius directly to the hosting view's layer so
    /// SwiftUI row backgrounds (especially hover fills) are clipped flush with
    /// the panel's rounded edges instead of bleeding into the corner gutter.
    private func applyHostCornerRadius(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = GeometryTokens.popoverCornerRadius
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

    private func resizePopover(_ panel: NSPanel,
                               hostView: NSHostingView<PopoverContentView>,
                               queue: [CompletedSession]) {
        let height = PopoverContentRules.popoverHeight(
            queue: queue,
            expandedProjects: expandedProjects,
            everHadAlerts: SettingsStore.shared.everHadAlerts
        )
        let size = NSSize(width: GeometryTokens.popoverWidth, height: height)
        guard let widgetPanel = widgetController?.window,
              let screen = widgetPanel.screen ?? NSScreen.main else {
            panel.setContentSize(size)
            hostView.frame = NSRect(origin: .zero, size: size)
            return
        }
        let origin = WidgetPopoverPositioning.origin(
            widgetFrame: widgetPanel.frame,
            panelSize: size,
            visibleFrame: screen.visibleFrame,
            corner: SettingsStore.shared.widgetCorner
        )
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        hostView.frame = NSRect(origin: .zero, size: size)
    }

    private func installEventMonitors() {
        guard globalEventMonitor == nil, localEventMonitor == nil else { return }
        let popoverWindowNumber = popoverPanel?.windowNumber
        let widgetWindowNumber = widgetController?.window?.windowNumber
        globalEventMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in self?.dismissPopover() }
        }
        localEventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            if event.type == .keyDown && event.keyCode == 53 {
                Task { @MainActor [weak self] in self?.dismissPopover() }
                return nil
            }
            guard event.type == .leftMouseDown || event.type == .rightMouseDown else { return event }
            let eventWindowNumber = event.window?.windowNumber
            if eventWindowNumber == popoverWindowNumber || eventWindowNumber == widgetWindowNumber {
                return event
            }
            Task { @MainActor [weak self] in self?.dismissPopover() }
            return event
        }
    }

    private func removeEventMonitors() {
        if let monitor = globalEventMonitor {
            NSEvent.removeMonitor(monitor)
            globalEventMonitor = nil
        }
        if let monitor = localEventMonitor {
            NSEvent.removeMonitor(monitor)
            localEventMonitor = nil
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

enum WidgetPopoverPositioning {
    private static let widgetGap: CGFloat = 4

    static func origin(widgetFrame: NSRect,
                       panelSize: NSSize,
                       visibleFrame: NSRect,
                       corner: WidgetCorner) -> NSPoint {
        let x: CGFloat
        switch corner {
        case .topRight, .bottomRight:
            x = widgetFrame.maxX - panelSize.width
        case .topLeft, .bottomLeft:
            x = widgetFrame.minX
        }

        let y: CGFloat
        switch corner {
        case .topRight, .topLeft:
            y = widgetFrame.minY - widgetGap - panelSize.height
        case .bottomRight, .bottomLeft:
            y = widgetFrame.maxY + widgetGap
        }

        return NSPoint(
            x: clamp(x, lower: visibleFrame.minX, upper: visibleFrame.maxX - panelSize.width),
            y: clamp(y, lower: visibleFrame.minY, upper: visibleFrame.maxY - panelSize.height)
        )
    }

    private static func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard upper >= lower else { return lower }
        return min(max(value, lower), upper)
    }
}
