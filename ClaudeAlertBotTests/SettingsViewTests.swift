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
    func test_settingsCopy_quietHoursSection() {
        XCTAssertEqual(SettingsView.quietHoursHeading, "Quiet Hours")
        XCTAssertEqual(SettingsView.quietHoursToggleLabel, "Quiet Hours")
    }
    func test_settingsCopy_idleAnimationSection() {
        XCTAssertEqual(SettingsView.idleAnimationHeading, "Idle Animation")
        XCTAssertEqual(SettingsView.idleAnimationLabel, "Animation")
    }
    func test_settingsCopy_widgetPositionSection() {
        XCTAssertEqual(SettingsView.widgetPositionHeading, "Widget Position")
        XCTAssertEqual(SettingsView.cornerLabel, "Corner")
        XCTAssertEqual(SettingsView.offsetXLabel, "Horizontal Offset")
        XCTAssertEqual(SettingsView.offsetYLabel, "Vertical Offset")
    }
    func test_settingsCopy_mutedProjectsSection() {
        XCTAssertEqual(SettingsView.mutedProjectsHeading, "Muted Projects")
        XCTAssertEqual(SettingsView.unmuteButtonLabel, "Unmute")
    }
    func test_settingsCopy_testButtonLabel() {
        XCTAssertEqual(SettingsView.testButtonLabel, "테스트 알림 보내기")
    }
    func test_widgetCornerLabels_4English() {
        let labels = WidgetCorner.allCases.map(SettingsView.widgetCornerLabel)
        XCTAssertEqual(labels, ["Top Left", "Top Right", "Bottom Left", "Bottom Right"])
    }

    // MARK: - D3-15 / D3-19 SET-05 copy lock (T-COPY-DRIFT-01)

    func test_settingsCopy_connectionTestHeading_isKorean() {
        XCTAssertEqual(SettingsView.connectionTestHeading, "iTerm2 연결",
                       "D3-15: section header stays Korean for tone consistency with Phase 2 sections")
    }

    func test_settingsCopy_connectionTestLabel_isKoreanVerbatim() {
        XCTAssertEqual(SettingsView.connectionTestLabel, "iTerm2 연결 테스트",
                       "D3-15: button label is Korean to match testButtonLabel tone")
    }

    func test_settingsCopy_connectionTestSuccessFmt_isMinimalEnglish() {
        XCTAssertEqual(SettingsView.connectionTestSuccessFmt, "Connected at %@",
                       "D3-19: success status label minimal English; %@ = HH:mm; no decoration prefix")
    }

    func test_settingsCopy_iTermNotRunningLabel_isMinimalEnglish() {
        XCTAssertEqual(SettingsView.iTermNotRunningLabel, "iTerm2 is not running",
                       "D3-19: iTermNotRunning status label minimal English")
    }

    func test_settingsCopy_connectionDeniedLabel_isMinimalEnglish() {
        XCTAssertEqual(SettingsView.connectionDeniedLabel, "Automation permission denied",
                       "D3-19: permission-denied status label minimal English")
    }

    // MARK: - WO-007 muted projects section contract (source-level audit)

    func test_mutedProjectsSection_usesActiveMutesRule() {
        let src = readSettingsViewSource()

        XCTAssertTrue(
            src.contains("MutedProjectsRules.activeMutes(store.mutedProjects, now: now)"),
            "WO-007: SettingsView must derive visible mutes through MutedProjectsRules.activeMutes"
        )
    }

    func test_mutedProjectsSection_wiresUnmuteButtonToStore() {
        let src = readSettingsViewSource()

        XCTAssertTrue(
            src.contains("store.unmute(project: entry.project)"),
            "WO-007: SettingsView Unmute button must call SettingsStore.unmute(project:)"
        )
    }

    func test_mutedProjectsSection_usesLockedCopy() {
        let src = readSettingsViewSource()

        XCTAssertTrue(src.contains(#"static let mutedProjectsHeading = "Muted Projects""#))
        XCTAssertTrue(src.contains(#"static let unmuteButtonLabel = "Unmute""#))
    }

    func test_quietHoursSection_wiresToggleToStore() {
        let src = readSettingsViewSource()

        XCTAssertTrue(src.contains("Toggle(Self.quietHoursToggleLabel, isOn: $store.quietHoursEnabled)"))
    }

    func test_idleAnimationSection_wiresPickerToStore() {
        let src = readSettingsViewSource()

        XCTAssertTrue(src.contains("Picker(Self.idleAnimationLabel, selection: store.idleAnimationBinding)"))
        XCTAssertTrue(src.contains("ForEach(IdleAnimation.allCases, id: \\.self)"))
        XCTAssertTrue(src.contains("Text(Self.idleAnimationName(animation)).tag(animation)"))
    }

    func test_idleAnimationLabels_areMinimalEnglish() {
        XCTAssertEqual(SettingsView.idleAnimationName(.bounce), "Bounce")
        XCTAssertEqual(SettingsView.idleAnimationName(.breathe), "Breathe")
    }

    func test_idleAnimationLabelsSource_includesRing() {
        let src = readSettingsViewSource()

        XCTAssertTrue(src.contains("case .ring: return \"Ring\""))
    }

    func test_idleAnimationLabelsSource_includesRoam() {
        let src = readSettingsViewSource()

        XCTAssertTrue(src.contains("case .roam: return \"Roam\""))
    }

    /// Resolve App/SettingsView.swift relative to this test file so source-level
    /// audits are independent of xcodebuild's working directory.
    private func readSettingsViewSource(_ thisFile: StaticString = #filePath) -> String {
        let here = URL(fileURLWithPath: "\(thisFile)")
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/SettingsView.swift")
        guard let data = try? String(contentsOf: target, encoding: .utf8) else {
            XCTFail("Could not read App/SettingsView.swift at \(target.path)")
            return ""
        }
        return data
    }
}
