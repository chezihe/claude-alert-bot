// App/MacBookProjectile.swift — Rage idle MacBook throw.
// Source of truth: HTML prototype `Claude Alert Bot - Prototype v2.html`
//   @keyframes mb-fly   (lines 679–685) — 1.05s flight, translate (-300, +240), rotate -900°
//
// Implementation: a transient borderless NSPanel hosting a small vector MacBook glyph
// is briefly raised, animated along the prototype throw arc, then torn down.
import AppKit
import Foundation

@MainActor
final class MacBookProjectileLauncher {
    static let shared = MacBookProjectileLauncher()
    private init() {}

    /// Spawn one projectile from the active widget panel's centre.
    func launchFromWidget() {
        guard let widget = NSApp.windows.first(where: { $0 is FloatingWidgetPanel && $0.isVisible }) else { return }
        let origin = NSPoint(x: widget.frame.midX, y: widget.frame.midY)
        let translation = Self.throwAwayFromWidget(widget)

        let projectile = ProjectilePanel(originPoint: origin)
        projectile.orderFrontRegardless()
        projectile.fly(translateX: translation.width, translateY: translation.height) { [weak projectile] _ in
            projectile?.orderOut(nil)
        }
    }

    private static func throwAwayFromWidget(_ widget: NSWindow) -> CGSize {
        let screenFrame = widget.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? widget.frame
        let goingLeft = widget.frame.midX >= screenFrame.midX
        let goingDown = widget.frame.midY >= screenFrame.midY

        return CGSize(width: (goingLeft ? -1 : 1) * screenFrame.width * 0.16,
                      height: (goingDown ? -1 : 1) * screenFrame.height * 0.14)
    }
}

/// 32×22pt MacBook glyph. Draws the HTML prototype laptop shape with a hint of drop shadow,
/// matching HTML's `.macbook-projectile` filter (drop-shadow(0 4px 6px rgba(0,0,0,0.35))).
private final class ProjectilePanel: NSPanel {
    private struct FlightKeyframe {
        let progress: CGFloat
        let xFactor: CGFloat
        let yFactor: CGFloat
        let lift: CGFloat
        let rotationDegrees: CGFloat
        let opacity: CGFloat
    }

    private struct FlightSample {
        let x: CGFloat
        let y: CGFloat
        let rotationRadians: CGFloat
        let opacity: CGFloat
    }

    private static let flightDuration: TimeInterval = 1.05
    private static let flightKeyframes: [FlightKeyframe] = [
        FlightKeyframe(progress: 0.00, xFactor: 0.00, yFactor: 0.00, lift: 0,  rotationDegrees: 0,    opacity: 0),
        FlightKeyframe(progress: 0.08, xFactor: 0.04, yFactor: 0.00, lift: 16, rotationDegrees: -30,  opacity: 1),
        FlightKeyframe(progress: 0.35, xFactor: 0.40, yFactor: 0.15, lift: 36, rotationDegrees: -360, opacity: 1),
        FlightKeyframe(progress: 0.70, xFactor: 0.78, yFactor: 0.55, lift: 12, rotationDegrees: -680, opacity: 1),
        FlightKeyframe(progress: 1.00, xFactor: 1.00, yFactor: 1.00, lift: 0,  rotationDegrees: -900, opacity: 1)
    ]

    private var flightTimer: Timer?

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

