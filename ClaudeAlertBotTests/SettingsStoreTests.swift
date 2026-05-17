// ClaudeAlertBotTests/SettingsStoreTests.swift
// WO-003 — UserDefaults persistence for widget corner settings.
import XCTest
import AppKit
@testable import ClaudeAlertBot

@MainActor
final class SettingsStoreTests: XCTestCase {
    func test_widgetCorner_defaultIsTopRight() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.widgetCorner, .topRight)
    }

    func test_widgetCorner_persistsAcrossInit() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsStore(defaults: defaults)
        first.widgetCorner = .bottomLeft

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.widgetCorner, .bottomLeft)
    }

    func test_quietHours_defaultIsOff() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)

        XCTAssertFalse(store.quietHoursEnabled)
    }

    func test_quietHours_persistsAcrossInit() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsStore(defaults: defaults)
        first.quietHoursEnabled = true

        let second = SettingsStore(defaults: defaults)
        XCTAssertTrue(second.quietHoursEnabled)
    }

    func test_idleAnimation_defaultIsBreathe() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.idleAnimation, .bounce)
    }

    func test_idleAnimation_persistsAcrossInit() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsStore(defaults: defaults)
        first.idleAnimation = .bounce

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.idleAnimation, .bounce)
    }

    func test_zeldaAlertEffect_defaultIsHeal() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.zeldaAlertEffect, .heal)
    }

    func test_zeldaAlertEffect_persistsAcrossInit() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsStore(defaults: defaults)
        first.zeldaAlertEffect = .hit

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.zeldaAlertEffect, .hit)
    }

    func test_widgetIconStyleChange_resetsAnimationSelectionsToIconDefaults() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.idleAnimation = .magic
        store.zeldaAlertEffect = .hit

        store.widgetIconStyle = .zelda

        XCTAssertEqual(store.idleAnimation, .bounce)
        XCTAssertEqual(store.zeldaAlertEffect, .heal)
    }

    func test_themeMode_defaultIsSystem() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.themeMode, .system)
    }

    func test_themeMode_persistsAcrossInit() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsStore(defaults: defaults)
        first.themeMode = .dark

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.themeMode, .dark)
    }

    func test_themeModeAppearanceMapping() {
        XCTAssertNil(ThemeMode.system.nsAppearance)
        XCTAssertEqual(ThemeMode.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(ThemeMode.dark.nsAppearance?.name, .darkAqua)
    }

    func test_reduceMotionPreference_defaultIsSystem() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)

        XCTAssertEqual(store.reduceMotionPreference, .system)
    }

    func test_reduceMotionPreference_persistsAcrossInit() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsStore(defaults: defaults)
        first.reduceMotionPreference = .reduced

        let second = SettingsStore(defaults: defaults)
        XCTAssertEqual(second.reduceMotionPreference, .reduced)
    }

    func test_reduceMotionPreferenceEffectiveMotion_respectsSystemAndManualReduce() {
        XCTAssertFalse(ReduceMotionPreference.system.effectiveReduceMotion(systemReduceMotion: false))
        XCTAssertTrue(ReduceMotionPreference.system.effectiveReduceMotion(systemReduceMotion: true))
        XCTAssertTrue(ReduceMotionPreference.reduced.effectiveReduceMotion(systemReduceMotion: false))
        XCTAssertTrue(ReduceMotionPreference.reduced.effectiveReduceMotion(systemReduceMotion: true))
    }

    func test_launchAtLogin_defaultIsOff() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)

        XCTAssertFalse(store.launchAtLoginEnabled)
    }

    func test_launchAtLogin_persistsAcrossInit() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsStore(defaults: defaults)
        first.launchAtLoginEnabled = true

        let second = SettingsStore(defaults: defaults)
        XCTAssertTrue(second.launchAtLoginEnabled)
    }

    func test_appDelegateSourceAppliesThemeOnLaunchAndSettingsChange() {
        let src = readAppDelegateSource()

        XCTAssertTrue(src.contains("private var themeCancellable: AnyCancellable?"))
        XCTAssertTrue(src.contains("applyThemeMode(SettingsStore.shared.themeMode)"))
        XCTAssertTrue(src.contains("themeCancellable = SettingsStore.shared.objectWillChange.sink"))
        XCTAssertTrue(src.contains("NSApp.appearance = mode.nsAppearance"))
    }

    func test_appDelegateSourceAppliesLaunchAtLoginPreferenceOnLaunch() {
        let src = readAppDelegateSource()

        XCTAssertTrue(src.contains("import ServiceManagement"))
        XCTAssertTrue(src.contains("if SettingsStore.shared.launchAtLoginEnabled"))
        XCTAssertTrue(src.contains("LoginItemController.apply(enabled: true)"))
    }

    func test_loginItemControllerSource_usesSMAppServiceMainApp() {
        let src = readAppDelegateSource()

        XCTAssertTrue(src.contains("enum LoginItemController"))
        XCTAssertTrue(src.contains("let service = SMAppService.mainApp"))
        XCTAssertTrue(src.contains("try service.register()"))
        XCTAssertTrue(src.contains("try service.unregister()"))
    }

    func test_loginItemControllerSource_doesNotRegisterWhenApprovalRequiresUserAction() {
        let src = readAppDelegateSource()

        XCTAssertTrue(src.contains("case .requiresApproval:"))
        XCTAssertTrue(src.contains("SettingsStore.shared.launchAtLoginEnabled = false"))
        XCTAssertTrue(src.contains("case .notRegistered, .notFound:\n                    try service.register()"))
    }

    func test_loginItemControllerSource_unregistersApprovalPendingItemBeforeClearingPreference() throws {
        let src = readAppDelegateSource()
        let approvalRange = try XCTUnwrap(src.range(of: "case .requiresApproval:"))
        let unknownRange = try XCTUnwrap(src.range(of: "@unknown default:", range: approvalRange.lowerBound..<src.endIndex))
        let approvalBlock = src[approvalRange.lowerBound..<unknownRange.lowerBound]

        let unregisterRange = try XCTUnwrap(approvalBlock.range(of: "try service.unregister()"))
        let clearRange = try XCTUnwrap(approvalBlock.range(of: "SettingsStore.shared.launchAtLoginEnabled = false"))
        XCTAssertLessThan(unregisterRange.lowerBound, clearRange.lowerBound)
    }

    func test_loginItemControllerSource_keepsSettingsRecoveryPreferencePendingApproval() throws {
        let src = readAppDelegateSource()
        let approvalRange = try XCTUnwrap(src.range(of: "case .requiresApproval:"))
        let unknownRange = try XCTUnwrap(src.range(of: "@unknown default:", range: approvalRange.lowerBound..<src.endIndex))
        let approvalBlock = src[approvalRange.lowerBound..<unknownRange.lowerBound]

        let recoveryRange = try XCTUnwrap(approvalBlock.range(of: "if openSettingsWhenApprovalRequired"))
        let clearRange = try XCTUnwrap(approvalBlock.range(of: "SettingsStore.shared.launchAtLoginEnabled = false"))
        XCTAssertLessThan(recoveryRange.lowerBound, clearRange.lowerBound)
    }

    func test_loginItemControllerSource_unregistersApprovalPendingItemWhenPreferenceTurnsOff() {
        let src = readAppDelegateSource()

        XCTAssertTrue(src.contains("case .enabled, .requiresApproval:\n                    try service.unregister()"))
    }

    func test_loginItemControllerSource_opensLoginItemsOnlyFromSettingsRecovery() {
        let src = readAppDelegateSource()

        XCTAssertTrue(src.contains("static func applyFromSettings(enabled: Bool)"))
        XCTAssertTrue(src.contains("SMAppService.openSystemSettingsLoginItems()"))
        XCTAssertTrue(src.contains("apply(enabled: enabled, openSettingsWhenApprovalRequired: true)"))
        XCTAssertTrue(src.contains("apply(enabled: enabled, openSettingsWhenApprovalRequired: false)"))
    }

    func test_everHadAlerts_defaultIsFalse() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)

        XCTAssertFalse(store.everHadAlerts)
    }

    func test_everHadAlerts_persistsAcrossInit() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SettingsStore(defaults: defaults)
        first.everHadAlerts = true

        let second = SettingsStore(defaults: defaults)
        XCTAssertTrue(second.everHadAlerts)
    }

    func test_muteProject_isMutedUntilExpirationBoundary() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        store.mute(project: "alpha", duration: 3600, now: now)

        XCTAssertTrue(store.isMuted(project: "alpha", now: now.addingTimeInterval(3599)))
        XCTAssertFalse(store.isMuted(project: "alpha", now: now.addingTimeInterval(3600)))
        XCTAssertFalse(store.isMuted(project: "beta", now: now))
    }

    func test_unmuteProject_removesMute() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = SettingsStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        store.mute(project: "alpha", duration: 3600, now: now)
        store.unmute(project: "alpha")

        XCTAssertFalse(store.isMuted(project: "alpha", now: now))
        XCTAssertNil(store.mutedProjects["alpha"])
    }

    func test_mutedProjects_persistAcrossInit() {
        let suiteName = "SettingsStoreTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let first = SettingsStore(defaults: defaults)
        first.mute(project: "alpha", duration: 3600, now: now)
        let second = SettingsStore(defaults: defaults)

        XCTAssertEqual(second.mutedProjects["alpha"], now.addingTimeInterval(3600))
        XCTAssertTrue(second.isMuted(project: "alpha", now: now.addingTimeInterval(3599)))
    }

    private func readAppDelegateSource(_ thisFile: StaticString = #filePath) -> String {
        let here = URL(fileURLWithPath: "\(thisFile)")
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/AppDelegate.swift")
        guard let data = try? String(contentsOf: target, encoding: .utf8) else {
            XCTFail("Could not read App/AppDelegate.swift at \(target.path)")
            return ""
        }
        return data
    }
}
