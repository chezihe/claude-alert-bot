// ClaudeAlertBotTests/PositioningTests.swift
// Phase 2 Plan 02-07 — RESEARCH Pattern 9 (positioning). Pure-function tests for WidgetPositioning.origin.
// Covers WIDG-06 (4 corners + offset) + WIDG-07 (NSScreen.safeAreaInsets clamp / notch awareness).
import XCTest
import AppKit
@testable import ClaudeAlertBot

@MainActor
final class PositioningTests: XCTestCase {
    private let panelSize = NSSize(width: 44, height: 44)
    private let visibleFrame = NSRect(x: 0, y: 0, width: 1920, height: 1080)
    private let zeroSafe = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
    private let topBadgeClearance: CGFloat = 2

    func test_topRight_offset_basic() {
        let origin = WidgetPositioning.origin(
            visibleFrame: visibleFrame,
            safeAreaInsets: zeroSafe,
            corner: .topRight,
            offsetX: 16, offsetY: 16,
            panelSize: panelSize
        )
        XCTAssertEqual(origin.x, 1920 - 44 - 16, accuracy: 0.0001) // 1860
        XCTAssertEqual(origin.y, 1080 - 44 - 16 - topBadgeClearance, accuracy: 0.0001) // 1018
    }

    func test_topRight_safeAreaWiderThanOffset() {
        // Notched display — top inset 38pt, right inset 20pt.
        let safe = NSEdgeInsets(top: 38, left: 0, bottom: 0, right: 20)
        let origin = WidgetPositioning.origin(
            visibleFrame: visibleFrame,
            safeAreaInsets: safe,
            corner: .topRight,
            offsetX: 16, offsetY: 16,
            panelSize: panelSize
        )
        // Right inset 20 wider than offset 16 → use 20.
        XCTAssertEqual(origin.x, 1920 - 44 - 20, accuracy: 0.0001) // 1856
        // Top inset 38 wider than offset 16 → use 38.
        XCTAssertEqual(origin.y, 1080 - 44 - 38 - topBadgeClearance, accuracy: 0.0001) // 996
    }

    func test_bottomLeft_basic() {
        let origin = WidgetPositioning.origin(
            visibleFrame: visibleFrame,
            safeAreaInsets: zeroSafe,
            corner: .bottomLeft,
            offsetX: 8, offsetY: 8,
            panelSize: panelSize
        )
        XCTAssertEqual(origin.x, 0 + 8, accuracy: 0.0001)
        XCTAssertEqual(origin.y, 0 + 8, accuracy: 0.0001)
    }

    func test_topLeft_safeAreaApplied() {
        let safe = NSEdgeInsets(top: 38, left: 12, bottom: 0, right: 0)
        let origin = WidgetPositioning.origin(
            visibleFrame: visibleFrame,
            safeAreaInsets: safe,
            corner: .topLeft,
            offsetX: 8, offsetY: 8,
            panelSize: panelSize
        )
        // left safe 12 > offset 8 → use 12.
        XCTAssertEqual(origin.x, 0 + 12, accuracy: 0.0001)
        // top safe 38 > offset 8 → use 38.
        XCTAssertEqual(origin.y, 1080 - 44 - 38 - topBadgeClearance, accuracy: 0.0001) // 996
    }

    func test_bottomRight_safeAreaApplied() {
        let safe = NSEdgeInsets(top: 0, left: 0, bottom: 18, right: 22)
        let origin = WidgetPositioning.origin(
            visibleFrame: visibleFrame,
            safeAreaInsets: safe,
            corner: .bottomRight,
            offsetX: 16, offsetY: 16,
            panelSize: panelSize
        )
        // right safe 22 > offset 16 → use 22.
        XCTAssertEqual(origin.x, 1920 - 44 - 22, accuracy: 0.0001)
        // bottom safe 18 > offset 16 → use 18.
        XCTAssertEqual(origin.y, 0 + 18, accuracy: 0.0001)
    }

