// App/RoamIdleMotion.swift — Roam idle: 1.6s counter-clockwise 16×4pt-radius ellipse, linear forever,
// plus a subtle 1.0↔1.04 breathing scale across the lap.
// The phase state lives in this modifier, so unmounting it (idle switch, Quiet Hours,
// Reduce Motion) drops the in-flight `.repeatForever` along with it.
import SwiftUI

struct RoamIdleMotion: ViewModifier {
    @State private var roamPhase: Double = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(1.0 + 0.04 * CGFloat(sin(roamPhase * .pi / 180)), anchor: .center)
            .modifier(RoamOffsetEffect(
                angle: roamPhase,
                radiusX: Double(MotionTokens.roamRadiusX),
                radiusY: Double(MotionTokens.roamRadiusY),
                isActive: true
            ))
            .onAppear {
                // Only mounted while roam is the active idle, so Reduce Motion is already off.
                guard let anim = MotionTokens.roamAnimation(reduceMotion: false) else { return }
                withAnimation(anim) {
                    roamPhase = -360
                }
            }
    }
}

struct RoamOffsetEffect: GeometryEffect {
    var angle: Double
    let radiusX: Double
    let radiusY: Double
    let isActive: Bool

    var animatableData: Double {
        get { angle }
        set { angle = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        guard isActive else { return ProjectionTransform(CGAffineTransform.identity) }
        let radians = angle * Double.pi / 180
        let x = cos(radians) * radiusX
        let y = sin(radians) * radiusY
        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }
}
