// App/FloatingWidgetPanel.swift — Phase 2 WIDG-01, WIDG-02, WIDG-04, WIDG-05.
// RESEARCH Pattern 7 (lines 672-708) — locked NSPanel subclass.
// PITFALLS #1: collectionBehavior 3-flag combination is non-negotiable for Stage Manager + multi-Space.
// UI-SPEC §"Floating Widget" — NSPanel + .hudWindow material + 14pt rounded body
// (NSVisualEffectView in contentView, controlled by WindowController).
import AppKit

final class FloatingWidgetPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.becomesKeyOnlyIfNeeded = true       // WIDG-02
        self.hidesOnDeactivate = false           // WIDG-04 — survives app deactivate
        self.isMovableByWindowBackground = false
        self.hasShadow = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.acceptsMouseMovedEvents = true      // for NSTrackingArea hover
        // Phase 3 03-09 fix — opt out of macOS Window Restoration. Default true would
        // let the system silently re-show the panel on relaunch even when the queue is
        // empty (no showWidget call from our code). Visibility is controlled exclusively
        // by NotificationOrchestrator.refreshQueueState; restoration would race that.
        self.isRestorable = false
    }

    // WIDG-02 belt-and-suspenders — `.nonactivatingPanel` already prevents key activation,
    // but explicit overrides catch edge cases (e.g. if a future SwiftUI bridge requests focus).
    override var canBecomeKey: Bool  { false }
    override var canBecomeMain: Bool { false }
}

/// Pure positioning function — extracted for unit testing (PATTERNS.md "no analog" + RESEARCH Pattern 9).
/// No NSScreen dependency in test mode; caller passes visibleFrame + safeAreaInsets.
enum WidgetPositioning {
    /// Compute panel origin given screen frame, safe area insets, corner, offset, and panel size.
    /// Pure function — no side effects. WIDG-06 (4 corners + offset) + WIDG-07 (safe-area clamp).
    static func origin(
        visibleFrame: NSRect,
        safeAreaInsets: NSEdgeInsets,
        corner: WidgetCorner,
        offsetX: Int,
        offsetY: Int,
        panelSize: NSSize
    ) -> NSPoint {
        let f = visibleFrame
        let safe = safeAreaInsets
        let ox = max(CGFloat(offsetX), 0)
        let oy = max(CGFloat(offsetY), 0)
        switch corner {
        case .topRight:
            return NSPoint(x: f.maxX - panelSize.width  - max(ox, safe.right),
                           y: f.maxY - panelSize.height - max(oy, safe.top))
        case .topLeft:
            return NSPoint(x: f.minX + max(ox, safe.left),
                           y: f.maxY - panelSize.height - max(oy, safe.top))
        case .bottomRight:
            return NSPoint(x: f.maxX - panelSize.width  - max(ox, safe.right),
                           y: f.minY + max(oy, safe.bottom))
        case .bottomLeft:
            return NSPoint(x: f.minX + max(ox, safe.left),
                           y: f.minY + max(oy, safe.bottom))
        }
    }
}