    func test_topCornerBadgeClearanceDoesNotChangeBottomCornerOffset() {
        let topOrigin = WidgetPositioning.origin(
            visibleFrame: visibleFrame,
            safeAreaInsets: zeroSafe,
            corner: .topRight,
            offsetX: 16,
            offsetY: 16,
            panelSize: panelSize
        )
        let bottomOrigin = WidgetPositioning.origin(
            visibleFrame: visibleFrame,
            safeAreaInsets: zeroSafe,
            corner: .bottomRight,
            offsetX: 16,
            offsetY: 16,
            panelSize: panelSize
        )

        XCTAssertEqual(topOrigin.y, 1080 - 44 - 16 - topBadgeClearance, accuracy: 0.0001)
        XCTAssertEqual(bottomOrigin.y, 16, accuracy: 0.0001)
    }

    func test_widgetPositioning_alignsClaudeAnchorsAcrossDrawableSizes() {
        let baseSize = GeometryTokens.widgetDrawableSize(
            idleAnimation: .bounce,
            quietHoursEnabled: false,
            reduceMotion: false,
            widgetIconStyle: .claude
        )
        let roamSize = GeometryTokens.widgetDrawableSize(
            idleAnimation: .roam,
            quietHoursEnabled: false,
            reduceMotion: false,
            widgetIconStyle: .claude
        )
        let magicSize = GeometryTokens.widgetDrawableSize(
            idleAnimation: .magic,
            quietHoursEnabled: false,
            reduceMotion: false,
            widgetIconStyle: .claude
        )
        let baseOrigin = WidgetPositioning.origin(
            visibleFrame: visibleFrame,
            safeAreaInsets: zeroSafe,
            corner: .topRight,
            offsetX: 16,
            offsetY: 16,
            panelSize: baseSize,
            positioningAnchor: GeometryTokens.widgetPositioningAnchor(
                idleAnimation: .bounce,
                quietHoursEnabled: false,
                reduceMotion: false,
                widgetIconStyle: .claude
            )
        )
        let roamOrigin = WidgetPositioning.origin(
            visibleFrame: visibleFrame,
            safeAreaInsets: zeroSafe,
            corner: .topRight,
            offsetX: 16,
            offsetY: 16,
            panelSize: roamSize,
            positioningAnchor: GeometryTokens.widgetPositioningAnchor(
                idleAnimation: .roam,
                quietHoursEnabled: false,
                reduceMotion: false,
                widgetIconStyle: .claude
            )
        )
        let magicOrigin = WidgetPositioning.origin(
            visibleFrame: visibleFrame,
            safeAreaInsets: zeroSafe,
            corner: .topRight,
            offsetX: 16,
            offsetY: 16,
            panelSize: magicSize,
            positioningAnchor: GeometryTokens.widgetPositioningAnchor(
                idleAnimation: .magic,
                quietHoursEnabled: false,
                reduceMotion: false,
                widgetIconStyle: .claude
            )
        )
        let baseAnchorPoint = NSPoint(x: baseOrigin.x + 32, y: baseOrigin.y + 44)
        let roamAnchorPoint = NSPoint(x: roamOrigin.x + 48, y: roamOrigin.y + 44)
        let magicAnchorPoint = NSPoint(x: magicOrigin.x + 32, y: magicOrigin.y + 52)

        XCTAssertEqual(baseAnchorPoint.x, roamAnchorPoint.x, accuracy: 0.0001)
        XCTAssertEqual(baseAnchorPoint.y, roamAnchorPoint.y, accuracy: 0.0001)
        XCTAssertEqual(baseAnchorPoint.x, magicAnchorPoint.x, accuracy: 0.0001)
        XCTAssertEqual(baseAnchorPoint.y, magicAnchorPoint.y, accuracy: 0.0001)
    }

