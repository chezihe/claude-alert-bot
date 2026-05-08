// ClaudeAlertBotTests/FloatingWidgetPanelTests.swift
// Phase 2 Plan 02-07 — Pattern 7 NSPanel locked (WIDG-01, WIDG-02).
// Each test asserts a property of FloatingWidgetPanel against accidental future regression.
import XCTest
import AppKit
@testable import ClaudeAlertBot

@MainActor
final class FloatingWidgetPanelTests: XCTestCase {
    private func makePanel() -> FloatingWidgetPanel {
        FloatingWidgetPanel(contentRect: NSRect(x: 0, y: 0, width: 44, height: 44))
    }

    func test_styleMask_containsNonActivating() {
        let p = makePanel()
        XCTAssertTrue(p.styleMask.contains(.nonactivatingPanel), "WIDG-02 anchor — `.nonactivatingPanel` MUST be set")
        XCTAssertTrue(p.styleMask.contains(.borderless))
    }

    func test_level_isFloating() {
        let p = makePanel()
        XCTAssertEqual(p.level, NSWindow.Level.floating, "WIDG-01 — panel must float above app windows")
    }

    func test_collectionBehavior_threeFlagsPresent() {
        let p = makePanel()
        let cb = p.collectionBehavior
        XCTAssertTrue(cb.contains(.canJoinAllSpaces), "WIDG-01 — must follow user across Spaces")
        XCTAssertTrue(cb.contains(.fullScreenAuxiliary), "WIDG-01 — must overlay full-screen apps")
        XCTAssertTrue(cb.contains(.stationary), "RESEARCH Pitfall #1 — prevents Mission Control suppression")
    }

    func test_canBecomeKey_returnsFalse() {
        let p = makePanel()
        XCTAssertFalse(p.canBecomeKey, "WIDG-02 belt-and-suspenders — panel must never steal focus")
        XCTAssertFalse(p.canBecomeMain)
    }

    func test_becomesKeyOnlyIfNeeded_isTrue() {
        let p = makePanel()
        XCTAssertTrue(p.becomesKeyOnlyIfNeeded)
    }

    func test_hasShadow_isTrue() {
        let p = makePanel()
        XCTAssertTrue(p.hasShadow, "UI-SPEC — `.hudWindow` material drop shadow")
    }

    func test_isOpaque_isFalse_backgroundClear() {
        let p = makePanel()
        XCTAssertFalse(p.isOpaque, "Allows NSVisualEffectView blur to show through")
        XCTAssertEqual(p.backgroundColor, NSColor.clear)
    }
}
