// ClaudeAlertBotTests/SettingsStoreTests.swift
// WO-003 — UserDefaults persistence for widget corner settings.
import XCTest
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
}