    func test_widgetPositioning_alignsZeldaAnchorWithClaudeAnchor() {
        let claudeSize = GeometryTokens.widgetDrawableSize(
            idleAnimation: .bounce,
            quietHoursEnabled: false,
            reduceMotion: false,
            widgetIconStyle: .claude
        )
        let zeldaSize = GeometryTokens.widgetDrawableSize(
            idleAnimation: .bounce,
            quietHoursEnabled: false,
            reduceMotion: false,
            widgetIconStyle: .zelda
        )
        let claudeAnchor = GeometryTokens.widgetPositioningAnchor(
            idleAnimation: .bounce,
            quietHoursEnabled: false,
            reduceMotion: false,
            widgetIconStyle: .claude
        )
        let zeldaAnchor = GeometryTokens.widgetPositioningAnchor(
            idleAnimation: .bounce,
            quietHoursEnabled: false,
            reduceMotion: false,
            widgetIconStyle: .zelda,
            widgetSide: .left
        )
        let claudeOrigin = WidgetPositioning.origin(
            visibleFrame: visibleFrame,
            safeAreaInsets: zeroSafe,
            corner: .bottomLeft,
            offsetX: 16,
            offsetY: 16,
            panelSize: claudeSize,
            positioningAnchor: claudeAnchor
        )
        let zeldaOrigin = WidgetPositioning.origin(
            visibleFrame: visibleFrame,
            safeAreaInsets: zeroSafe,
            corner: .bottomLeft,
            offsetX: 16,
            offsetY: 16,
            panelSize: zeldaSize,
            positioningAnchor: zeldaAnchor
        )

        XCTAssertEqual(claudeOrigin.x + claudeAnchor.x, zeldaOrigin.x + zeldaAnchor.x, accuracy: 0.0001)
        XCTAssertEqual(claudeOrigin.y + claudeAnchor.y, zeldaOrigin.y + zeldaAnchor.y, accuracy: 0.0001)
    }

    func test_widgetPositioning_keepsSideSpecificZeldaPngEdgesOffScreenCorners() {
        let zeldaSize = GeometryTokens.widgetDrawableSize(
            idleAnimation: .bounce,
            quietHoursEnabled: false,
            reduceMotion: false,
            widgetIconStyle: .zelda
        )
        let leftAnchor = GeometryTokens.widgetPositioningAnchor(
            idleAnimation: .bounce,
            quietHoursEnabled: false,
            reduceMotion: false,
            widgetIconStyle: .zelda,
            widgetSide: .left
        )
        let rightAnchor = GeometryTokens.widgetPositioningAnchor(
            idleAnimation: .bounce,
            quietHoursEnabled: false,
            reduceMotion: false,
            widgetIconStyle: .zelda,
            widgetSide: .right
        )
        let leftOrigin = WidgetPositioning.origin(
            visibleFrame: visibleFrame,
            safeAreaInsets: zeroSafe,
            corner: .bottomLeft,
            offsetX: 16,
            offsetY: 16,
            panelSize: zeldaSize,
            positioningAnchor: leftAnchor
        )
        let rightOrigin = WidgetPositioning.origin(
            visibleFrame: visibleFrame,
            safeAreaInsets: zeroSafe,
            corner: .bottomRight,
            offsetX: 16,
            offsetY: 16,
            panelSize: zeldaSize,
            positioningAnchor: rightAnchor
        )

        XCTAssertEqual(leftOrigin.x + 18, 25, accuracy: 0.0001)
        XCTAssertEqual(rightOrigin.x + 110, visibleFrame.maxX - 25, accuracy: 0.0001)
    }

    func test_widgetScreenSelection_prefersFocusedWindowScreenOverFallback() {
        let primary = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = NSRect(x: 1440, y: 0, width: 1440, height: 900)
        let focusedWindow = NSRect(x: 1560, y: 240, width: 600, height: 420)

        let index = WidgetScreenSelection.preferredScreenIndex(
            windowBounds: focusedWindow,
            mouseLocation: NSPoint(x: 100, y: 100),
            screenFrames: [primary, secondary],
            fallbackIndex: 0
        )

        XCTAssertEqual(index, 1)
    }

    func test_widgetScreenSelection_usesMouseScreenWhenFocusedWindowMissing() {
        let primary = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = NSRect(x: 1440, y: 0, width: 1440, height: 900)

        let index = WidgetScreenSelection.preferredScreenIndex(
            windowBounds: nil,
            mouseLocation: NSPoint(x: 1600, y: 300),
            screenFrames: [primary, secondary],
            fallbackIndex: 0
        )

        XCTAssertEqual(index, 1)
    }

