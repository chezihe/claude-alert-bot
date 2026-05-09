// ClaudeAlertBotTests/FloatingWidgetWindowControllerTests.swift
// WO-003 — currently visible widget reacts to Settings corner changes.
import XCTest
import AppKit
@testable import ClaudeAlertBot

@MainActor
final class FloatingWidgetWindowControllerTests: XCTestCase {
    func test_visibleWidgetRepositionsWhenWidgetCornerChanges() async throws {
        guard let screen = NSScreen.main else {
            throw XCTSkip("NSScreen.main unavailable in this test environment")
        }

        let store = SettingsStore.shared
        let oldCorner = store.widgetCorner
        let oldOffsetX = store.offsetX
        let oldOffsetY = store.offsetY

        store.offsetX = 16
        store.offsetY = 16
        store.widgetCorner = .topRight

        let controller = FloatingWidgetWindowController()
        defer {
            controller.window?.orderOut(nil)
            store.widgetCorner = oldCorner
            store.offsetX = oldOffsetX
            store.offsetY = oldOffsetY
        }

        controller.showWidget(pendingCount: 1, latest: nil)
        try await Task.sleep(nanoseconds: 300_000_000)
        let before = controller.window!.frame.origin

        store.widgetCorner = .bottomLeft
        try await Task.sleep(nanoseconds: 50_000_000)

        let after = controller.window!.frame.origin
        let expected = WidgetPositioning.origin(
            visibleFrame: screen.visibleFrame,
            safeAreaInsets: screen.safeAreaInsets,
            corner: .bottomLeft,
            offsetX: 16,
            offsetY: 16,
            panelSize: controller.window!.frame.size
        )

        XCTAssertNotEqual(before.x, after.x, accuracy: 0.0001)
        XCTAssertNotEqual(before.y, after.y, accuracy: 0.0001)
        XCTAssertEqual(after.x, expected.x, accuracy: 0.0001)
        XCTAssertEqual(after.y, expected.y, accuracy: 0.0001)
    }
}
