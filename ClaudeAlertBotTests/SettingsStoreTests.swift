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
}
