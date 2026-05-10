// App/FloatingWidgetWindowController.swift — Phase 2 WIDG controller; conforms to WidgetControllerProtocol.
// PATTERNS.md §FloatingWidgetWindowController: AppKit bridge with main.swift LSUIElement preserved.
// RESEARCH Pattern 8 + Pattern 9 — NSHostingView + NSTrackingArea + corner/offset positioning.
// UI-SPEC §"Floating Widget" — 200ms ease-in-out fade + 4pt slide animations; reduced-motion skips animations.
// LSUIElement invariant: NEVER call activate(ignoringOtherApps:) on NSApp (anti-pattern from RESEARCH).
// The literal symbol is intentionally absent here so a grep regression guard stays clean.
// 02-01-SPIKE-RESULT.md verdict: Pattern 8 — popover lives with controller in 02-08; this plan ships
// the panel + icon view + HoverDelegate stub only.
import AppKit
import SwiftUI
import Combine
import os

@MainActor protocol WidgetHoverDelegate: AnyObject {
    func widgetMouseEntered()
    func widgetMouseExited()
}

@MainActor
final class FloatingWidgetWindowController: NSWindowController, WidgetControllerProtocol {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "widget")
    private let panel: FloatingWidgetPanel
    private var hostingView: NSHostingView<WidgetIconView>?
    private var trackingArea: NSTrackingArea?
    private var settingsCancellable: AnyCancellable?
    private var accessibilityCancellable: AnyCancellable?
    private var currentQueue: [CompletedSession] = []
    private var currentPendingCount: Int = 0
    private var currentAlertPulseID: Int = 0
    weak var hoverDelegate: WidgetHoverDelegate?

    init() {
        let store = SettingsStore.shared
        let initialSize = GeometryTokens.widgetDrawableSize(
            idleAnimation: store.idleAnimation,
            quietHoursEnabled: store.quietHoursEnabled,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )
        let initialFrame = NSRect(origin: .zero, size: initialSize)
        let p = FloatingWidgetPanel(contentRect: initialFrame)
        self.panel = p
        super.init(window: p)
        // Initial host view
        let hv = NSHostingView(rootView: WidgetIconView(
            pendingCount: 0,
            idleAnimation: SettingsStore.shared.idleAnimation,
            alertPulseID: currentAlertPulseID,
            quietHoursEnabled: SettingsStore.shared.quietHoursEnabled
        ))
        hv.frame = initialFrame
        p.contentView = hv
        self.hostingView = hv
        installTrackingArea(on: hv)
        settingsCancellable = SettingsStore.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateRootView(pendingCount: self.currentPendingCount)
                self.repositionIfVisible()
            }
        }
        accessibilityCancellable = NotificationCenter.default
            .publisher(for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.updateRootView(pendingCount: self.currentPendingCount)
                    self.repositionIfVisible()
                }
            }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - WidgetControllerProtocol

    func showWidget(pendingCount: Int, latest: CompletedSession?) {
        currentPendingCount = pendingCount
        if latest != nil && !SettingsStore.shared.quietHoursEnabled {
            currentAlertPulseID += 1
        }
        updateRootView(pendingCount: pendingCount)
        reposition()
        if !panel.isVisible {
            applyEnterAnimation()
            panel.orderFront(nil)
        }
        log.notice("showWidget count=\(pendingCount, privacy: .public)")
    }

    func hideWidget() {
        if panel.isVisible {
            applyExitAnimation { [weak self] in
                self?.panel.orderOut(nil)
            }
        }
        log.notice("hideWidget")
    }

    func updatePendingCount(_ n: Int, latest: CompletedSession?) {
        currentPendingCount = n
        updateRootView(pendingCount: n)
        // No reposition unless settings changed — caller (02-06) decides via showWidget vs updatePendingCount.
    }

    func setQueue(_ queue: [CompletedSession]) {
        self.currentQueue = queue
        // Popover (02-08) consumes via queueSnapshot or its own queue source — Wave 6 wires.
    }

    /// Read-only snapshot of the latest queue passed to setQueue. Consumed by 02-08 popover.
    var queueSnapshot: [CompletedSession] { currentQueue }

    // MARK: - private

    private func updateRootView(pendingCount: Int) {
        let store = SettingsStore.shared
        let size = GeometryTokens.widgetDrawableSize(
            idleAnimation: store.idleAnimation,
            quietHoursEnabled: store.quietHoursEnabled,
            reduceMotion: reducedMotion
        )
        resizeContent(to: size)
        hostingView?.rootView = WidgetIconView(
            pendingCount: pendingCount,
            idleAnimation: SettingsStore.shared.idleAnimation,
            alertPulseID: currentAlertPulseID,
            quietHoursEnabled: SettingsStore.shared.quietHoursEnabled
        )
    }

    private func resizeContent(to size: CGSize) {
        guard panel.frame.size != size else { return }
        var frame = panel.frame
        frame.size = size
        panel.setFrame(frame, display: true)
        hostingView?.frame = NSRect(origin: .zero, size: size)
    }

    private func repositionIfVisible() {
        guard panel.isVisible else { return }
        reposition()
    }

    private func reposition() {
        guard let screen = NSScreen.main else { return }
        let store = SettingsStore.shared
        let origin = WidgetPositioning.origin(
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screen.safeAreaInsets,
            corner: store.widgetCorner,
            offsetX: store.offsetX,
            offsetY: store.offsetY,
            panelSize: panel.frame.size
        )
        panel.setFrameOrigin(origin)
    }

    private func installTrackingArea(on view: NSView) {
        if let ta = trackingArea { view.removeTrackingArea(ta) }
        let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        let ta = NSTrackingArea(rect: .zero, options: opts, owner: self, userInfo: nil)
        view.addTrackingArea(ta)
        self.trackingArea = ta
    }

    override func mouseEntered(with event: NSEvent) {
        hoverDelegate?.widgetMouseEntered()
    }
    override func mouseExited(with event: NSEvent) {
        hoverDelegate?.widgetMouseExited()
    }

    // MARK: - animation (UI-SPEC §"Layout & Dimensions")

    private var reducedMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func applyEnterAnimation() {
        guard !reducedMotion else { panel.alphaValue = 1.0; return }
        panel.alphaValue = 0.0
        var origin = panel.frame.origin
        origin.y += 4         // start 4pt above target
        panel.setFrameOrigin(origin)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 1.0
            var to = panel.frame.origin
            to.y -= 4
            panel.animator().setFrameOrigin(to)
        }
    }

    private func applyExitAnimation(completion: @escaping () -> Void) {
        guard !reducedMotion else { panel.alphaValue = 0.0; completion(); return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.20
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = 0.0
            var to = panel.frame.origin
            to.y += 4
            panel.animator().setFrameOrigin(to)
        }, completionHandler: completion)
    }
}
