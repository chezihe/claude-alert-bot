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

// MARK: - SettingsView (Task 2)
extension SettingsViewTests {
    func test_settingsCopy_thresholdSection() {
        XCTAssertEqual(SettingsView.thresholdHeading, "알림 임계값")
        XCTAssertEqual(SettingsView.thresholdCaption, "이 시간 이상 걸린 작업만 알려요")
    }
    func test_settingsCopy_soundSection() {
        XCTAssertEqual(SettingsView.soundHeading, "사운드")
        XCTAssertEqual(SettingsView.soundToggleLabel, "알림 사운드 재생")
    }
    func test_settingsCopy_widgetPositionSection() {
        XCTAssertEqual(SettingsView.widgetPositionHeading, "위젯 위치")
        XCTAssertEqual(SettingsView.cornerLabel, "코너")
        XCTAssertEqual(SettingsView.offsetXLabel, "가로 오프셋")
        XCTAssertEqual(SettingsView.offsetYLabel, "세로 오프셋")
    }
    func test_settingsCopy_testButtonLabel() {
        XCTAssertEqual(SettingsView.testButtonLabel, "테스트 알림 보내기")
    }
    func test_widgetCornerLabels_4Korean() {
        let labels = WidgetCorner.allCases.map(\.localizedLabel)
        XCTAssertEqual(labels, ["왼쪽 위", "오른쪽 위", "왼쪽 아래", "오른쪽 아래"])
    }
}
