// ClaudeAlertBotTests/SettingsViewTests.swift — Phase 2 plan 02-10.
// Locked Korean copy regression guards for PermissionBannerView (Task 1) and SettingsView (Task 2).
// UI-SPEC §"Permission Banner" + §"Settings Window" + §"Copywriting Contract".
import XCTest
@testable import ClaudeAlertBot

@MainActor
final class SettingsViewTests: XCTestCase {
    // MARK: - PermissionBannerView (Task 1)
    func test_bannerCopy_headlineLocked() {
        XCTAssertEqual(PermissionBannerView.headlineCopy, "자동화 권한이 꺼져 있어요")
    }
    func test_bannerCopy_bodyLocked() {
        XCTAssertEqual(PermissionBannerView.bodyCopy, "이미 보고 있는 터미널에서도 알림이 뜰 수 있습니다.")
    }
    func test_bannerCopy_buttonLabelLocked() {
        XCTAssertEqual(PermissionBannerView.buttonCopy, "시스템 설정 열기")
    }
    // (Task 2 appends more tests below this point)
}
