// ClaudeAlertBotTests/IdleAnimationTests.swift — WO-012 idle animation selector contract.
// Behaviour tests for WidgetIconView's idle gate, keyframe step tables, roam / rage
// motion math, badges and accessibility copy (no source-text matching on the view files).
import XCTest
import SwiftUI
@testable import ClaudeAlertBot

final class IdleAnimationTests: XCTestCase {

    func test_idleAnimation_defaultIsBounce() {
        XCTAssertEqual(IdleAnimation.default, .bounce)
    }

    func test_idleAnimation_allCasesMatchProto() {
        XCTAssertTrue(IdleAnimation.allCases.contains(.bounce))
        XCTAssertTrue(IdleAnimation.allCases.contains(.heart))
        XCTAssertTrue(IdleAnimation.allCases.contains(.ring))
        XCTAssertTrue(IdleAnimation.allCases.contains(.roam))
        XCTAssertTrue(IdleAnimation.allCases.contains(.rage))
        XCTAssertEqual(IdleAnimation.allCases.count, 5)
        XCTAssertNil(IdleAnimation(rawValue: "magic"), "Magic was removed; a stored \"magic\" falls back to the default")
    }

    // MARK: - activeIdle gate

    func test_activeIdle_runsSelectedIdleForClaudeIcon() {
        for idle in IdleAnimation.allCases {
            XCTAssertEqual(activeIdle(idle), idle, "\(idle) must run for the Claude icon")
        }
    }

    func test_activeIdle_claudeIdleAnimatorsDoNotRunForZeldaIcon() {
        for idle in IdleAnimation.allCases {
            XCTAssertNil(activeIdle(idle, style: .zelda), "\(idle) must not run for the Zelda icon")
        }
    }

    func test_activeIdle_quietHoursSuppressesIdle() {
        for idle in IdleAnimation.allCases {
            XCTAssertNil(activeIdle(idle, quietHours: true), "\(idle) must stop in Quiet Hours")
        }
    }

    func test_activeIdle_reduceMotionSuppressesIdle() {
        for idle in IdleAnimation.allCases {
            XCTAssertNil(activeIdle(idle, reduceMotion: true), "\(idle) must stop under Reduce Motion")
        }
    }

    func test_reduceMotionPreference_feedsIdleGate() {
        // `.reduced` forces Reduce Motion even when the system setting is off.
        let reduced = ReduceMotionPreference.reduced.effectiveReduceMotion(systemReduceMotion: false)
        XCTAssertNil(activeIdle(.bounce, reduceMotion: reduced))
        let system = ReduceMotionPreference.system.effectiveReduceMotion(systemReduceMotion: false)
        XCTAssertEqual(activeIdle(.bounce, reduceMotion: system), .bounce)
        XCTAssertTrue(ReduceMotionPreference.system.effectiveReduceMotion(systemReduceMotion: true))
    }

    // MARK: - Keyframe animators (bounce / heart / rage / ring)

    func test_bounceSteps_followCycleAndSumToPeriod() {
        assertSteps(
            MotionKeyframes.bounceSteps.map(\.frame), Array(MotionKeyframes.bounceCycle.dropFirst()),
            durations: MotionKeyframes.bounceSteps.map(\.duration),
            fractions: [0.18, 0.32, 0.32, 0.18], period: MotionKeyframes.bouncePeriod
        )
    }

    func test_heartSteps_followCycleAndSumToPeriod() {
        assertSteps(
            MotionKeyframes.heartSteps.map(\.frame), Array(MotionKeyframes.heartCycle.dropFirst()),
            durations: MotionKeyframes.heartSteps.map(\.duration),
            fractions: [0.14, 0.14, 0.14, 0.14, 0.44], period: MotionKeyframes.heartPeriod
        )
    }

    func test_ringSteps_followCycleAndSumToPeriod() {
        // Indices 1–6 are the damped bell swing (10% each); 7+8 the micro-aftershock; 9 settles to 0.
        assertSteps(
            MotionKeyframes.ringSteps.map(\.frame), Array(MotionKeyframes.ringCycle.dropFirst()),
            durations: MotionKeyframes.ringSteps.map(\.duration),
            fractions: [0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.10, 0.15, 0.15], period: MotionKeyframes.ringPeriod
        )
        XCTAssertEqual(MotionKeyframes.ringSteps.last?.frame.rotation, 0, "Ring must settle back to 0°")
    }

