// ClaudeAlertBotTests/SettingsViewTests.swift — locked copy regression guards for the
// SettingsView namespace (constants + label helpers) and source-level audits of the
// MenuBarExtra settings surface in ClaudeAlertBotApp.swift.
import XCTest
@testable import ClaudeAlertBot

@MainActor
final class SettingsViewTests: XCTestCase {
    func test_settingsCopy_staticTextContract() {
        XCTAssertEqual(SettingsView.thresholdHeading, "알림 임계값")
        XCTAssertEqual(SettingsView.thresholdCaption, "이 시간 이상 걸린 작업만 알려요")
        XCTAssertEqual(SettingsView.soundHeading, "사운드")
        XCTAssertEqual(SettingsView.soundToggleLabel, "알림 사운드 재생")
        XCTAssertEqual(SettingsView.quietHoursHeading, "Quiet Hours")
        XCTAssertEqual(SettingsView.quietHoursToggleLabel, "Quiet Hours")
        XCTAssertEqual(SettingsView.idleAnimationHeading, "Idle Animation")
        XCTAssertEqual(SettingsView.idleAnimationLabel, "Animation")
        XCTAssertEqual(SettingsView.themeHeading, "Theme")
        XCTAssertEqual(SettingsView.themeLabel, "Appearance")
        XCTAssertEqual(SettingsView.reduceMotionHeading, "Reduce Motion")
        XCTAssertEqual(SettingsView.reduceMotionLabel, "Mode")
        XCTAssertEqual(SettingsView.startupHeading, "Startup")
        XCTAssertEqual(SettingsView.launchAtLoginToggleLabel, "Open at Login")
        XCTAssertEqual(SettingsView.widgetPositionHeading, "Widget Position")
        XCTAssertEqual(SettingsView.cornerLabel, "Corner")
        XCTAssertEqual(SettingsView.offsetXLabel, "Horizontal Offset")
        XCTAssertEqual(SettingsView.offsetYLabel, "Vertical Offset")
        XCTAssertEqual(SettingsView.mutedProjectsHeading, "Muted Projects")
        XCTAssertEqual(SettingsView.unmuteButtonLabel, "Unmute")
        XCTAssertEqual(SettingsView.testButtonLabel, "테스트 알림 보내기")

        let labels = WidgetCorner.allCases.map(SettingsView.widgetCornerLabel)
        XCTAssertEqual(labels, ["Top Left", "Top Right", "Bottom Left", "Bottom Right"])
    }

    // MARK: - D3-15 / D3-19 SET-05 copy lock (T-COPY-DRIFT-01)

    func test_settingsCopy_connectionStatusContract() {
        XCTAssertEqual(SettingsView.connectionTestHeading, "iTerm2 연결",
                       "D3-15: section header stays Korean for tone consistency with Phase 2 sections")
        XCTAssertEqual(SettingsView.connectionTestLabel, "iTerm2 연결 테스트",
                       "D3-15: button label is Korean to match testButtonLabel tone")
        XCTAssertEqual(SettingsView.connectionTestSuccessFmt, "Connected at %@",
                       "D3-19: success status label minimal English; %@ = HH:mm; no decoration prefix")
        XCTAssertEqual(SettingsView.iTermNotRunningLabel, "iTerm2 is not running",
                       "D3-19: iTermNotRunning status label minimal English")
        XCTAssertEqual(SettingsView.connectionDeniedLabel, "Automation permission denied",
                       "D3-19: permission-denied status label minimal English")
    }

    func test_idleAnimationLabels_areMinimalEnglish() {
        XCTAssertEqual(SettingsView.idleAnimationName(.bounce), "Bounce")
        XCTAssertEqual(SettingsView.idleAnimationName(.heart), "Heart")
        XCTAssertEqual(SettingsView.idleAnimationName(.ring), "Ring")
        XCTAssertEqual(SettingsView.idleAnimationName(.roam), "Roam")
        XCTAssertEqual(SettingsView.idleAnimationName(.rage), "🤬 Rage")
        XCTAssertEqual(SettingsView.idleAnimationName(.magic), "Magic")
    }

    func test_widgetIconStyle_allCasesIncludesZeldaAndDefaultStaysClaude() {
        XCTAssertEqual(WidgetIconStyle.default, .claude)
        XCTAssertTrue(WidgetIconStyle.allCases.contains(.claude))
        XCTAssertTrue(WidgetIconStyle.allCases.contains(.zelda))
    }

    func test_widgetIconStyleLabels_areMinimalEnglish() {
        XCTAssertEqual(SettingsView.widgetIconStyleName(.claude), "Claude")
        XCTAssertEqual(SettingsView.widgetIconStyleName(.zelda), "Zelda")
    }

