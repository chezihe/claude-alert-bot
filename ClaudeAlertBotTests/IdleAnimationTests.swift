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

    func test_widgetIconViewSource_quietHoursSuppressesIdleAndBadge() {
        let src = readWidgetIconViewSource()

        XCTAssertTrue(src.contains("var quietHoursEnabled: Bool = false"))
        XCTAssertTrue(src.contains("guard !quietHoursEnabled else { return }"))
        XCTAssertTrue(src.contains("if quietHoursEnabled {"))
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
}
