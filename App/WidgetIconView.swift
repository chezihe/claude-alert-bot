// App/WidgetIconView.swift — Phase 2 WIDG-03 (icon + project name location).
// UI-SPEC: 36pt Claude Code glyph, 4pt internal padding (44pt total).
// +N badge: 16pt × 16pt circle, systemRed fill, white SF Pro Semibold 11pt numeral.
// Anchored top-trailing with -4/-4 overhang per UI-SPEC.
// Bounce: 5pt vertical, 0.45s easeInOut, autoreverse forever; suppressed when Reduce Motion is on.
import SwiftUI
import AppKit

struct WidgetIconView: View {
    let pendingCount: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounceOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image("ClaudeCodeIcon")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 36, height: 36)
                .frame(width: 44, height: 44)
                .offset(y: bounceOffset)
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                        bounceOffset = -5
                    }
                }
            if pendingCount >= 2 {
                Text("+\(pendingCount - 1)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(
                        Circle().fill(Color(NSColor.systemRed))
                    )
                    .offset(x: 4, y: -4)        // top-trailing -4/-4 overhang
                    .accessibilityHidden(true)  // count is announced via the parent label
            }
        }
        .frame(width: 44, height: 44, alignment: .center)
        .accessibilityElement()
        .accessibilityLabel("Claude 작업 완료 알림. 보류 중 \(pendingCount)건")
        .accessibilityAddTraits(.isButton)
    }
}