    func test_rageSteps_windupThenHoldAtIdentity_loopsAtRagePeriod() {
        let steps = MotionKeyframes.rageSteps
        let windup = Array(steps.dropLast())
        assertSteps(
            windup.map(\.frame), Array(MotionKeyframes.rageCycle.dropFirst()),
            durations: windup.map(\.duration),
            fractions: [0.18, 0.12, 0.14, 0.14, 0.20, 0.22], period: MotionKeyframes.rageWindupDuration
        )
        let hold = steps.last
        XCTAssertEqual(hold?.frame, MotionKeyframes.rageCycle.last)
        XCTAssertEqual(hold?.duration ?? 0, MotionKeyframes.rageHoldDuration, accuracy: 1e-9)
        XCTAssertEqual(hold?.frame.rotation, 0)
        XCTAssertEqual(hold?.frame.scale, 1)
        XCTAssertEqual(steps.map(\.duration).reduce(0, +), MotionKeyframes.ragePeriod, accuracy: 1e-9)
        XCTAssertEqual(MotionKeyframes.ragePeriod, 2.4, accuracy: 1e-9)
    }

    func test_animatorInitialValues_matchFirstKeyframe() {
        let bounce = BounceAnimatorValue()
        let bounce0 = MotionKeyframes.bounceCycle[0]
        XCTAssertEqual(bounce.translateY, bounce0.translateY)
        XCTAssertEqual(bounce.scaleX, bounce0.scaleX)
        XCTAssertEqual(bounce.scaleY, bounce0.scaleY)
        XCTAssertEqual(bounce.rotation, bounce0.rotation)
        XCTAssertEqual(HeartAnimatorValue().scale, MotionKeyframes.heartCycle[0].scale)
        let rage = RageAnimatorValue()
        let rage0 = MotionKeyframes.rageCycle[0]
        XCTAssertEqual(rage.rotation, rage0.rotation)
        XCTAssertEqual(rage.translateX, rage0.translateX)
        XCTAssertEqual(rage.translateY, rage0.translateY)
        XCTAssertEqual(rage.scale, rage0.scale)
        XCTAssertEqual(RingAnimatorValue().rotation, MotionKeyframes.ringCycle[0].rotation)
    }

    func test_glyphMotion_defaultsAreAtRest() {
        let motion = GlyphMotion()
        XCTAssertEqual(motion.heartScale, 1)
        XCTAssertEqual(motion.ringRotation, 0)
        XCTAssertEqual(motion.rage.rotation, 0)
        XCTAssertEqual(motion.rage.scale, 1)
    }

    // MARK: - Rage projectile loop

    func test_rageProjectile_releasesAtPeakForwardWhip() {
        // The 44% windup keyframe is the most-negative (forward) rotation — the throw release.
        let whip = MotionKeyframes.rageCycle.min { $0.rotation < $1.rotation }
        XCTAssertEqual(whip?.percent, 44)
        XCTAssertEqual(MotionKeyframes.rageReleaseOffset,
                       MotionKeyframes.rageWindupDuration * 0.44, accuracy: 1e-9)
        XCTAssertLessThan(MotionKeyframes.rageReleaseOffset, MotionKeyframes.ragePeriod)
    }

    // MARK: - Roam

    func test_roamOffsetEffect_tracesCounterClockwiseEllipse() {
        let rx = Double(MotionTokens.roamRadiusX)
        let ry = Double(MotionTokens.roamRadiusY)
        // Phase animates 0 → -360: right → top (SwiftUI y grows down) → left → bottom.
        assertTranslation(roam(angle: 0), x: rx, y: 0)
        assertTranslation(roam(angle: -90), x: 0, y: -ry)
        assertTranslation(roam(angle: -180), x: -rx, y: 0)
        assertTranslation(roam(angle: -270), x: 0, y: ry)
    }

    func test_roamOffsetEffect_inactiveIsIdentity_andAngleIsAnimatable() {
        let inactive = RoamOffsetEffect(angle: -90, radiusX: 16, radiusY: 4, isActive: false)
        assertTranslation(inactive, x: 0, y: 0)

        var effect = RoamOffsetEffect(angle: 0, radiusX: 16, radiusY: 4, isActive: true)
        effect.animatableData = -45
        XCTAssertEqual(effect.angle, -45)
    }