    func test_zeldaFramePaths_matchWidgetSideAndEffect() {
        XCTAssertEqual(ZeldaFrame.idleFrames, ["zelda_frame_00", "zelda_frame_01"])
        XCTAssertEqual(ZeldaFrame.alertFrames(side: .left, effect: .heal),
                       ["zelda_frame_02", "zelda_frame_03", "zelda_frame_04_heal"])
        XCTAssertEqual(ZeldaFrame.alertFrames(side: .left, effect: .hit),
                       ["zelda_frame_02", "zelda_frame_03", "zelda_frame_04_hit"])
        XCTAssertEqual(ZeldaFrame.alertFrames(side: .right, effect: .heal),
                       ["zelda_frame_02", "zelda_frame_03", "zelda_frame_04_heal"])
        XCTAssertEqual(ZeldaFrame.alertFrames(side: .right, effect: .hit),
                       ["zelda_frame_02", "zelda_frame_03", "zelda_frame_04_hit"])
        XCTAssertEqual(ZeldaFrame.characterSubdirectory(side: .left), "adventure-widget/character/left")
        XCTAssertEqual(ZeldaFrame.characterSubdirectory(side: .right), "adventure-widget/character/right")
        XCTAssertEqual(ZeldaFrame.alertFrameDurationMultiplier(frameName: "zelda_frame_04_heal"), 1.5)
        XCTAssertEqual(ZeldaFrame.alertFrameDurationMultiplier(frameName: "zelda_frame_04_hit"), 1.5)
        XCTAssertEqual(ZeldaFrame.alertFrameDurationMultiplier(frameName: "zelda_frame_02"), 1.0)
    }

    func test_zeldaAlertEffectLabels_areMinimalEnglish() {
        XCTAssertEqual(WidgetAlertEffect.default, .heal)
        XCTAssertEqual(WidgetAlertEffect.allCases, [.heal, .hit])
        XCTAssertEqual(SettingsView.zeldaAlertEffectName(.heal), "Heal")
        XCTAssertEqual(SettingsView.zeldaAlertEffectName(.hit), "Hit")
    }

    func test_menuBarAnimationPickerBranchesByIconStyle() {
        let appSource = readClaudeAlertBotAppSource()

        XCTAssertTrue(appSource.contains("if store.widgetIconStyle == .zelda {"))
        XCTAssertTrue(appSource.contains("Picker(SettingsView.idleAnimationLabel, selection: store.zeldaAlertEffectBinding)"))
        XCTAssertTrue(appSource.contains("ForEach(WidgetAlertEffect.allCases, id: \\.self)"))
        XCTAssertTrue(appSource.contains("Text(SettingsView.zeldaAlertEffectName(effect)).tag(effect)"))
        XCTAssertTrue(appSource.contains("} else {"))
        XCTAssertTrue(appSource.contains("Picker(SettingsView.idleAnimationLabel, selection: store.idleAnimationBinding)"))
        XCTAssertTrue(appSource.contains("ForEach(menuIdleAnimations, id: \\.self)"))
    }

    func test_themeModeLabels_areMinimalEnglish() {
        XCTAssertEqual(SettingsView.themeModeName(.system), "System")
        XCTAssertEqual(SettingsView.themeModeName(.light), "Light")
        XCTAssertEqual(SettingsView.themeModeName(.dark), "Dark")
    }

    func test_reduceMotionPreferenceLabels_areMinimalEnglish() {
        XCTAssertEqual(SettingsView.reduceMotionPreferenceName(.system), "System")
        XCTAssertEqual(SettingsView.reduceMotionPreferenceName(.reduced), "Reduced")
    }

