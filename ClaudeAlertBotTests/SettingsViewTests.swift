// ClaudeAlertBotTests/SettingsViewTests.swift — Phase 2 plan 02-10.
// Locked Korean copy regression guards for PermissionBannerView (Task 1) and SettingsView (Task 2).
// UI-SPEC §"Permission Banner" + §"Settings Window" + §"Copywriting Contract".
import XCTest
@testable import ClaudeAlertBot

@MainActor
final class SettingsViewTests: XCTestCase {
    // MARK: - PermissionBannerView (Task 1)
    func test_bannerCopy_locked() {
        XCTAssertEqual(PermissionBannerView.headlineCopy, "자동화 권한이 꺼져 있어요")
        XCTAssertEqual(PermissionBannerView.bodyCopy, "이미 보고 있는 터미널에서도 알림이 뜰 수 있습니다.")
        XCTAssertEqual(PermissionBannerView.buttonCopy, "시스템 설정 열기")
    }

    func test_accessibilityBannerCopy_locked() {
        XCTAssertEqual(AccessibilityPermissionBannerView.headlineCopy, "손쉬운 사용 권한이 필요해요")
        XCTAssertEqual(AccessibilityPermissionBannerView.bodyCopy, "전체화면 Space의 iTerm 창으로 점프하려면 필요합니다.")
        XCTAssertEqual(AccessibilityPermissionBannerView.buttonCopy, "시스템 설정 열기")
        XCTAssertFalse(AccessibilityPermissionBannerView.bodyCopy.contains("재시작"))
    }

    func test_accessibilityBannerButtonRequestsCurrentAppTrustBeforeOpeningSettings() {
        let src = readPermissionBannerViewSource()
        guard let bannerStart = src.range(of: "struct AccessibilityPermissionBannerView") else {
            XCTFail("Could not find AccessibilityPermissionBannerView")
            return
        }
        let bannerSource = String(src[bannerStart.lowerBound...])

        XCTAssertTrue(bannerSource.contains("AccessibilityRaiser.requestTrust()"))
        XCTAssertTrue(bannerSource.contains("PermissionDeepLink.openAccessibilityPreferences()"))
    }
    // (Task 2 appends more tests below this point)
}

// MARK: - SettingsView (Task 2)
extension SettingsViewTests {
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
        XCTAssertEqual(ZeldaFrame.pickerSubdirectory(side: .left), "zelda/picker/left")
        XCTAssertEqual(ZeldaFrame.pickerSubdirectory(side: .right), "zelda/picker/right")
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

    func test_themeSection_wiresPickerToStore() {
        let src = readSettingsViewSource()

        XCTAssertTrue(src.contains("Picker(Self.themeLabel, selection: store.themeModeBinding)"))
        XCTAssertTrue(src.contains("ForEach(ThemeMode.allCases, id: \\.self)"))
        XCTAssertTrue(src.contains("Text(Self.themeModeName(mode)).tag(mode)"))
    }

    func test_themeModeLabels_areMinimalEnglish() {
        XCTAssertEqual(SettingsView.themeModeName(.system), "System")
        XCTAssertEqual(SettingsView.themeModeName(.light), "Light")
        XCTAssertEqual(SettingsView.themeModeName(.dark), "Dark")
    }

    func test_reduceMotionSection_wiresPickerToStore() {
        let src = readSettingsViewSource()

        XCTAssertTrue(src.contains("Picker(Self.reduceMotionLabel, selection: store.reduceMotionPreferenceBinding)"))
        XCTAssertTrue(src.contains("ForEach(ReduceMotionPreference.allCases, id: \\.self)"))
        XCTAssertTrue(src.contains("Text(Self.reduceMotionPreferenceName(preference)).tag(preference)"))
    }

    func test_reduceMotionPreferenceLabels_areMinimalEnglish() {
        XCTAssertEqual(SettingsView.reduceMotionPreferenceName(.system), "System")
        XCTAssertEqual(SettingsView.reduceMotionPreferenceName(.reduced), "Reduced")
    }

    func test_startupSection_wiresToggleToStoreAndLoginItemController() {
        let src = readSettingsViewSource()

        XCTAssertTrue(src.contains("Toggle(Self.launchAtLoginToggleLabel, isOn: $store.launchAtLoginEnabled)"))
        XCTAssertTrue(src.contains(".onChange(of: store.launchAtLoginEnabled)"))
        XCTAssertTrue(src.contains("LoginItemController.applyFromSettings(enabled: enabled)"))
    }

