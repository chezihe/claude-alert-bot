// App/FloatingWidgetPanel.swift — Phase 2 WIDG-01, WIDG-02, WIDG-04, WIDG-05.
// RESEARCH Pattern 7 (lines 672-708) — locked NSPanel subclass.
// PITFALLS #1: collectionBehavior 3-flag combination is non-negotiable for Stage Manager + multi-Space.
// UI-SPEC §"Floating Widget" — NSPanel + .hudWindow material + 14pt rounded body
// (NSVisualEffectView in contentView, controlled by WindowController).
import AppKit
import CoreGraphics

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
        // NSPanel.hasShadow draws a window-rect shadow under the *bounding box*, not the glyph
        // silhouette — so on a transparent 50pt panel it reads as a dark square frame behind
        // the icon. The widget is meant to look glued to the screen surface, not floating in
        // a card, so the shadow stays off.
        self.hasShadow = false
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
    private static let topBadgeClearance: CGFloat = 2

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
                           y: f.maxY - panelSize.height - max(oy, safe.top) - topBadgeClearance)
        case .topLeft:
            return NSPoint(x: f.minX + max(ox, safe.left),
                           y: f.maxY - panelSize.height - max(oy, safe.top) - topBadgeClearance)
        case .bottomRight:
            return NSPoint(x: f.maxX - panelSize.width  - max(ox, safe.right),
                           y: f.minY + max(oy, safe.bottom))
        case .bottomLeft:
            return NSPoint(x: f.minX + max(ox, safe.left),
                           y: f.minY + max(oy, safe.bottom))
        }
    }
}

enum WidgetScreenSelection {
    @MainActor
    static func activeScreen(preferMouseLocation: Bool = false) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return NSScreen.main }

        let fallback = NSScreen.main
        let fallbackIndex = fallback.flatMap { fallbackScreen in
            screens.firstIndex { $0.frame == fallbackScreen.frame }
        }
        let frontmostWindow = frontmostWindowBounds(mainScreenFrame: screens[0].frame)
        let index = preferredScreenIndex(
            windowBounds: frontmostWindow,
            mouseLocation: NSEvent.mouseLocation,
            screenFrames: screens.map(\.frame),
            fallbackIndex: fallbackIndex,
            preferMouseLocation: preferMouseLocation
        )

        return index.map { screens[$0] } ?? fallback
    }

    static func preferredScreenIndex(
        windowBounds: NSRect?,
        mouseLocation: NSPoint?,
        screenFrames: [NSRect],
        fallbackIndex: Int?,
        preferMouseLocation: Bool = false
    ) -> Int? {
        if preferMouseLocation,
           let mouseLocation,
           let index = screenFrames.firstIndex(where: { $0.contains(mouseLocation) }) {
            return index
        }

        if let windowBounds,
           let index = screenFrames.indices.max(by: {
               intersectionArea(windowBounds, screenFrames[$0]) < intersectionArea(windowBounds, screenFrames[$1])
           }),
           intersectionArea(windowBounds, screenFrames[index]) > 0 {
            return index
        }

        if let mouseLocation,
           let index = screenFrames.firstIndex(where: { $0.contains(mouseLocation) }) {
            return index
        }

        return fallbackIndex ?? screenFrames.indices.first
    }

    private static func frontmostWindowBounds(mainScreenFrame: NSRect) -> NSRect? {
        guard let frontmostApp = NSWorkspace.shared.frontmostApplication,
              frontmostApp.bundleIdentifier != Bundle.main.bundleIdentifier,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let frontmostPID = Int(frontmostApp.processIdentifier)
        for window in windows {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                  ownerPID == frontmostPID,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  layer == 0,
                  let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary else {
                continue
            }

            var bounds = CGRect.zero
            guard CGRectMakeWithDictionaryRepresentation(boundsDictionary as CFDictionary, &bounds),
                  bounds.width > 0,
                  bounds.height > 0 else {
                continue
            }

            return appKitRect(fromQuartzBounds: bounds, mainScreenFrame: mainScreenFrame)
        }

        return nil
    }

    private static func appKitRect(fromQuartzBounds bounds: CGRect, mainScreenFrame: NSRect) -> NSRect {
        NSRect(
            x: bounds.minX,
            y: mainScreenFrame.maxY - bounds.maxY,
            width: bounds.width,
            height: bounds.height
        )
    }

    private static func intersectionArea(_ lhs: NSRect, _ rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull, !intersection.isEmpty else { return 0 }
        return intersection.width * intersection.height
    }
}