    func test_menuBarSettingsExposeInlineControls() {
        let appSource = readClaudeAlertBotAppSource()
        let popoverSource = readWidgetPopoverControllerSource()

        XCTAssertFalse(appSource.contains("SettingsWindowPresenter"))
        XCTAssertFalse(appSource.contains("@Environment(\\.openSettings)"))
        XCTAssertFalse(popoverSource.contains("SettingsWindowPresenter"))
        XCTAssertFalse(popoverSource.contains(#"NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)"#))

        XCTAssertTrue(appSource.contains("Menu(\"Notification\")"))
        XCTAssertTrue(appSource.contains("Toggle(Self.menuSoundToggleLabel, isOn: $store.soundEnabled)"))
        XCTAssertTrue(appSource.contains("Toggle(Self.menuQuietHoursToggleLabel, isOn: $store.quietHoursEnabled)"))
        XCTAssertTrue(appSource.contains("Menu(Self.menuAlertDetailsHeading)"))
        XCTAssertTrue(appSource.contains("Menu(\"Style\")"))
        XCTAssertTrue(appSource.contains("Picker(SettingsView.idleAnimationLabel, selection: store.zeldaAlertEffectBinding)"))
        XCTAssertTrue(appSource.contains("Picker(SettingsView.idleAnimationLabel, selection: store.idleAnimationBinding)"))
        XCTAssertTrue(appSource.contains("Picker(SettingsView.themeLabel, selection: store.themeModeBinding)"))
        XCTAssertTrue(appSource.contains("Picker(SettingsView.reduceMotionLabel, selection: store.reduceMotionPreferenceBinding)"))
        XCTAssertTrue(appSource.contains("Toggle(Self.menuLaunchAtLoginLabel, isOn: $store.launchAtLoginEnabled)"))
        XCTAssertTrue(appSource.contains("Menu(Self.menuWidgetPositionHeading)"))
        XCTAssertTrue(appSource.contains("Menu(Self.menuConnectionTestHeading)"))
    }

    func test_menuBarSettings_replacesSteppersWithPresetMenus() {
        let appSource = readClaudeAlertBotAppSource()

        XCTAssertFalse(appSource.contains("Stepper(\\(store.thresholdSeconds)초\", value: $store.thresholdSeconds"))
        XCTAssertFalse(appSource.contains("Stepper(\\(SettingsView.offsetXLabel): \\(store.offsetX) pt\", value: $store.offsetX"))
        XCTAssertFalse(appSource.contains("Stepper(\\(SettingsView.offsetYLabel): \\(store.offsetY) pt\", value: $store.offsetY"))
        XCTAssertTrue(appSource.contains("Direct (0s)"))
        XCTAssertTrue(appSource.contains("struct ThresholdPreset"))
        XCTAssertTrue(appSource.contains("struct OffsetPreset"))
        XCTAssertTrue(appSource.contains(".init(label: \"Direct (0s)\", seconds: 0)"))
        XCTAssertTrue(appSource.contains(".init(label: \"Close to edge (8 pt)\", value: 8)"))
        XCTAssertTrue(appSource.contains("private static let menuOffsetXLabel = \"Horizontal Offset\""))
        XCTAssertTrue(appSource.contains("private static let menuOffsetYLabel = \"Vertical Offset\""))
        XCTAssertTrue(appSource.contains("private static let menuSoundToggleLabel = \"Play notification sound\""))
        XCTAssertTrue(appSource.contains("private static let menuQuietHoursToggleLabel = \"Quiet Hours\""))
        XCTAssertTrue(appSource.contains("private static let menuThresholdHeading = \"Notification Threshold\""))
        XCTAssertTrue(appSource.contains("private static let menuAlertDetailsHeading = \"Alert Details\""))
        XCTAssertTrue(appSource.contains("private static let menuAlertDetailsNoneLabel = \"None\""))
        XCTAssertTrue(appSource.contains("private static let menuAlertDetailsLastOutputLabel = \"Last Output\""))
        XCTAssertTrue(appSource.contains("private static let menuWidgetPositionHeading = \"Widget Position\""))
        XCTAssertTrue(appSource.contains("private static let menuConnectionTestHeading = \"iTerm2 Connection\""))
        XCTAssertTrue(appSource.contains("Image(systemName: \"checkmark\")"))
    }

    func test_menuBarAlertDetailsMenu_wiresLastOutputSetting() {
        let appSource = readClaudeAlertBotAppSource()

        XCTAssertTrue(appSource.contains("store.detailShowLastOutput = false"))
        XCTAssertTrue(appSource.contains("store.detailShowLastOutput = true"))
        XCTAssertTrue(appSource.contains("if !store.detailShowLastOutput"))
        XCTAssertTrue(appSource.contains("if store.detailShowLastOutput"))
    }

    /// D2-36 — the Settings-window denied banner was removed with the Settings scene,
    /// so the menu must carry a persistent denied status + System Settings deep-link.
    func test_menuBarConnectionMenu_showsPersistentDeniedStatus() {
        let appSource = readClaudeAlertBotAppSource()

        XCTAssertTrue(appSource.contains("} else if store.applescriptPermission == .denied {"))
        XCTAssertTrue(appSource.contains("if store.applescriptPermission == .denied {"))
        XCTAssertTrue(appSource.contains("private static let menuOpenAutomationSettingsLabel = \"Open Automation Settings…\""))
        XCTAssertTrue(appSource.contains("PermissionDeepLink.openAutomationPreferences()"))
    }

    private func readClaudeAlertBotAppSource(_ thisFile: StaticString = #filePath) -> String {
        let here = URL(fileURLWithPath: "\(thisFile)")
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/ClaudeAlertBotApp.swift")
        guard let data = try? String(contentsOf: target, encoding: .utf8) else {
            XCTFail("Could not read App/ClaudeAlertBotApp.swift at \(target.path)")
            return ""
        }
        return data
    }

    private func readWidgetPopoverControllerSource(_ thisFile: StaticString = #filePath) -> String {
        let here = URL(fileURLWithPath: "\(thisFile)")
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/WidgetPopoverController.swift")
        guard let data = try? String(contentsOf: target, encoding: .utf8) else {
            XCTFail("Could not read App/WidgetPopoverController.swift at \(target.path)")
            return ""
        }
        return data
    }
}
