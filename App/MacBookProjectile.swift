// App/MacBookProjectile.swift — Rage idle MacBook throw.
// Source of truth: HTML prototype `Claude Alert Bot - Prototype v2.html`
//   @keyframes mb-fly   (lines 679–685) — 1.05s flight, translate (-300, +240), rotate -900°
//   @keyframes mb-impact (lines 695–699) — 600ms scale-rotate fade at landing point
//
// Implementation: a transient borderless NSPanel hosting an SF Symbol or emoji glyph
// is briefly raised, animated via CoreAnimation, then torn down. No desktop "shake"
// (HTML uses a fake desktop element; macOS has no equivalent surface to shake).
import AppKit
import Foundation

@MainActor
final class MacBookProjectileLauncher {
    static let shared = MacBookProjectileLauncher()
    private init() {}

    /// Spawn one projectile from the active widget panel's centre. Picks a random
    /// horizontal direction so consecutive throws fan out instead of stacking.
    func launchFromWidget() {
        guard let widget = NSApp.windows.first(where: { $0 is FloatingWidgetPanel && $0.isVisible }) else { return }
        let origin = NSPoint(x: widget.frame.midX, y: widget.frame.midY)

        let direction: CGFloat = Bool.random() ? -1 : 1
        let translateX: CGFloat = 300 * direction
        let translateY: CGFloat = 240    // screen-coords: NSWindow origin grows up, so +240 moves up. HTML uses CSS-pixels-down; we flip.

        let projectile = ProjectilePanel(originPoint: origin)
        projectile.orderFrontRegardless()
        projectile.fly(translateX: translateX, translateY: -translateY) { [weak projectile] landingPoint in
            projectile?.orderOut(nil)
            let impact = ImpactPanel(centerPoint: landingPoint)
            impact.orderFrontRegardless()
            impact.burst { [weak impact] in
                impact?.orderOut(nil)
            }
        }
    }
}

/// 32×22pt MacBook glyph. Uses `laptopcomputer` SF Symbol with a hint of drop shadow,
/// matching HTML's `.macbook-projectile` filter (drop-shadow(0 4px 6px rgba(0,0,0,0.35))).
private final class ProjectilePanel: NSPanel {
    init(originPoint: NSPoint) {
        let size = NSSize(width: 32, height: 22)
        let rect = NSRect(x: originPoint.x - size.width / 2,
                          y: originPoint.y - size.height / 2,
                          width: size.width,
                          height: size.height)
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

        let glyphView = NSImageView(frame: NSRect(origin: .zero, size: size))
        glyphView.image = NSImage(systemSymbolName: "laptopcomputer", accessibilityDescription: nil)
        glyphView.contentTintColor = .secondaryLabelColor
        glyphView.imageScaling = .scaleProportionallyUpOrDown
        glyphView.wantsLayer = true
        glyphView.layer?.shadowColor = NSColor.black.cgColor
        glyphView.layer?.shadowOpacity = 0.35
        glyphView.layer?.shadowRadius = 6
        glyphView.layer?.shadowOffset = CGSize(width: 0, height: -4)
        self.contentView = glyphView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// HTML @keyframes mb-fly (Prototype v2 lines 679–685). 1.05s cubic-bezier flight
    /// that ends at (origin + translate). Rotation totals -900° (2.5 full spins).
    func fly(translateX: CGFloat, translateY: CGFloat, completion: @escaping (NSPoint) -> Void) {
        let start = self.frame.origin
        let landing = NSPoint(x: start.x + translateX, y: start.y + translateY)
        let duration: TimeInterval = 1.05

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = duration
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.04, 0.8, 1.0)
            self.animator().setFrameOrigin(landing)

            if let layer = self.contentView?.layer {
                let spin = CABasicAnimation(keyPath: "transform.rotation.z")
                spin.fromValue = 0
                spin.toValue = -900 * CGFloat.pi / 180   // -900° flip in radians
                spin.duration = duration
                spin.timingFunction = CAMediaTimingFunction(controlPoints: 0.32, 0.04, 0.8, 1.0)
                spin.isRemovedOnCompletion = false
                spin.fillMode = .forwards
                layer.add(spin, forKey: "mb-fly-rotate")
            }
        }, completionHandler: {
            let center = NSPoint(x: landing.x + 16, y: landing.y + 11)
            completion(center)
        })
    }
}

/// 70×70pt impact burst. Uses an SF "burst.fill" symbol with HTML's mb-impact keyframes.
private final class ImpactPanel: NSPanel {
    init(centerPoint: NSPoint) {
        let size = NSSize(width: 70, height: 70)
        let rect = NSRect(x: centerPoint.x - size.width / 2,
                          y: centerPoint.y - size.height / 2,
                          width: size.width,
                          height: size.height)
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

        let burst = NSImageView(frame: NSRect(origin: .zero, size: size))
        burst.image = NSImage(systemSymbolName: "burst.fill", accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        burst.contentTintColor = NSColor.systemRed
        burst.imageScaling = .scaleProportionallyUpOrDown
        burst.wantsLayer = true
        burst.layer?.opacity = 0
        self.contentView = burst
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// HTML @keyframes mb-impact (Prototype v2 lines 695–699). 600ms ease into
    /// scale 1.2 + rotate 15°, then continues to scale 1.8 + rotate 25° fade.
    func burst(completion: @escaping () -> Void) {
        let duration: TimeInterval = 0.6
        guard let layer = self.contentView?.layer else { completion(); return }

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