    func test_roamAnimation_repeatsForeverUnlessReduceMotion() {
        XCTAssertNotNil(MotionTokens.roamAnimation(reduceMotion: false))
        XCTAssertNil(MotionTokens.roamAnimation(reduceMotion: true))
    }

    func test_widgetDrawableSize_expandsOnlyForActiveRoam() {
        let base = GeometryTokens.widgetDrawableSize(idleAnimation: .bounce, quietHoursEnabled: false, reduceMotion: false)
        let roam = GeometryTokens.widgetDrawableSize(idleAnimation: .roam, quietHoursEnabled: false, reduceMotion: false)
        XCTAssertGreaterThan(roam.width, base.width)
        XCTAssertEqual(GeometryTokens.widgetDrawableSize(idleAnimation: .roam, quietHoursEnabled: true, reduceMotion: false), base)
        XCTAssertEqual(GeometryTokens.widgetDrawableSize(idleAnimation: .roam, quietHoursEnabled: false, reduceMotion: true), base)
    }

    // MARK: - New-alert pulse

    func test_alertPulse_runsOnlyForNewPositivePulseID() {
        XCTAssertTrue(WidgetIconView.shouldRunAlertPulse(alertPulseID: 1, activeAlertPulseID: 0, quietHoursEnabled: false))
        XCTAssertFalse(WidgetIconView.shouldRunAlertPulse(alertPulseID: 0, activeAlertPulseID: 0, quietHoursEnabled: false))
        XCTAssertFalse(WidgetIconView.shouldRunAlertPulse(alertPulseID: 3, activeAlertPulseID: 3, quietHoursEnabled: false))
    }

    func test_alertPulse_quietHoursSuppressesNewAlertPulse() {
        XCTAssertFalse(WidgetIconView.shouldRunAlertPulse(alertPulseID: 2, activeAlertPulseID: 1, quietHoursEnabled: true))
    }

    // MARK: - Badges

    func test_badgeKind_claudeShowsCountFromTwoSessions() {
        XCTAssertEqual(WidgetIconView.badgeKind(widgetIconStyle: .claude, pendingCount: 0), .none)
        XCTAssertEqual(WidgetIconView.badgeKind(widgetIconStyle: .claude, pendingCount: 1), .none)
        XCTAssertEqual(WidgetIconView.badgeKind(widgetIconStyle: .claude, pendingCount: 2), .count)
        XCTAssertEqual(WidgetIconView.badgeKind(widgetIconStyle: .claude, pendingCount: 9), .count)
    }

    func test_badgeKind_replacesBadgeWithZeldaHeartsOnlyForZelda() {
        XCTAssertEqual(WidgetIconView.badgeKind(widgetIconStyle: .zelda, pendingCount: 0), .none)
        XCTAssertEqual(WidgetIconView.badgeKind(widgetIconStyle: .zelda, pendingCount: 1), .hearts)
        XCTAssertEqual(WidgetIconView.badgeKind(widgetIconStyle: .zelda, pendingCount: 5), .hearts)
    }

    func test_badgeText_showsTotalPendingSessionCount() {
        XCTAssertEqual(WidgetIconView.badgeText(pendingCount: 2), "+2")
        XCTAssertEqual(WidgetIconView.badgeText(pendingCount: 7), "+7")
    }

    func test_pendingBadge_positionedWithZeldaLikeClearance() {
        XCTAssertEqual(WidgetIconView.badgeOffset, CGSize(width: -2, height: -10))
        XCTAssertEqual(GeometryTokens.widgetBadgeTopClearance, 12)
    }