        self.contentView = MacBookGlyphView(frame: NSRect(origin: .zero, size: size))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// HTML @keyframes mb-fly (Prototype v2 lines 679–685). 1.05s cubic-bezier flight
    /// that ends at (origin + translate). Rotation totals -900° (2.5 full spins).
    func fly(translateX: CGFloat, translateY: CGFloat, completion: @escaping (NSPoint) -> Void) {
        let start = self.frame.origin
        let startedAt = CACurrentMediaTime()

        flightTimer?.invalidate()
        alphaValue = 0
        contentView?.layer?.transform = CATransform3DIdentity

        let timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let elapsed = CACurrentMediaTime() - startedAt
            let progress = min(CGFloat(elapsed / Self.flightDuration), 1)
            let sample = Self.flightSample(progress: progress, translateX: translateX, translateY: translateY)
            let origin = NSPoint(x: start.x + sample.x, y: start.y + sample.y)

            self.setFrameOrigin(origin)
            self.alphaValue = sample.opacity
            self.contentView?.layer?.transform = CATransform3DMakeRotation(sample.rotationRadians, 0, 0, 1)

            if progress >= 1 {
                timer.invalidate()
                self.flightTimer = nil
                completion(NSPoint(x: origin.x + 16, y: origin.y + 11))
            }
        }
        flightTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func flightSample(progress: CGFloat, translateX: CGFloat, translateY: CGFloat) -> FlightSample {
        let boundedProgress = min(max(progress, 0), 1)
        let frames = flightKeyframes

        guard let nextIndex = frames.firstIndex(where: { $0.progress >= boundedProgress }) else {
            return sample(from: frames[frames.count - 1], translateX: translateX, translateY: translateY)
        }
        guard nextIndex > 0 else {
            return sample(from: frames[0], translateX: translateX, translateY: translateY)
        }

        let previous = frames[nextIndex - 1]
        let next = frames[nextIndex]
        let span = next.progress - previous.progress
        let local = span > 0 ? (boundedProgress - previous.progress) / span : 0

        return FlightSample(
            x: lerp(previous.xFactor, next.xFactor, local) * translateX,
            y: lerp(previous.yFactor, next.yFactor, local) * translateY + lerp(previous.lift, next.lift, local),
            rotationRadians: lerp(previous.rotationDegrees, next.rotationDegrees, local) * CGFloat.pi / 180,
            opacity: lerp(previous.opacity, next.opacity, local)
        )
    }

    private static func sample(from frame: FlightKeyframe, translateX: CGFloat, translateY: CGFloat) -> FlightSample {
        FlightSample(x: frame.xFactor * translateX,
                     y: frame.yFactor * translateY + frame.lift,
                     rotationRadians: frame.rotationDegrees * CGFloat.pi / 180,
                     opacity: frame.opacity)
    }

    private static func lerp(_ start: CGFloat, _ end: CGFloat, _ progress: CGFloat) -> CGFloat {
        start + (end - start) * progress
    }
}

private final class MacBookGlyphView: NSView {
    private static let macBookLidColor = NSColor(red: 0xCF/255, green: 0xD2/255, blue: 0xD8/255, alpha: 1)
    private static let macBookScreenColor = NSColor(red: 0x10/255, green: 0x10/255, blue: 0x15/255, alpha: 1)
    private static let macBookAccentColor = NSColor(red: 0xD9/255, green: 0x77/255, blue: 0x57/255, alpha: 0.85)
    private static let macBookBaseColor = NSColor(red: 0xAE/255, green: 0xB2/255, blue: 0xBC/255, alpha: 1)
    private static let macBookStrokeColor = NSColor(red: 0x6E/255, green: 0x72/255, blue: 0x80/255, alpha: 1)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -4)
    }

    required init?(coder: NSCoder) {
        return nil
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        drawRoundedRect(NSRect(x: 3, y: 1.5, width: 26, height: 15.5),
                        radius: 1.4,
                        fill: Self.macBookLidColor,
                        stroke: Self.macBookStrokeColor,
                        lineWidth: 0.6)
        drawRoundedRect(NSRect(x: 4.5, y: 3, width: 23, height: 12.5),
                        radius: 0.4,
                        fill: Self.macBookScreenColor)

        Self.macBookAccentColor.setFill()
        NSBezierPath(ovalIn: NSRect(x: 13.9, y: 7.1, width: 4.2, height: 4.2)).fill()

        drawRoundedRect(NSRect(x: 0.5, y: 16.5, width: 31, height: 3.4),
                        radius: 0.7,
                        fill: Self.macBookBaseColor,
                        stroke: Self.macBookStrokeColor,
                        lineWidth: 0.6)
        drawRoundedRect(NSRect(x: 12, y: 16.4, width: 8, height: 0.8),
                        radius: 0.4,
                        fill: Self.macBookStrokeColor)
    }

    private func drawRoundedRect(_ rect: NSRect,
                                 radius: CGFloat,
                                 fill: NSColor,
                                 stroke: NSColor? = nil,
                                 lineWidth: CGFloat = 0) {
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
        fill.setFill()
        path.fill()

        if let stroke, lineWidth > 0 {
            stroke.setStroke()
            path.lineWidth = lineWidth
            path.stroke()
        }
    }
}
