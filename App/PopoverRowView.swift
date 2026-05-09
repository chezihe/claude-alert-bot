// App/PopoverRowView.swift — Phase 2 / Plan 02-08 popover row.
// UI-SPEC §"Popover row states" — default / hover / orphan / same-project-duplicate.
// D2-06 row display rules (project name + optional time suffix); D2-08 click action;
// D2-16 orphan `?` trailing indicator in secondaryLabelColor.
//
// Phase 3 / Plan 03-06 (D3-11/12/14): RowState integration.
// - state owned by parent (WidgetPopoverController, wired in 03-07) — leaf View per CONTEXT D3-11.
// - Click handler short-circuits when state != .normal (JUMP-05 row-level self-debounce).
// - .missing transitions trigger 도리도리(±12° 1 round-trip, 0..0.3s) → collapse+fade(0.3..0.7s)
//   → onMissingComplete() callback so the parent can call SessionRegistry.clearOne(sessionID:).
// - Reduced-motion fallback skips rotation, collapses immediately
//   (mirrors FloatingWidgetWindowController.swift lines 113-115).
// - D3-12: animation IS the message — no copy strings, no sound, no system notifications.
// Phase 03.1: row geometry literals (36/12/8) resolve through GeometryTokens (SC#1).
// Non-SPEC literals retained per Finding F-2: hover color/anim (controlAccentColor + 0.12s),
// Phase 3 D3-11 missing-animation timings (0.15s × 2 + 0.4s collapse + 0.2s reduce-motion fallback),
// typography (13pt body, 11pt secondary). See 03.1-01-SUMMARY.md.
import SwiftUI
import AppKit

/// Phase 3 D3-11 row state. Owned by WidgetPopoverController; passed down per PATTERNS Option C.
enum RowState: Equatable {
    case normal
    case jumping     // click in flight; row visually dimmed + non-interactive (JUMP-05 self-debounce)
    case missing     // jump returned .missing/.iTermNotRunning/.timeout/.permissionDenied/.otherError → 도리도리+collapse
}

struct PopoverRowView: View {
    let session: CompletedSession
    let showTimeSuffix: Bool
    /// Phase 3 D3-11 — state owned by parent (WidgetPopoverController via PopoverContentView).
    /// Default `.normal` keeps any call site that hasn't wired state yet working until 03-07.
    var state: RowState = .normal
    let onClick: () -> Void
    /// Phase 3 D3-11 — fired after the missing-collapse animation completes; parent should
    /// then call `SessionRegistry.shared.clearOne(sessionID:)`. No-op default for call sites
    /// that pin state to `.normal` and will never reach the failure branch.
    var onMissingComplete: () -> Void = {}

    @State private var isHovered: Bool = false
    @State private var rotation: Double = 0
    @State private var collapsed: Bool = false
    @State private var faded: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: {
            // D3-11 + JUMP-05: row-level self-debounce. Click while non-.normal is a no-op.
            guard state == .normal else { return }
            onClick()
        }) {
            HStack(spacing: 8) {
                statusDot
                Text(session.projectName)
                    .font(.system(size: 13))
                    .foregroundStyle(state == .jumping
                                     ? Color(NSColor.tertiaryLabelColor)
                                     : Color(NSColor.labelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .rotationEffect(.degrees(rotation))     // 도리도리 effect — only animates in .missing
                Spacer()
                if showTimeSuffix {
                    Text("· \(PopoverContentRules.timeSuffix(for: session.stoppedAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
                if PopoverContentRules.showsOrphanIndicator(session: session) {
                    Text("?")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .accessibilityLabel("경과 시간 알 수 없음")
                }
            }
            .padding(.vertical, GeometryTokens.rowVerticalPadding)
            .padding(.horizontal, GeometryTokens.rowHorizontalPadding)
            .frame(minHeight: collapsed ? 0 : GeometryTokens.rowMinHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovered ? ColorTokens.rowHover(colorScheme: colorScheme) : Color.clear
            )
            .opacity(faded ? 0 : (session.available ? 1 : 0.5))
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state != .normal)                         // belt-and-suspenders for JUMP-05
        .onHover { hovering in
            isHovered = hovering
        }
        .onChange(of: state) { _, newState in
            if newState == .missing {
                runMissingAnimation()
            }
        }
        .accessibilityLabel("\(session.projectName) 작업 완료, 클릭하여 정리")
    }

    @ViewBuilder
    private var statusDot: some View {
        if session.available {
            Circle()
                .fill(ColorTokens.statusSuccess)
                .frame(width: GeometryTokens.statusDotDiameter,
                       height: GeometryTokens.statusDotDiameter)
        } else {
            Circle()
                .stroke(ColorTokens.statusSuccess, lineWidth: GeometryTokens.statusDotRingStroke)
                .frame(width: GeometryTokens.statusDotDiameter,
                       height: GeometryTokens.statusDotDiameter)
        }
    }

    // MARK: - Phase 3 D3-11 missing animation

    private func runMissingAnimation() {
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            // A11y: skip rotation, immediate collapse.
            withAnimation(.easeInOut(duration: 0.2), completionCriteria: .logicallyComplete) {
                collapsed = true
                faded = true
            } completion: {
                onMissingComplete()
            }
            return
        }

        // Phase 1 (0..0.3s): 도리도리 — rotation +12 → -12 → 0 (1 round-trip).
        withAnimation(.easeInOut(duration: 0.15)) { rotation = 12 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.15)) { rotation = -12 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                // settle to 0 (no animation — instant) and chain to phase 2.
                rotation = 0
                // Phase 2 (0.3..0.7s): collapse + fade.
                withAnimation(.easeInOut(duration: 0.4), completionCriteria: .logicallyComplete) {
                    collapsed = true
                    faded = true
                } completion: {
                    onMissingComplete()
                }
            }
        }
    }
}