    func test_zeldaHeartBadge_framesAndOverflow() {
        XCTAssertEqual(ZeldaHeartBadge.frameName(pendingCount: 1), "heart_frame_01")
        XCTAssertEqual(ZeldaHeartBadge.frameName(pendingCount: 2), "heart_frame_02")
        XCTAssertEqual(ZeldaHeartBadge.frameName(pendingCount: 3), "heart_frame_03")
        XCTAssertEqual(ZeldaHeartBadge.frameName(pendingCount: 8), "heart_frame_03")
        XCTAssertNil(ZeldaHeartBadge.overflowText(pendingCount: 3))
        XCTAssertEqual(ZeldaHeartBadge.overflowText(pendingCount: 4), "+1")
        XCTAssertEqual(ZeldaHeartBadge.overflowText(pendingCount: 6), "+3")
        XCTAssertEqual(ZeldaHeartBadge.offset, CGSize(width: -1, height: -18))
    }

    // MARK: - Zelda glyph

    func test_zeldaFrames_idleAndAlertSequences() {
        XCTAssertEqual(ZeldaFrame.idleFrames, ["zelda_frame_00", "zelda_frame_01"])
        XCTAssertEqual(ZeldaFrame.alertFrames(effect: .heal),
                       ["zelda_frame_02", "zelda_frame_03", "zelda_frame_04_heal"])
        XCTAssertEqual(ZeldaFrame.alertFrames(effect: .hit),
                       ["zelda_frame_02", "zelda_frame_03", "zelda_frame_04_hit"])
    }

    func test_zeldaGlyph_playsAlertSequenceThenReturnsToIdleLoop() {
        let idleStart = Date(timeIntervalSinceReferenceDate: 0)
        let alertStart = Date(timeIntervalSinceReferenceDate: 100)
        func frame(_ t: TimeInterval) -> String {
            ZeldaGlyph.frameName(at: alertStart + t, idleStartedAt: idleStart, alertStartedAt: alertStart, effect: .hit)
        }
        let step = ZeldaGlyph.alertFrameDuration
        XCTAssertEqual(frame(0.01), "zelda_frame_02")
        XCTAssertEqual(frame(step + 0.01), "zelda_frame_03")
        // Final alert frame holds ×1.5.
        XCTAssertEqual(frame(2 * step + 0.01), "zelda_frame_04_hit")
        XCTAssertEqual(frame(2 * step + 1.5 * step - 0.01), "zelda_frame_04_hit")
        XCTAssertTrue(ZeldaFrame.idleFrames.contains(frame(2 * step + 1.5 * step + 0.01)))
    }

    func test_zeldaGlyph_idleLoopAlternatesFrames() {
        let idleStart = Date(timeIntervalSinceReferenceDate: 0)
        func frame(_ t: TimeInterval) -> String {
            ZeldaGlyph.frameName(at: idleStart + t, idleStartedAt: idleStart, alertStartedAt: .distantFuture, effect: .heal)
        }
        let step = ZeldaGlyph.idleFrameDuration
        XCTAssertEqual(frame(0.01), "zelda_frame_00")
        XCTAssertEqual(frame(step + 0.01), "zelda_frame_01")
        XCTAssertEqual(frame(2 * step + 0.01), "zelda_frame_00")
    }

    func test_glyphGeometry_doubleSizeZeldaAndFixedClaudeOffset() {
        XCTAssertEqual(WidgetIconView.glyphSize(for: .claude), CGSize(width: 46, height: 46))
        XCTAssertEqual(WidgetIconView.glyphSize(for: .zelda), CGSize(width: 92, height: 92))
        // Glyph offset depends only on icon style, never on the pending badge.
        XCTAssertEqual(WidgetIconView.glyphOffset(for: .claude), CGSize(width: 0, height: 8))
        XCTAssertEqual(WidgetIconView.glyphOffset(for: .zelda), CGSize(width: 0, height: 18))
    }

    // MARK: - Accessibility

    func test_widgetIconViewAccessibilityLabel_announcesQuietHoursState() {
        XCTAssertEqual(WidgetIconView.accessibilityLabel(pendingCount: 1, quietHoursEnabled: false),
                       "Claude alert. 1 pending session")
        XCTAssertEqual(WidgetIconView.accessibilityLabel(pendingCount: 3, quietHoursEnabled: false),
                       "Claude alert. 3 pending sessions")
        XCTAssertEqual(WidgetIconView.accessibilityLabel(pendingCount: 2, quietHoursEnabled: true),
                       "Claude alert. 2 pending sessions. Quiet Hours")
    }

    // MARK: - FloatingWidgetWindowController wiring

