// App/MacBookProjectile.swift — Rage idle MacBook throw.
// Source of truth: internal motion prototype
//   @keyframes mb-fly   — 1.05s flight, translate (-300, +240), rotate -900°
//   @keyframes mb-impact — 600ms scale-rotate fade at landing point
//
// Implementation: a transient borderless NSPanel hosting an SF Symbol glyph is briefly raised,
// animated via CoreAnimation, then closed. No desktop "shake"
// (HTML uses a fake desktop element; macOS has no equivalent surface to shake).
//
// Transforms run on a standalone CALayer (`GlyphLayerView.glyphLayer`) with a centred
// anchorPoint. An AppKit view's own backing layer keeps anchorPoint (0,0), which would make
// rotation/scale pivot around the glyph's bottom-left corner.
import AppKit
import Foundation

@MainActor
final class MacBookProjectileLauncher {
    static let shared = MacBookProjectileLauncher()
    private init() {}

    /// Panels currently on screen. The launcher is their single owner: a panel is retained
    /// from launch until its animation completes, then closed and released here.
    private var livePanels: [NSPanel] = []

    /// Spawn one projectile from the active widget panel's centre. Picks a random
    /// horizontal direction so consecutive throws fan out instead of stacking.
    func launchFromWidget() {
        guard let widget = NSApp.windows.first(where: { $0 is FloatingWidgetPanel && $0.isVisible }) else { return }
        let origin = NSPoint(x: widget.frame.midX, y: widget.frame.midY)

        let direction: CGFloat = Bool.random() ? -1 : 1
        let translateX: CGFloat = 300 * direction
        let translateY: CGFloat = 240    // screen-coords: NSWindow origin grows up, so +240 moves up. HTML uses CSS-pixels-down; we flip.

        let projectile = ProjectilePanel(originPoint: origin)
        show(projectile)
        projectile.fly(translateX: translateX, translateY: -translateY) { [self] landingPoint in
            dismiss(projectile)
            let impact = ImpactPanel(centerPoint: landingPoint)
            show(impact)
            impact.burst { [self] in
                dismiss(impact)
            }
        }
    }

    private func show(_ panel: NSPanel) {
        livePanels.append(panel)
        panel.orderFrontRegardless()
    }

    private func dismiss(_ panel: NSPanel) {
        panel.orderOut(nil)
        panel.close()
        livePanels.removeAll { $0 === panel }
    }
}

/// Transparent panel content view whose glyph is drawn by a centred-anchor sublayer,
/// so CoreAnimation rotation/scale pivots around the glyph's centre.
private final class GlyphLayerView: NSView {
    let glyphLayer = CALayer()

    init(size: NSSize, symbolNames: [String], tint: NSColor) {
        super.init(frame: NSRect(origin: .zero, size: size))
        wantsLayer = true
        layer?.backgroundColor = .clear
        glyphLayer.bounds = CGRect(origin: .zero, size: size)
        glyphLayer.anchorPoint = CGPoint(x: 0.5, y: 0.5)
        glyphLayer.position = CGPoint(x: size.width / 2, y: size.height / 2)
        glyphLayer.contentsGravity = .resizeAspect
        glyphLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        let symbol = symbolNames.lazy
            .compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            .first
        if let symbol {
            glyphLayer.contents = Self.tinted(symbol, with: tint)
        }
        layer?.addSublayer(glyphLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// CALayer contents ignore `contentTintColor`, so bake the tint into the template symbol.
    private static func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }
}

/// 32×22pt MacBook glyph. Uses `laptopcomputer` SF Symbol with a hint of drop shadow,
/// matching HTML's `.macbook-projectile` filter (drop-shadow(0 4px 6px rgba(0,0,0,0.35))).
private final class ProjectilePanel: NSPanel {
    private let glyphView: GlyphLayerView