    func test_menuBarSettingsExposeInlineControls() {
        let appSource = readClaudeAlertBotAppSource()
        let popoverSource = readWidgetPopoverControllerSource()

        XCTAssertFalse(appSource.contains("Button(\"Settings…\") { SettingsWindowPresenter.open() }"))
        XCTAssertFalse(appSource.contains("@Environment(\\.openSettings)"))
        XCTAssertFalse(popoverSource.contains("onOpenSettings: {\n                SettingsWindowPresenter.open()\n            }"))
        XCTAssertFalse(popoverSource.contains(#"NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)"#))

        XCTAssertTrue(appSource.contains("Menu(\"Notification\")"))
        XCTAssertTrue(appSource.contains("Toggle(Self.menuSoundToggleLabel, isOn: $store.soundEnabled)"))
        XCTAssertTrue(appSource.contains("Toggle(Self.menuQuietHoursToggleLabel, isOn: $store.quietHoursEnabled)"))
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
        XCTAssertTrue(appSource.contains("private static let menuWidgetPositionHeading = \"Widget Position\""))
        XCTAssertTrue(appSource.contains("private static let menuConnectionTestHeading = \"iTerm2 Connection\""))
        XCTAssertTrue(appSource.contains("Image(systemName: \"checkmark\")"))
    }

    func test_settingsWindowPresenterBringsSettingsWindowToFront() {
        let src = readSettingsWindowPresenterSource()

        XCTAssertTrue(src.contains("NSApp.activate(ignoringOtherApps: true)"))
        XCTAssertTrue(src.contains(#"NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)"#))
        XCTAssertTrue(src.contains("DispatchQueue.main.async"))
        XCTAssertTrue(src.contains("window.makeKeyAndOrderFront(nil)"))
        XCTAssertTrue(src.contains("window.orderFrontRegardless()"))
        XCTAssertTrue(src.contains("!(window is NSPanel)"))
        XCTAssertTrue(src.contains("for window in NSApp.windows where !(window is NSPanel)"))
        XCTAssertFalse(src.contains("window.isVisible && !(window is NSPanel)"))
    }

    func test_settingsViewRefreshesAccessibilityPermissionWhenAppBecomesActive() {
        let src = readSettingsViewSource()

        XCTAssertTrue(src.contains("@State private var accessibilityTrusted = true"))
        XCTAssertTrue(src.contains("if hasCheckedAccessibilityTrust && !accessibilityTrusted"))
        XCTAssertTrue(src.contains(".onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))"))
        XCTAssertTrue(src.contains("refreshAccessibilityTrust()"))
    }

    func test_settingsViewRechecksAutomationPermissionBeforeShowingDeniedBanner() {
        let src = readSettingsViewSource()

        XCTAssertTrue(src.contains("@State private var isCheckingAutomationPermission = false"))
        XCTAssertTrue(src.contains("if store.applescriptPermission == .denied && !isCheckingAutomationPermission"))
        XCTAssertTrue(src.contains("refreshAutomationPermissionIfNeeded()"))
        XCTAssertTrue(src.contains("guard store.applescriptPermission != .granted else"))
        XCTAssertTrue(src.contains("await AppleScriptHelper.shared.triggerPermissionPrompt()"))
    }

    func test_settingsViewShowsAccessibilityBannerOnlyAfterTrustCheck() {
        let src = readSettingsViewSource()

        XCTAssertTrue(src.contains("@State private var hasCheckedAccessibilityTrust = false"))
        XCTAssertTrue(src.contains("if hasCheckedAccessibilityTrust && !accessibilityTrusted"))
        XCTAssertTrue(src.contains("hasCheckedAccessibilityTrust = true"))
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

    private func readPermissionBannerViewSource(_ thisFile: StaticString = #filePath) -> String {
        let here = URL(fileURLWithPath: "\(thisFile)")
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/PermissionBannerView.swift")
        guard let data = try? String(contentsOf: target, encoding: .utf8) else {
            XCTFail("Could not read App/PermissionBannerView.swift at \(target.path)")
            return ""
        }
        return data
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

    private func readSettingsWindowPresenterSource(_ thisFile: StaticString = #filePath) -> String {
        let here = URL(fileURLWithPath: "\(thisFile)")
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/SettingsWindowPresenter.swift")
        guard let data = try? String(contentsOf: target, encoding: .utf8) else {
            XCTFail("Could not read App/SettingsWindowPresenter.swift at \(target.path)")
            return ""
        }
        return data
    }
}