    func test_floatingWidgetWindowController_passesSelectedIdleAnimationToIconView() {
        let src = readFloatingWidgetWindowControllerSource()

        XCTAssertTrue(src.contains("idleAnimation: SettingsStore.shared.idleAnimation"))
    }

    func test_floatingWidgetWindowController_passesReduceMotionPreferenceToIconView() {
        let src = readFloatingWidgetWindowControllerSource()

        XCTAssertTrue(src.contains("reduceMotionPreference: SettingsStore.shared.reduceMotionPreference"))
    }

    func test_floatingWidgetWindowController_resizesHostToWidgetDrawableSize() {
        let src = readFloatingWidgetWindowControllerSource()

        XCTAssertTrue(src.contains("GeometryTokens.widgetDrawableSize("))
        XCTAssertTrue(src.contains("resizeContent(to: size)"))
        XCTAssertTrue(src.contains("panel.setFrame(frame, display: true)"))
        XCTAssertTrue(src.contains("hostingView?.frame = NSRect(origin: .zero, size: size)"))
    }

    func test_floatingWidgetWindowController_passesAlertPulseIDToIconView() {
        let src = readFloatingWidgetWindowControllerSource()

        XCTAssertTrue(src.contains("if latest != nil && !SettingsStore.shared.quietHoursEnabled"))
        XCTAssertTrue(src.contains("currentAlertPulseID += 1"))
        XCTAssertTrue(src.contains("alertPulseID: currentAlertPulseID"))
    }

    func test_floatingWidgetWindowControllerPassesWidgetSideAndAlertEffectToIconView() {
        let src = readFloatingWidgetWindowControllerSource()

        XCTAssertTrue(src.contains("widgetSide: store.widgetCorner.widgetSide"))
        XCTAssertTrue(src.contains("alertEffect: currentAlertEffect"))
        XCTAssertTrue(src.contains("currentAlertEffect = SettingsStore.shared.zeldaAlertEffect"))
        XCTAssertFalse(src.contains("currentAlertEffect = .heal"))
    }


    // MARK: - Helpers

    private func activeIdle(
        _ idle: IdleAnimation,
        style: WidgetIconStyle = .claude,
        quietHours: Bool = false,
        reduceMotion: Bool = false
    ) -> IdleAnimation? {
        WidgetIconView.activeIdle(
            idleAnimation: idle,
            widgetIconStyle: style,
            quietHoursEnabled: quietHours,
            reduceMotion: reduceMotion
        )
    }

    private func assertSteps<Frame: Equatable>(
        _ frames: [Frame],
        _ expectedFrames: [Frame],
        durations: [TimeInterval],
        fractions: [Double],
        period: TimeInterval,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(frames, expectedFrames, "Steps must target keyframes 1...n in order", file: file, line: line)
        XCTAssertEqual(durations.count, fractions.count, file: file, line: line)
        for (duration, fraction) in zip(durations, fractions) {
            XCTAssertEqual(duration, period * fraction, accuracy: 1e-9, file: file, line: line)
        }
        XCTAssertEqual(durations.reduce(0, +), period, accuracy: 1e-9, "Steps must sum to the cycle period",
                       file: file, line: line)
    }

    private func roam(angle: Double) -> RoamOffsetEffect {
        RoamOffsetEffect(
            angle: angle,
            radiusX: Double(MotionTokens.roamRadiusX),
            radiusY: Double(MotionTokens.roamRadiusY),
            isActive: true
        )
    }

    private func assertTranslation(
        _ effect: RoamOffsetEffect,
        x: Double,
        y: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let transform = effect.effectValue(size: .zero)
        XCTAssertEqual(Double(transform.m31), x, accuracy: 1e-9, "tx", file: file, line: line)
        XCTAssertEqual(Double(transform.m32), y, accuracy: 1e-9, "ty", file: file, line: line)
    }

    private func readFloatingWidgetWindowControllerSource(_ thisFile: StaticString = #filePath) -> String {
        let here = URL(fileURLWithPath: "\(thisFile)")
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/FloatingWidgetWindowController.swift")
        guard let data = try? String(contentsOf: target, encoding: .utf8) else {
            XCTFail("Could not read App/FloatingWidgetWindowController.swift at \(target.path)")
            return ""
        }
        return data
    }
}
