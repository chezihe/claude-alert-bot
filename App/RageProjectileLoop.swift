// App/RageProjectileLoop.swift — Rage idle projectile loop.
// Internal prototype rage loop: every 2.4s while rage is the active idle, throw a MacBook
// projectile. The glyph KeyframeAnimator (KeyframeIdleGlyph) loops the throw-windup on its
// own; this modifier handles the separate window-level projectile + the widget impact kick.
// Mounted only alongside the rage KeyframeAnimator, so both start together and the first
// throw lands on the peak forward whip of the first windup.
import SwiftUI

struct RageProjectileLoop: ViewModifier {
    // Generation invalidates queued work from a previous mount; every mount owns its own copy.
    @State private var generation: Int = 0
    @State private var workItem: DispatchWorkItem?
    @State private var impactKick: CGFloat = 0

    func body(content: Content) -> some View {
        content
            // Rage projectile impact aftershock — small vertical kick post-launch.
            .offset(y: impactKick * 1.5)
            .onAppear { start() }
            .onDisappear { stop() }
    }

    private func start() {
        stop()
        let current = generation
        scheduleNextProjectile(generation: current, delay: MotionKeyframes.rageReleaseOffset)
    }

    private func stop() {
        generation &+= 1
        workItem?.cancel()
        workItem = nil
        impactKick = 0
    }

    private func scheduleNextProjectile(generation scheduled: Int, delay: TimeInterval) {
        let item = DispatchWorkItem {
            guard scheduled == generation else { return }
            MacBookProjectileLauncher.shared.launchFromWidget()
            kickImpact(generation: scheduled)
            scheduleNextProjectile(generation: scheduled, delay: MotionKeyframes.ragePeriod)
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // Camera-shake-style kick on the widget itself right after each projectile leaves.
    // Springs up by 1.5pt, then settles. Synced to `generation` so unmounting cancels it.
    private func kickImpact(generation scheduled: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard scheduled == generation else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.35)) {
                impactKick = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard scheduled == generation else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    impactKick = 0
                }
            }
        }
    }
}