    func test_widgetScreenSelection_canPreferMouseScreenForVisibleWidgetFollow() {
        let primary = NSRect(x: 0, y: 0, width: 1440, height: 900)
        let secondary = NSRect(x: 1440, y: 0, width: 1440, height: 900)
        let focusedWindow = NSRect(x: 100, y: 120, width: 600, height: 420)

        let index = WidgetScreenSelection.preferredScreenIndex(
            windowBounds: focusedWindow,
            mouseLocation: NSPoint(x: 1600, y: 300),
            screenFrames: [primary, secondary],
            fallbackIndex: 0,
            preferMouseLocation: true
        )

        XCTAssertEqual(index, 1)
    }

    func test_widgetPopoverPositioning_usesTightArrowlessGap() {
        let widgetFrame = NSRect(x: 1500, y: 800, width: 44, height: 44)
        let popoverSize = NSSize(width: 270, height: 200)

        let topOrigin = WidgetPopoverPositioning.origin(
            widgetFrame: widgetFrame,
            panelSize: popoverSize,
            visibleFrame: visibleFrame,
            corner: .topRight
        )
        let bottomOrigin = WidgetPopoverPositioning.origin(
            widgetFrame: widgetFrame,
            panelSize: popoverSize,
            visibleFrame: visibleFrame,
            corner: .bottomRight
        )

        XCTAssertEqual(topOrigin.y, widgetFrame.minY - 4 - popoverSize.height, accuracy: 0.0001)
        XCTAssertEqual(bottomOrigin.y, widgetFrame.maxY + 4, accuracy: 0.0001)
    }

    func test_widgetPopoverPositioning_usesZeldaVisualAnchorForVerticalGap() {
        let widgetFrame = NSRect(x: 1000, y: 500, width: 128, height: 128)
        let popoverSize = NSSize(width: 270, height: 200)

        let topOrigin = WidgetPopoverPositioning.origin(
            widgetFrame: widgetFrame,
            panelSize: popoverSize,
            visibleFrame: visibleFrame,
            corner: .topRight,
            widgetIconStyle: .zelda
        )
        let bottomOrigin = WidgetPopoverPositioning.origin(
            widgetFrame: widgetFrame,
            panelSize: popoverSize,
            visibleFrame: visibleFrame,
            corner: .bottomRight,
            widgetIconStyle: .zelda
        )

        XCTAssertEqual(topOrigin.y, widgetFrame.minY + 2 - (4.0 / 3.0) - popoverSize.height, accuracy: 0.0001)
        XCTAssertEqual(bottomOrigin.y, widgetFrame.maxY - 2 + (4.0 / 3.0), accuracy: 0.0001)
        XCTAssertEqual(
            bottomOrigin.y - widgetFrame.maxY,
            widgetFrame.minY - (topOrigin.y + popoverSize.height),
            accuracy: 0.0001
        )
    }

    func test_widgetPopoverPositioning_usesZeldaVisualAnchorForHorizontalEdges() {
        let widgetFrame = NSRect(x: 1000, y: 500, width: 128, height: 128)
        let popoverSize = NSSize(width: 270, height: 200)

        let leftOrigin = WidgetPopoverPositioning.origin(
            widgetFrame: widgetFrame,
            panelSize: popoverSize,
            visibleFrame: visibleFrame,
            corner: .topLeft,
            widgetIconStyle: .zelda
        )
        let rightOrigin = WidgetPopoverPositioning.origin(
            widgetFrame: widgetFrame,
            panelSize: popoverSize,
            visibleFrame: visibleFrame,
            corner: .topRight,
            widgetIconStyle: .zelda
        )

        XCTAssertEqual(leftOrigin.x, widgetFrame.minX + 9, accuracy: 0.0001)
        XCTAssertEqual(rightOrigin.x, widgetFrame.minX + 9 + 110 - popoverSize.width, accuracy: 0.0001)
    }
}
