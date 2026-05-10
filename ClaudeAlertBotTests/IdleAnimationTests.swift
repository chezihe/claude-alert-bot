// ClaudeAlertBotTests/IdleAnimationTests.swift — WO-012 idle animation selector contract.
import XCTest
@testable import ClaudeAlertBot

final class IdleAnimationTests: XCTestCase {

    func test_idleAnimation_defaultIsBreathe() {
        XCTAssertEqual(IdleAnimation.default, .breathe)
    }

    func test_idleAnimation_allCasesContainsBounceAndBreathe() {
        XCTAssertTrue(IdleAnimation.allCases.contains(.bounce))
        XCTAssertTrue(IdleAnimation.allCases.contains(.breathe))
    }

    func test_widgetIconViewSource_wiresBreatheBranch() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("case .breathe:"))
        XCTAssertTrue(src.contains("MotionTokens.breatheAnimation"))
    }

    func test_widgetIconViewSource_wiresBounceSquashScale() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("@State private var bounceScale: CGFloat = 1.0"))
        XCTAssertTrue(src.contains(".scaleEffect(quietHoursEnabled ? 1.0 : breatheScale * bounceScale * alertPulseScale)"))
        XCTAssertTrue(src.contains("bounceScale = 1.0"))
        XCTAssertTrue(src.contains("bounceScale = MotionTokens.bounceStretchScale"))
        XCTAssertTrue(src.contains("bounceScale = MotionTokens.bounceSquashScale"))
    }

    func test_floatingWidgetWindowController_passesSelectedIdleAnimationToIconView() {
        let src = readFloatingWidgetWindowControllerSource()

        XCTAssertTrue(src.contains("idleAnimation: SettingsStore.shared.idleAnimation"))
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
        XCTAssertTrue(restartBody.contains("bounceOffset = 0"))
        XCTAssertTrue(restartBody.contains("bounceScale = 1.0"))
        XCTAssertTrue(restartBody.contains("breatheScale = 1.0"))
        XCTAssertTrue(restartBody.contains("startIdleAnimation()"))
    }

    func test_widgetIconViewSource_restartsWhenReduceMotionChanges() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains(".onChange(of: reduceMotion)"))
        XCTAssertTrue(src.contains("restartIdleAnimation()"))
    }

    func test_widgetIconViewSource_runsNewAlertPulseWhenPulseIDChanges() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("var alertPulseID: Int = 0"))
        XCTAssertTrue(src.contains("@State private var alertPulseScale: CGFloat = 1.0"))
        XCTAssertTrue(src.contains("@State private var sonarOpacity: Double = 0"))
        XCTAssertTrue(src.contains("@State private var activeAlertPulseID: Int = 0"))
        XCTAssertTrue(src.contains(".onChange(of: alertPulseID)"))
        XCTAssertTrue(src.contains("runNewAlertPulse()"))
        XCTAssertTrue(src.contains("guard activeAlertPulseID == pulseID else { return }"))
    }

    func test_widgetIconViewSource_quietHoursSuppressesNewAlertPulse() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("guard alertPulseID > 0, alertPulseID != activeAlertPulseID, !quietHoursEnabled else { return }"))
    }

    func test_widgetIconViewSource_quietHoursSuppressesIdleAndKeepsPendingBadge() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("var quietHoursEnabled: Bool = false"))
        XCTAssertTrue(src.contains("guard !quietHoursEnabled else { return }"))
        XCTAssertTrue(src.contains("if pendingCount >= 2 {"))
        XCTAssertTrue(src.contains("if quietHoursEnabled {"))
        XCTAssertFalse(src.contains("else if quietHoursEnabled {"))
        XCTAssertTrue(src.contains("quietHoursEnabled ? Color(NSColor.systemGray) : Color(NSColor.systemRed)"))
        XCTAssertTrue(src.contains("y: pendingCount >= 2 ? 11 : -6"))
        XCTAssertTrue(src.contains(#"Text("Zzz")"#))
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
}