    init(originPoint: NSPoint) {
        let size = NSSize(width: 32, height: 22)
        let rect = NSRect(x: originPoint.x - size.width / 2,
                          y: originPoint.y - size.height / 2,
                          width: size.width,
                          height: size.height)
        glyphView = GlyphLayerView(size: size, symbolNames: ["laptopcomputer"], tint: .secondaryLabelColor)
        super.init(contentRect: rect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.isReleasedWhenClosed = false
        self.becomesKeyOnlyIfNeeded = true

        let glyphLayer = glyphView.glyphLayer
        glyphLayer.shadowColor = NSColor.black.cgColor
        glyphLayer.shadowOpacity = 0.35
        glyphLayer.shadowRadius = 6
        glyphLayer.shadowOffset = CGSize(width: 0, height: -4)
        self.contentView = glyphView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Internal prototype @keyframes mb-fly. 1.05s cubic-bezier flight
    /// that ends at (origin + translate). Rotation totals -900° (2.5 full spins).
    func fly(translateX: CGFloat, translateY: CGFloat, completion: @escaping (NSPoint) -> Void) {
        let start = self.frame.origin
        let landing = NSPoint(x: start.x + translateX, y: start.y + translateY)
        let duration: TimeInterval = 1.05
        let glyphLayer = glyphView.glyphLayer

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.04, 0.8, 1.0)
            self.animator().setFrameOrigin(landing)

            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = 0
            spin.toValue = -900 * CGFloat.pi / 180   // -900° flip in radians
            spin.duration = duration
            spin.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.04, 0.8, 1.0)
            spin.isRemovedOnCompletion = false
            spin.fillMode = .forwards
            glyphLayer.add(spin, forKey: "mb-fly-rotate")
        }, completionHandler: {
            let center = NSPoint(x: landing.x + 16, y: landing.y + 11)
            completion(center)
        })
    }
}

/// 70×70pt impact burst. Uses an SF "burst.fill" symbol with the prototype's mb-impact keyframes.
private final class ImpactPanel: NSPanel {
    private let glyphView: GlyphLayerView

    init(centerPoint: NSPoint) {
        let size = NSSize(width: 70, height: 70)
        let rect = NSRect(x: centerPoint.x - size.width / 2,
                          y: centerPoint.y - size.height / 2,
                          width: size.width,
                          height: size.height)
        glyphView = GlyphLayerView(size: size, symbolNames: ["burst.fill", "sparkles"], tint: .systemRed)
        super.init(contentRect: rect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = true
        self.isReleasedWhenClosed = false

        glyphView.glyphLayer.opacity = 0
        self.contentView = glyphView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Internal prototype @keyframes mb-impact. 600ms ease into
    /// scale 1.2 + rotate 15°, then continues to scale 1.8 + rotate 25° fade.
    func burst(completion: @escaping () -> Void) {
        let duration: TimeInterval = 0.6
        let layer = glyphView.glyphLayer

        let scale = CAKeyframeAnimation(keyPath: "transform.scale")
        scale.values = [0.25, 1.2, 1.8]
        scale.keyTimes = [0, 0.25, 1.0]
        scale.duration = duration
        scale.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.7, 0.3, 1.0)
        scale.fillMode = .forwards
        scale.isRemovedOnCompletion = false

        let rotate = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        rotate.values = [0, 15 * CGFloat.pi / 180, 25 * CGFloat.pi / 180]
        rotate.keyTimes = [0, 0.25, 1.0]
        rotate.duration = duration
        rotate.fillMode = .forwards
        rotate.isRemovedOnCompletion = false

        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0.0, 1.0, 0.0]
        opacity.keyTimes = [0, 0.25, 1.0]
        opacity.duration = duration
        opacity.fillMode = .forwards
        opacity.isRemovedOnCompletion = false

        CATransaction.begin()
        CATransaction.setCompletionBlock { completion() }
        layer.add(scale, forKey: "impact-scale")
        layer.add(rotate, forKey: "impact-rotate")
        layer.add(opacity, forKey: "impact-opacity")
        CATransaction.commit()
    }
}
