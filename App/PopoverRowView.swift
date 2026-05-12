// App/PopoverRowView.swift — Phase 2 / Plan 02-08 popover row.
// UI-SPEC §"Popover row states" — default / hover / orphan / same-project-duplicate.
// D2-06 row display rules (project name + optional time suffix); D2-08 click action;
// D2-16 orphan `?` trailing indicator in secondaryLabelColor.
//
// Phase 3 / Plan 03-06 (D3-11/12/14): RowState integration.
// - state owned by parent (WidgetPopoverController, wired in 03-07) — leaf View per CONTEXT D3-11.
// - Click handler short-circuits when state != .normal (JUMP-05 row-level self-debounce).
// - .missing transitions trigger 도리도리(±12° 1 round-trip, 0..0.3s) → translate+collapse+fade(0.3..0.7s)
//   → onMissingComplete() callback so the parent can clear the row by alertID.
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
    var isMuted: Bool = false
    let onClick: () -> Void
    var onTogglePin: () -> Void = {}
    var onToggleMute: () -> Void = {}
    /// Phase 3 D3-11 — fired after the missing-collapse animation completes; parent should
    /// then clear this row by alertID. No-op default for call sites
    /// that pin state to `.normal` and will never reach the failure branch.
    var onMissingComplete: () -> Void = {}

    @State private var isHovered: Bool = false
    @State private var rotation: Double = 0
    @State private var collapsed: Bool = false
    @State private var faded: Bool = false
    @State private var dismissOffset: CGFloat = 0
    @State private var rippleScale: CGFloat = 1.0
    @State private var rippleOpacity: Double = 0
    @State private var waitingDotOpacity: Double = 1.0
    @ObservedObject private var settings = SettingsStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    private var reduceMotion: Bool {
        settings.reduceMotionPreference.effectiveReduceMotion(systemReduceMotion: systemReduceMotion)
    }

    var body: some View {
        Button(action: {
            // D3-11 + JUMP-05: row-level self-debounce. Click while non-.normal is a no-op.
            guard state == .normal else { return }
            onClick()
        }) {
            HStack(spacing: 8) {
                Text(session.projectName)
                    .font(.system(size: 13))
                    .foregroundStyle(state == .jumping
                                     ? Color(NSColor.tertiaryLabelColor)
                                     : Color(NSColor.labelColor))
                    .strikethrough(!session.available, color: Color(NSColor.secondaryLabelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .rotationEffect(.degrees(rotation))     // 도리도리 effect — only animates in .missing
                if session.pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .rotationEffect(.degrees(45))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .accessibilityLabel("Pinned")
                }
                Spacer(minLength: 0)
                if showTimeSuffix {
                    Text("· \(PopoverContentRules.timeSuffix(for: session.stoppedAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
                if PopoverContentRules.showsOrphanIndicator(session: session) {
                    Text("?")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .accessibilityLabel("Unknown Duration")
                }
                statusDot
            }
            .padding(.vertical, GeometryTokens.rowVerticalPadding)
            .padding(.horizontal, GeometryTokens.rowHorizontalPadding)
            .frame(minHeight: collapsed ? 0 : GeometryTokens.rowMinHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovered ? ColorTokens.rowHover(colorScheme: colorScheme) : Color.clear
            )
            .opacity(faded ? 0 : (session.available ? 1 : 0.5))
            .offset(x: dismissOffset)
            .saturation(PopoverContentRules.isAged(session: session, now: Date()) ? EffectTokens.agedSaturation : 1.0)
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .clipped()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state != .normal)                         // belt-and-suspenders for JUMP-05
        .contextMenu {
            Button(session.pinned ? "Unpin" : "Pin") { onTogglePin() }
            Button(isMuted ? "Unmute This Project" : "Mute this project for 1h") { onToggleMute() }
        }
        .onHover { hovering in
            isHovered = hovering
        }
        .onAppear {
            runArrivalRippleIfNeeded()
            runWaitingDotPulseIfNeeded()
        }
        .onChange(of: session.kind) { _, _ in
            runWaitingDotPulseIfNeeded()
        }
        .onChange(of: session.available) { _, _ in
            runWaitingDotPulseIfNeeded()
        }
        .onChange(of: reduceMotion) { _, _ in
            resetArrivalRipple()
            runArrivalRippleIfNeeded()
            runWaitingDotPulseIfNeeded()
        }
        .onChange(of: state) { _, newState in
            if newState == .missing {
                runMissingAnimation()
            }
        }
        .accessibilityLabel(rowAccessibilityLabel)
    }

    private var rowAccessibilityLabel: String {
        let pinnedPrefix = session.pinned ? "Pinned, " : ""
        let statusText = session.available ? "session complete" : "session unavailable"
        let actionText = session.available ? "activate to jump" : "activate to clear"
        return "\(session.projectName), \(pinnedPrefix)\(statusText), \(actionText)"
    }

    @ViewBuilder
    private var statusDot: some View {
        let dotColor = ColorTokens.statusDot(for: session.kind)
        if session.available {
            Circle()
                .fill(dotColor)
                .frame(width: GeometryTokens.statusDotDiameter,
                       height: GeometryTokens.statusDotDiameter)
                .opacity(waitingDotOpacity)
                .overlay {
                    Circle()
                        .stroke(dotColor.opacity(rippleOpacity), lineWidth: GeometryTokens.statusDotRingStroke)
                        .frame(width: GeometryTokens.statusDotDiameter,
                               height: GeometryTokens.statusDotDiameter)
                        .scaleEffect(rippleScale)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
        } else {
            Circle()
                .stroke(dotColor, lineWidth: GeometryTokens.statusDotRingStroke)
                .frame(width: GeometryTokens.statusDotDiameter,
                       height: GeometryTokens.statusDotDiameter)
        }
    }

    private func runArrivalRippleIfNeeded() {
        guard session.available else { return }
        guard PopoverContentRules.isJustArrived(session: session, now: Date()) else { return }
        guard !reduceMotion else { return }
        rippleScale = 1.0
        rippleOpacity = MotionTokens.statusDotRippleStartOpacity
        withAnimation(.easeOut(duration: MotionTokens.statusDotRippleDuration).repeatCount(MotionTokens.statusDotRippleRepeatCount, autoreverses: false)) {
            rippleScale = MotionTokens.statusDotRippleEndScale
            rippleOpacity = 0
        }
    }

    private func resetArrivalRipple() {
        withTransaction(Transaction(animation: nil)) {
            rippleScale = 1.0
            rippleOpacity = 0
        }
    }

    private func runWaitingDotPulseIfNeeded() {
        withTransaction(Transaction(animation: nil)) {
            waitingDotOpacity = 1.0
        }
        guard session.available, session.kind == .waiting else { return }
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: MotionTokens.waitingDotPulseDuration).repeatForever(autoreverses: true)) {
            waitingDotOpacity = MotionTokens.waitingDotPulseMinOpacity
        }
    }

    // MARK: - Phase 3 D3-11 missing animation

    private func runMissingAnimation() {
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
                // Phase 2 (0.3..0.7s): translate + collapse + fade.
                withAnimation(.easeInOut(duration: 0.4), completionCriteria: .logicallyComplete) {
                    collapsed = true
                    faded = true
                    dismissOffset = 8
                } completion: {
                    onMissingComplete()
                }
            }
        }
    }
}
