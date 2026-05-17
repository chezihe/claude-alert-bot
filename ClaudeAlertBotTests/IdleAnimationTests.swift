// ClaudeAlertBotTests/IdleAnimationTests.swift — WO-012 idle animation selector contract.
import XCTest
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
        XCTAssertTrue(IdleAnimation.allCases.contains(.magic))
        XCTAssertEqual(IdleAnimation.allCases.count, 6)
    }

    func test_widgetIconViewSource_wiresMagicAnimationOverlay() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("case .magic:"))
        XCTAssertTrue(src.contains("magicCastOverlay"))
        XCTAssertTrue(src.contains("magicAnimatorActive"))
        XCTAssertTrue(src.contains("magicCastPhase"))
    }

    func test_widgetIconViewSource_wiresHeartKeyframeAnimator() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("MotionKeyframes.heartCycle"))
        XCTAssertTrue(src.contains("MotionKeyframes.heartPeriod"))
        XCTAssertTrue(src.contains("HeartAnimatorValue"))
        // Anchor at center — HTML transform-origin: 50% 50% for heartbeat.
        XCTAssertTrue(src.contains("anchor: .center"))
    }

    func test_widgetIconViewSource_wiresRingKeyframeAnimator() {
        // Ring runs as its own KeyframeAnimator branch so the animation lifecycle is bound to
        // the branch's mount state. Switching idle animations unmounts the branch and the
        // glyph snaps back to 0° without a leaked `.repeatForever`.
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("ringAnimatorActive"))
        XCTAssertTrue(src.contains("RingAnimatorValue"))
        XCTAssertTrue(src.contains("MotionKeyframes.ringCycle"))
        XCTAssertTrue(src.contains("MotionKeyframes.ringPeriod"))
        XCTAssertTrue(src.contains("alertPulseRotation + ringRotation"))
        XCTAssertTrue(src.contains("anchor: UnitPoint(x: 0.5, y: 0.1)"))
    }

    func test_widgetIconViewSource_wiresRoamBranch() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("@State private var roamPhase: Double = 0"))
        XCTAssertTrue(src.contains(".modifier(RoamOffsetEffect("))
        XCTAssertTrue(src.contains("case .roam:"))
        XCTAssertTrue(src.contains("MotionTokens.roamAnimation"))
        XCTAssertTrue(src.contains("roamPhase = -360"))
        XCTAssertTrue(src.contains("roamPhase = 0"))
    }

    func test_widgetIconViewSource_wiresRageKeyframeAnimator() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("MotionKeyframes.rageCycle"))
        XCTAssertTrue(src.contains("MotionKeyframes.rageWindupDuration"))
        XCTAssertTrue(src.contains("MotionKeyframes.rageHoldDuration"))
        XCTAssertTrue(src.contains("RageAnimatorValue"))
        // HTML transform-origin 50% 90% for throw-windup.
        XCTAssertTrue(src.contains("UnitPoint(x: 0.5, y: 0.9)"))
    }

    func test_widgetIconViewSource_rageProjectileLoopRestartsOnIdleChange() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("@State private var rageGeneration: Int = 0"))
        XCTAssertTrue(src.contains("private func restartRageProjectileLoop()"))
        XCTAssertTrue(src.contains("private func stopRageProjectileLoop()"))
        XCTAssertTrue(src.contains("MacBookProjectileLauncher.shared.launchFromWidget()"))
    }

    func test_widgetIconViewSource_roamUsesCounterClockwiseGeometryEffect() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("private struct RoamOffsetEffect: GeometryEffect"))
        XCTAssertTrue(src.contains("var animatableData: Double"))
        XCTAssertTrue(src.contains("cos(radians) * radiusX"))
        XCTAssertTrue(src.contains("sin(radians) * radiusY"))
        XCTAssertTrue(src.contains("ProjectionTransform(CGAffineTransform(translationX: x, y: y))"))
    }

    func test_widgetIconViewSource_wiresBounceKeyframeAnimator() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("KeyframeAnimator"))
        XCTAssertTrue(src.contains("MotionKeyframes.bounceCycle"))
        XCTAssertTrue(src.contains("MotionKeyframes.bouncePeriod"))
        XCTAssertTrue(src.contains("BounceAnimatorValue"))
        // Anchor at bottom — HTML transform-origin: 50% 100% for bounce-cute.
        XCTAssertTrue(src.contains("anchor: .bottom"))
    }

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

    func test_widgetIconViewSource_usesExpandedDrawableBoundsForRoam() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("private var widgetBoundsSize: CGSize"))
        XCTAssertTrue(src.contains("GeometryTokens.widgetDrawableSize("))
        XCTAssertTrue(src.contains(".frame(width: GeometryTokens.widgetBaseSize.width, height: GeometryTokens.widgetBaseSize.height, alignment: .center)"))
        // Magic biases the outer bounds to .leading so the wand/burst can fan out to
        // the right of the icon; every other idle keeps the classic center alignment.
        XCTAssertTrue(src.contains(".frame(width: widgetBoundsSize.width, height: widgetBoundsSize.height, alignment: magicAnimatorActive ? .leading : .center)"))
    }

    func test_floatingWidgetWindowController_passesAlertPulseIDToIconView() {
        let src = readFloatingWidgetWindowControllerSource()

        XCTAssertTrue(src.contains("if latest != nil && !SettingsStore.shared.quietHoursEnabled"))
        XCTAssertTrue(src.contains("currentAlertPulseID += 1"))
        XCTAssertTrue(src.contains("alertPulseID: currentAlertPulseID"))
    }

    func test_widgetIconViewSource_restartsWhenIdleAnimationChanges() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains(".onChange(of: idleAnimation)"))
        XCTAssertTrue(src.contains("restartIdleAnimation()"))
        XCTAssertTrue(src.contains("private func restartIdleAnimation()"))
        guard let restartStart = src.range(of: "private func restartIdleAnimation()") else {
            return
        }
        let restartBody = String(src[restartStart.lowerBound...])
        XCTAssertTrue(restartBody.contains("roamPhase = 0"))
        XCTAssertTrue(restartBody.contains("startIdleAnimation()"))
    }

    func test_widgetIconViewSource_claudeIdleAnimatorsDoNotRunForZeldaIcon() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("widgetIconStyle == .claude && idleAnimation == .bounce"))
        XCTAssertTrue(src.contains("widgetIconStyle == .claude && idleAnimation == .heart"))
        XCTAssertTrue(src.contains("widgetIconStyle == .claude && idleAnimation == .rage"))
        XCTAssertTrue(src.contains("widgetIconStyle == .claude && idleAnimation == .ring"))
        XCTAssertTrue(src.contains("widgetIconStyle == .claude && idleAnimation == .magic"))
        XCTAssertTrue(src.contains("idleAnimation == .roam && widgetIconStyle == .claude"))
    }

    func test_widgetIconViewSource_restartsWhenReduceMotionChanges() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("var reduceMotionPreference: ReduceMotionPreference = .system"))
        XCTAssertTrue(src.contains("@Environment(\\.accessibilityReduceMotion) private var systemReduceMotion"))
        XCTAssertTrue(src.contains("reduceMotionPreference.effectiveReduceMotion(systemReduceMotion: systemReduceMotion)"))
        XCTAssertTrue(src.contains(".onChange(of: reduceMotion)"))
        XCTAssertTrue(src.contains("restartIdleAnimation()"))
    }

    func test_widgetIconViewSource_cancelsAlertPulseWhenReduceMotionChanges() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("@State private var alertPulseGeneration: Int = 0"))
        XCTAssertTrue(src.contains("resetAlertPulse()"))
        XCTAssertTrue(src.contains("private func resetAlertPulse()"))
        XCTAssertTrue(src.contains("withTransaction(Transaction(animation: nil))"))
        XCTAssertTrue(src.contains("let pulseGeneration = alertPulseGeneration"))
        XCTAssertTrue(src.contains("alertPulseGeneration == pulseGeneration"))
    }

    func test_widgetIconViewSource_runsNewAlertPulseWhenPulseIDChanges() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("var alertPulseID: Int = 0"))
        XCTAssertTrue(src.contains("@State private var alertPulseScale: CGFloat = 1.0"))
        XCTAssertTrue(src.contains("@State private var sonarOpacity: Double = 0"))
        XCTAssertTrue(src.contains("@State private var activeAlertPulseID: Int = 0"))
        XCTAssertTrue(src.contains(".strokeBorder(ColorTokens.accent.opacity(sonarOpacity), lineWidth: 1.5)"))
        XCTAssertTrue(src.contains(".frame(width: MotionTokens.sonarBaseDiameter, height: MotionTokens.sonarBaseDiameter)"))
        XCTAssertTrue(sonarBlock(in: src).contains(".frame(width: GeometryTokens.widgetBaseSize.width, height: GeometryTokens.widgetBaseSize.height, alignment: .center)"))
        XCTAssertTrue(src.contains(".onChange(of: alertPulseID)"))
        XCTAssertTrue(src.contains("runNewAlertPulse()"))
        XCTAssertTrue(src.contains("guard activeAlertPulseID == pulseID, alertPulseGeneration == pulseGeneration else { return }"))
    }

    func test_widgetIconViewSource_quietHoursSuppressesNewAlertPulse() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("guard alertPulseID > 0, alertPulseID != activeAlertPulseID, !quietHoursEnabled else { return }"))
    }

    func test_widgetIconViewSource_cancelsAlertPulseWhenQuietHoursChanges() {
        let src = readWidgetIconViewSource()
        let block = onChangeBlock(for: ".onChange(of: quietHoursEnabled)", in: src)

        XCTAssertTrue(block.contains("resetAlertPulse()"))
        XCTAssertTrue(block.contains("restartIdleAnimation()"))
    }

    func test_widgetIconViewSource_quietHoursSuppressesIdleAndKeepsPendingBadge() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("var quietHoursEnabled: Bool = false"))
        XCTAssertTrue(src.contains("guard !quietHoursEnabled else { return }"))
        XCTAssertTrue(src.contains("if pendingCount >= 2 {"))
        XCTAssertTrue(src.contains("quietHoursEnabled ? 1.0"))
        XCTAssertFalse(src.contains("else if quietHoursEnabled {"))
        // Badge now uses HTML-proto accent-dark fill (#B8492C) with a Quiet-mode gray (#6B6B75).
        XCTAssertTrue(src.contains("Color(red: 0x6B/255, green: 0x6B/255, blue: 0x75/255)"))
        XCTAssertTrue(src.contains(": ColorTokens.accentDark"))
        XCTAssertFalse(src.contains(#"Text("Zzz")"#))
    }

    func test_widgetIconViewSource_keepsPendingBadgeInsidePanelBounds() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("private static let badgeOffset = CGSize(width: -2, height: 2)"))
        XCTAssertTrue(src.contains(".offset(x: Self.badgeOffset.width, y: Self.badgeOffset.height)"))
        XCTAssertTrue(src.contains(".font(.system(size: 10.5))"))
        XCTAssertTrue(src.contains(".padding(.horizontal, 5)"))
        XCTAssertTrue(src.contains(".frame(minWidth: 18, minHeight: 18)"))
        XCTAssertFalse(src.contains("private static let badgeOffset = CGSize(width: 0, height: 0)"))
        XCTAssertFalse(src.contains(".font(.system(size: 11, weight: .semibold))"))
        XCTAssertFalse(src.contains("let ringColor"))
        XCTAssertFalse(src.contains("colorScheme == .dark"))
        XCTAssertFalse(src.contains("Color.black.opacity(0.55)"))
        XCTAssertFalse(src.contains("Color.white.opacity(0.85)"))
        XCTAssertFalse(src.contains(".padding(.horizontal, 4.5)"))
        XCTAssertFalse(src.contains(".frame(minWidth: 17, minHeight: 17)"))
        XCTAssertFalse(src.contains(".stroke(ringColor, lineWidth: 1)"))
        XCTAssertFalse(src.contains(".stroke(ringColor, lineWidth: 2)"))
        XCTAssertFalse(src.contains(".stroke(ringColor, lineWidth: 1.5)"))
        XCTAssertFalse(src.contains(".offset(x: 5, y: -6)"))
    }

    func test_widgetIconViewSource_badgeShowsTotalPendingSessionCount() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains(#"Text("+\(pendingCount)")"#))
        XCTAssertFalse(src.contains("pendingCount - 1"))
    }

    func test_widgetIconViewSource_replacesBadgeWithZeldaHeartsOnlyForZelda() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("if widgetIconStyle == .zelda {"))
        XCTAssertTrue(src.contains("zeldaHeartBadgeView"))
        XCTAssertTrue(src.contains("zeldaHeartOverflowText"))
        XCTAssertTrue(src.contains("zeldaHeartFrameName"))
        XCTAssertTrue(src.contains(#"Text("+\(pendingCount - 3)")"#))
        XCTAssertTrue(src.contains("} else if pendingCount >= 2 {"))
        XCTAssertTrue(src.contains("if pendingCount >= 2 {"))
        XCTAssertTrue(src.contains("badgeView"))
    }

    func test_widgetIconViewSource_wiresZeldaIdleAndAlertFrames() {
        let src = readWidgetIconViewSource()
        let frameSource = readWidgetIconStyleSource()

        XCTAssertTrue(src.contains("ZeldaFrame.idleFrames"))
        XCTAssertTrue(src.contains("ZeldaFrame.alertFrames(side: widgetSide, effect: alertEffect)"))
        XCTAssertTrue(frameSource.contains(#""zelda_frame_00""#))
        XCTAssertTrue(frameSource.contains(#""zelda_frame_01""#))
        XCTAssertTrue(frameSource.contains(#""zelda_frame_02""#))
        XCTAssertTrue(frameSource.contains(#""zelda_frame_03""#))
        XCTAssertTrue(frameSource.contains(#""zelda_frame_04_heal""#))
        XCTAssertTrue(frameSource.contains(#""zelda_frame_04_hit""#))
        XCTAssertTrue(src.contains("ZeldaFrame.pickerSubdirectory(side: widgetSide)"))
        XCTAssertTrue(src.contains("ZeldaFrame.alertFrameDurationMultiplier(frameName: frameName)"))
        XCTAssertFalse(frameSource.contains(#""zelda_frame_05""#))
        XCTAssertFalse(frameSource.contains(#""zelda_frame_06""#))
        XCTAssertFalse(frameSource.contains(#""zelda_frame_07_heal""#))
        XCTAssertFalse(frameSource.contains(#""zelda_frame_07_hit""#))
    }

    func test_floatingWidgetWindowControllerPassesWidgetSideAndAlertEffectToIconView() {
        let src = readFloatingWidgetWindowControllerSource()

        XCTAssertTrue(src.contains("widgetSide: store.widgetCorner.widgetSide"))
        XCTAssertTrue(src.contains("alertEffect: currentAlertEffect"))
        XCTAssertTrue(src.contains("currentAlertEffect = SettingsStore.shared.zeldaAlertEffect"))
        XCTAssertFalse(src.contains("currentAlertEffect = .heal"))
    }

    func test_widgetIconViewSource_usesDoubleSizeZeldaIconAndHearts() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("private static let zeldaGlyphSize = CGSize(width: 92, height: 92)"))
        XCTAssertTrue(src.contains("private static let claudeGlyphSize = CGSize(width: 46, height: 46)"))
        XCTAssertTrue(src.contains("private static let zeldaGlyphOffset = CGSize(width: 0, height: 18)"))
        XCTAssertTrue(src.contains("private static let zeldaHeartOffset = CGSize(width: -1, height: -18)"))
        XCTAssertTrue(src.contains("widgetIconStyle == .zelda ? Self.zeldaGlyphOffset : Self.fixedGlyphOffset"))
        XCTAssertTrue(src.contains(".frame(width: glyphSize.width, height: glyphSize.height)"))
        XCTAssertTrue(src.contains(".frame(width: 45, height: 24)"))
        guard
            let overflowRange = src.range(of: "private var zeldaHeartOverflowText: some View"),
            let accessibilityRange = src.range(of: "private var widgetAccessibilityLabel: String")
        else {
            XCTFail("WidgetIconView must define zeldaHeartOverflowText before widgetAccessibilityLabel")
            return
        }
        let overflowSource = String(src[overflowRange.lowerBound..<accessibilityRange.lowerBound])
        XCTAssertTrue(overflowSource.contains(#"Text("+\(pendingCount - 3)")"#))
        XCTAssertTrue(overflowSource.contains(".font(.system(size: 12, weight: .bold))"))
        XCTAssertTrue(overflowSource.contains(".foregroundStyle(.black)"))
        XCTAssertFalse(overflowSource.contains(".padding(.horizontal, 5)"))
        XCTAssertFalse(overflowSource.contains(".frame(minWidth: 22, minHeight: 19)"))
        XCTAssertFalse(overflowSource.contains(".background(Capsule(style: .continuous).fill(ColorTokens.accentDark))"))
        XCTAssertFalse(overflowSource.contains(".offset(x: 11, y: 0)"))
    }

    func test_widgetIconViewSource_keepsGlyphPositionFixedWhenPendingBadgeIsVisible() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("private static let fixedGlyphOffset = CGSize(width: 0, height: 8)"))
        XCTAssertTrue(src.contains("x: glyphOffset.width,"))
        XCTAssertTrue(src.contains("y: (quietHoursEnabled ? 0 : bounceValue.translateY) + glyphOffset.height"))
        XCTAssertFalse(src.contains("pendingBadgeGlyphOffset"))
        XCTAssertFalse(src.contains("badgeClearanceGlyphOffset"))
    }

    func test_widgetIconViewAccessibilityLabel_announcesQuietHoursState() {
        let src = readWidgetIconViewSource()

        guard let helperRange = src.range(of: "private var widgetAccessibilityLabel: String") else {
            XCTFail("WidgetIconView must define widgetAccessibilityLabel")
            return
        }

        let helperSource = String(src[helperRange.lowerBound...])
        XCTAssertTrue(
            helperSource.contains(#"let sessionCount = pendingCount == 1 ? "1 pending session" : "\(pendingCount) pending sessions""#),
            "Widget accessibility label must keep announcing the pending session count"
        )
        XCTAssertTrue(
            helperSource.contains(#"let quietSuffix = quietHoursEnabled ? ". Quiet Hours" : """#),
            "Quiet Hours marker must be announced by the widget accessibility label"
        )
        XCTAssertTrue(
            helperSource.contains(#"return "Claude alert. \(sessionCount)\(quietSuffix)""#),
            "Widget accessibility label must include the quiet-hours suffix in its returned value"
        )
        XCTAssertTrue(src.contains(".accessibilityLabel(widgetAccessibilityLabel)"))
    }

    private func readWidgetIconViewSource(_ thisFile: StaticString = #filePath) -> String {
        let here = URL(fileURLWithPath: "\(thisFile)")
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/WidgetIconView.swift")
        guard let data = try? String(contentsOf: target, encoding: .utf8) else {
            XCTFail("Could not read App/WidgetIconView.swift at \(target.path)")
            return ""
        }
        return data
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

    private func readWidgetIconStyleSource(_ thisFile: StaticString = #filePath) -> String {
        let here = URL(fileURLWithPath: "\(thisFile)")
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/WidgetIconStyle.swift")
        guard let data = try? String(contentsOf: target, encoding: .utf8) else {
            XCTFail("Could not read App/WidgetIconStyle.swift at \(target.path)")
            return ""
        }
        return data
    }

    private func sonarBlock(in source: String) -> String {
        guard
            let start = source.range(of: "if sonarOpacity > 0, !quietHoursEnabled"),
            let end = source.range(of: #"Image("ClaudeCodeIcon")"#, range: start.upperBound..<source.endIndex)
        else {
            return ""
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }

    private func onChangeBlock(for marker: String, in source: String) -> String {
        guard
            let start = source.range(of: marker),
            let end = source.range(of: ".onChange", range: start.upperBound..<source.endIndex)
        else {
            return ""
        }
        return String(source[start.lowerBound..<end.lowerBound])
    }
}
