// App/WidgetIconView.swift — Phase 2 WIDG-03 (icon + project name location).
// UI-SPEC: 36pt Claude Code glyph, 4pt internal padding (44pt total).
// +N badge: 16pt × 16pt circle, systemRed fill (systemGray in Quiet Hours), white SF Pro Semibold 11pt numeral.
// Anchored top-trailing with -4/-4 overhang per UI-SPEC.
// Bounce: 5pt vertical + 1.04↔0.94 squash, 0.45s easeInOut, autoreverse forever; suppressed when Reduce Motion is on.
// Breathe: 2.4s scale 1.0↔1.06, autoreverse forever; default idle animation for WO-012.
import SwiftUI
import AppKit

struct WidgetIconView: View {
    let pendingCount: Int
    var idleAnimation: IdleAnimation = .default
    var quietHoursEnabled: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounceOffset: CGFloat = 0
    @State private var bounceScale: CGFloat = 1.0
    @State private var breatheScale: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Non-SPEC literals retained per Finding F-2 (see 03.1-01-SUMMARY.md):
            // floating-widget topology differs from SPEC §3 NSStatusItem 22pt-in-28pt + badge offsets.
            Image("ClaudeCodeIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .frame(width: 44, height: 44)
                .scaleEffect(quietHoursEnabled ? 1.0 : breatheScale * bounceScale)
                .offset(y: quietHoursEnabled ? 0 : bounceOffset)
                .onAppear {
                    startIdleAnimation()
                }
                .onChange(of: quietHoursEnabled) { _, _ in
                    restartIdleAnimation()
                }
                .onChange(of: idleAnimation) { _, _ in
                    restartIdleAnimation()
                }
                .onChange(of: reduceMotion) { _, _ in
                    restartIdleAnimation()
                }
            if pendingCount >= 2 {
                Text("+\(pendingCount - 1)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle().fill(quietHoursEnabled ? Color(NSColor.systemGray) : Color(NSColor.systemRed))
                    )
                    .offset(x: 4, y: -4)        // top-trailing -4/-4 overhang
                    .accessibilityHidden(true)  // count is announced via the parent label
            }
            if quietHoursEnabled {
                Text("Zzz")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
                    .offset(x: 5, y: pendingCount >= 2 ? 11 : -6)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 44, height: 44, alignment: .center)
        .accessibilityElement()
        .accessibilityLabel("Claude 작업 완료 알림. 보류 중 \(pendingCount)건")
        .accessibilityAddTraits(.isButton)
    }

    private func startIdleAnimation() {
        guard !quietHoursEnabled else { return }
        // Phase 03.1: consume MotionTokens (SC#1, SC#3 uniform reduce-motion gate).
        switch idleAnimation {
        case .bounce:
            guard let anim = MotionTokens.bounceAnimation(reduceMotion: reduceMotion) else { return }
            bounceScale = MotionTokens.bounceStretchScale
            withAnimation(anim) {
                bounceOffset = -MotionTokens.bounceOffset
                bounceScale = MotionTokens.bounceSquashScale
            }
        case .breathe:
            guard let anim = MotionTokens.breatheAnimation(reduceMotion: reduceMotion) else { return }
            withAnimation(anim) {
                breatheScale = MotionTokens.breatheScale
            }
        }
    }

    private func restartIdleAnimation() {
        bounceOffset = 0
        bounceScale = 1.0
        breatheScale = 1.0
        startIdleAnimation()
    }
}
