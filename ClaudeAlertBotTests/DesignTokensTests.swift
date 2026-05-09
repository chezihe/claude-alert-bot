// DesignTokensTests.swift — Phase 03.1 Plan 01.
// Drift-guard XCTests for App/DesignTokens.swift. Every documented token value
// (SPEC.md §3 + §4 + Finding F-1) is asserted here; mutating any token literal
// MUST break exactly one test below. SC#2 contract.
//
// Pure XCTest — no SnapshotTesting / pointfreeco / external Swift deps (D2-29).
import XCTest
import SwiftUI
import AppKit
@testable import ClaudeAlertBot

final class DesignTokensTests: XCTestCase {

    // MARK: - ColorTokens (SPEC.md §3 "Color")

    func test_colorTokens_accent_matchesSpecHex_D97757() {
        let c = NSColor(ColorTokens.accent).usingColorSpace(.sRGB)
        XCTAssertNotNil(c, "accent must bridge to sRGB NSColor")
        XCTAssertEqual(c?.redComponent   ?? 0, Double(0xD9) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.greenComponent ?? 0, Double(0x77) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.blueComponent  ?? 0, Double(0x57) / 255.0, accuracy: 0.005)
    }

    func test_colorTokens_accentDark_matchesSpecHex_B8492C() {
        let c = NSColor(ColorTokens.accentDark).usingColorSpace(.sRGB)
        XCTAssertEqual(c?.redComponent   ?? 0, Double(0xB8) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.greenComponent ?? 0, Double(0x49) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.blueComponent  ?? 0, Double(0x2C) / 255.0, accuracy: 0.005)
    }

    func test_colorTokens_statusSuccess_matchesSpecHex_D97757() {
        let c = NSColor(ColorTokens.statusSuccess).usingColorSpace(.sRGB)
        XCTAssertEqual(c?.redComponent   ?? 0, Double(0xD9) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.greenComponent ?? 0, Double(0x77) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.blueComponent  ?? 0, Double(0x57) / 255.0, accuracy: 0.005)
    }

    func test_colorTokens_statusError_matchesSpecHex_E5484D() {
        let c = NSColor(ColorTokens.statusError).usingColorSpace(.sRGB)
        XCTAssertEqual(c?.redComponent   ?? 0, Double(0xE5) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.greenComponent ?? 0, Double(0x48) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.blueComponent  ?? 0, Double(0x4D) / 255.0, accuracy: 0.005)
    }

    func test_colorTokens_statusWaiting_matchesSpecHex_F5A623() {
        let c = NSColor(ColorTokens.statusWaiting).usingColorSpace(.sRGB)
        XCTAssertEqual(c?.redComponent   ?? 0, Double(0xF5) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.greenComponent ?? 0, Double(0xA6) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.blueComponent  ?? 0, Double(0x23) / 255.0, accuracy: 0.005)
    }

    func test_colorTokens_statusDotMapsAlertKindToStatusColors() {
        assertColor(ColorTokens.statusDot(for: .success), matches: ColorTokens.statusSuccess)
        assertColor(ColorTokens.statusDot(for: .error), matches: ColorTokens.statusError)
        assertColor(ColorTokens.statusDot(for: .waiting), matches: ColorTokens.statusWaiting)
    }

    func test_colorTokens_rowHoverLight_matchesSpecRGBA() {
        let c = NSColor(ColorTokens.rowHover(colorScheme: .light)).usingColorSpace(.sRGB)
        XCTAssertEqual(c?.redComponent   ?? 0, Double(0xD9) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.greenComponent ?? 0, Double(0x77) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.blueComponent  ?? 0, Double(0x57) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.alphaComponent ?? 0, 0.13, accuracy: 0.005)
    }

    func test_colorTokens_rowHoverDark_matchesSpecRGBA() {
        let c = NSColor(ColorTokens.rowHover(colorScheme: .dark)).usingColorSpace(.sRGB)
        XCTAssertEqual(c?.redComponent   ?? 0, Double(0xD9) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.greenComponent ?? 0, Double(0x77) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.blueComponent  ?? 0, Double(0x57) / 255.0, accuracy: 0.005)
        XCTAssertEqual(c?.alphaComponent ?? 0, 0.20, accuracy: 0.005)
    }

    // MARK: - GeometryTokens (SPEC.md §3 "Geometry")

    func test_geometryTokens_popoverWidth_is280_perFindingF1() {
        // F-1: SPEC.md §3 says 270pt; code SoT is 280pt — token follows code (Constraint D).
        XCTAssertEqual(GeometryTokens.popoverWidth, 280)
    }

    func test_geometryTokens_popoverCornerRadius_is14() {
        XCTAssertEqual(GeometryTokens.popoverCornerRadius, 14)
    }

    func test_geometryTokens_rowMinHeight_is36() {
        XCTAssertEqual(GeometryTokens.rowMinHeight, 36)
    }

    func test_geometryTokens_rowHorizontalPadding_is12() {
        XCTAssertEqual(GeometryTokens.rowHorizontalPadding, 12)
    }

    func test_geometryTokens_rowVerticalPadding_is8() {
        XCTAssertEqual(GeometryTokens.rowVerticalPadding, 8)
    }

    func test_geometryTokens_statusDotDiameter_is7() {
        XCTAssertEqual(GeometryTokens.statusDotDiameter, 7)
    }

    func test_geometryTokens_statusDotRingStroke_is1_5() {
        XCTAssertEqual(GeometryTokens.statusDotRingStroke, 1.5)
    }

    func test_geometryTokens_popoverMaxVisibleRows_is8() {
        XCTAssertEqual(GeometryTokens.popoverMaxVisibleRows, 8)
    }

    // MARK: - MotionTokens (SPEC.md §4 "Motion")

    func test_motionTokens_bounceDuration_is0_45() {
        XCTAssertEqual(MotionTokens.bounceDuration, 0.45, accuracy: 0.001)
    }

    func test_motionTokens_bounceOffset_is5() {
        XCTAssertEqual(MotionTokens.bounceOffset, 5)
    }

    // MARK: - MotionTokens reduce-motion gate (D4 / SC#3)

    func test_motionTokens_bounceAnimation_returnsNil_whenReduceMotionIsTrue() {
        // D4: token namespace owns the uniform reduce-motion gate.
        XCTAssertNil(MotionTokens.bounceAnimation(reduceMotion: true))
    }

    func test_motionTokens_bounceAnimation_returnsNonNil_whenReduceMotionIsFalse() {
        // We cannot inspect Animation internals across SwiftUI versions; non-nil + the
        // reduce-motion=true → nil pair above is sufficient drift-guard.
        XCTAssertNotNil(MotionTokens.bounceAnimation(reduceMotion: false))
    }

    private func assertColor(_ actual: Color, matches expected: Color, file: StaticString = #filePath, line: UInt = #line) {
        let actualColor = NSColor(actual).usingColorSpace(.sRGB)
        let expectedColor = NSColor(expected).usingColorSpace(.sRGB)
        XCTAssertEqual(actualColor?.redComponent ?? 0, expectedColor?.redComponent ?? 0, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(actualColor?.greenComponent ?? 0, expectedColor?.greenComponent ?? 0, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(actualColor?.blueComponent ?? 0, expectedColor?.blueComponent ?? 0, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(actualColor?.alphaComponent ?? 0, expectedColor?.alphaComponent ?? 0, accuracy: 0.005, file: file, line: line)
    }
}
