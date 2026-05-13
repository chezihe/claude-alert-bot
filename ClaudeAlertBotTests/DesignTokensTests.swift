// DesignTokensTests.swift — Phase 03.1 Plan 01.
// Drift-guard XCTests for App/DesignTokens.swift. Every documented token value
// (SPEC.md §3 + §4) is asserted here; mutating any token literal
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

    func test_geometryTokens_popoverWidth_is270_perSpec() {
        XCTAssertEqual(GeometryTokens.popoverWidth, 270)
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

    func test_geometryTokens_popoverMaxVisibleRows_is4_perFeaturesSpec() {
        XCTAssertEqual(GeometryTokens.popoverMaxVisibleRows, 4)
    }

    func test_geometryTokens_popoverScrollFadeHeight_is12() {
        XCTAssertEqual(GeometryTokens.popoverScrollFadeHeight, 12)
    }

    func test_geometryTokens_widgetDrawableSize_expandsForActiveRoam() {
        let size = GeometryTokens.widgetDrawableSize(
            idleAnimation: .roam,
            quietHoursEnabled: false,
            reduceMotion: false
        )

        XCTAssertEqual(size.width, 74)
        XCTAssertEqual(size.height, 56)
    }

    func test_geometryTokens_widgetDrawableSize_expandsForActiveMagic() {
        let size = GeometryTokens.widgetDrawableSize(
            idleAnimation: .magic,
            quietHoursEnabled: false,
            reduceMotion: false
        )

        XCTAssertEqual(size.width, 74)
        XCTAssertEqual(size.height, 82)
    }

    func test_geometryTokens_widgetDrawableSize_keepsBaseSizeWhenRoamIsSuppressed() {
        let quietSize = GeometryTokens.widgetDrawableSize(
            idleAnimation: .roam,
            quietHoursEnabled: true,
            reduceMotion: false
        )
        let reduceMotionSize = GeometryTokens.widgetDrawableSize(
            idleAnimation: .roam,
            quietHoursEnabled: false,
            reduceMotion: true
        )
        let bounceSize = GeometryTokens.widgetDrawableSize(
            idleAnimation: .bounce,
            quietHoursEnabled: false,
            reduceMotion: false
        )
        let rageSize = GeometryTokens.widgetDrawableSize(
            idleAnimation: .rage,
            quietHoursEnabled: false,
            reduceMotion: false
        )
        let magicSuppressedSize = GeometryTokens.widgetDrawableSize(
            idleAnimation: .magic,
            quietHoursEnabled: true,
            reduceMotion: false
        )
        let magicReduceMotionSize = GeometryTokens.widgetDrawableSize(
            idleAnimation: .magic,
            quietHoursEnabled: false,
            reduceMotion: true
        )

        XCTAssertEqual(quietSize.width, 50)
        XCTAssertEqual(quietSize.height, 50)
        XCTAssertEqual(reduceMotionSize.width, 50)
        XCTAssertEqual(reduceMotionSize.height, 50)
        XCTAssertEqual(bounceSize.width, 50)
        XCTAssertEqual(bounceSize.height, 50)
        XCTAssertEqual(rageSize.width, 50)
        XCTAssertEqual(rageSize.height, 50)
        XCTAssertEqual(magicSuppressedSize.width, 50)
        XCTAssertEqual(magicSuppressedSize.height, 50)
        XCTAssertEqual(magicReduceMotionSize.width, 50)
        XCTAssertEqual(magicReduceMotionSize.height, 50)
    }

    // MARK: - MotionTokens (SPEC.md §4 "Motion")

    func test_motionTokens_rageValues_matchPrototype() {
        XCTAssertEqual(MotionTokens.ragePeriod, 2.4, accuracy: 0.001)
        XCTAssertEqual(MotionTokens.rageWindupDuration, 0.95, accuracy: 0.001)
    }

    func test_motionTokensSource_ringValues_movedToMotionKeyframes() {
        let src = readDesignTokensSource()

        XCTAssertFalse(src.contains("static let ringDuration"))
        XCTAssertFalse(src.contains("static let ringRotation"))
        XCTAssertFalse(src.contains("static func ringAnimation"))
    }

    func test_motionTokensSource_roamValues_matchSpec() {
        let src = readDesignTokensSource()

        XCTAssertTrue(src.contains("static let roamDuration: TimeInterval = 1.6"))
        XCTAssertTrue(src.contains("static let roamRadiusX: CGFloat = 12"))
        XCTAssertTrue(src.contains("static let roamRadiusY: CGFloat = 3"))
        XCTAssertTrue(src.contains("static func roamAnimation(reduceMotion: Bool) -> Animation?"))
        XCTAssertTrue(src.contains(".linear(duration: roamDuration).repeatForever(autoreverses: false)"))
    }


    func test_motionTokens_newAlertPulseValues_matchSpec() {
        XCTAssertEqual(MotionTokens.newAlertPulseDuration, 0.45, accuracy: 0.001)
        XCTAssertEqual(MotionTokens.newAlertPulsePeakScale, 1.14, accuracy: 0.001)
        XCTAssertEqual(MotionTokens.newAlertPulseSquashScale, 0.96, accuracy: 0.001)
        XCTAssertEqual(MotionTokens.newAlertPulseSettleScale, 1.06, accuracy: 0.001)
        XCTAssertEqual(MotionTokens.newAlertPulseRotation, 7, accuracy: 0.001)
    }

    func test_motionTokens_sonarValues_matchSpec() {
        XCTAssertEqual(MotionTokens.sonarDuration, 0.75, accuracy: 0.001)
        XCTAssertEqual(MotionTokens.sonarStartScale, 0.5, accuracy: 0.001)
        XCTAssertEqual(MotionTokens.sonarEndScale, 3.0, accuracy: 0.001)
        XCTAssertEqual(MotionTokens.sonarBaseDiameter, 14, accuracy: 0.001)
        XCTAssertLessThanOrEqual(MotionTokens.sonarBaseDiameter * MotionTokens.sonarEndScale, 50)
        XCTAssertEqual(MotionTokens.sonarStartOpacity, 0.75, accuracy: 0.001)
        XCTAssertEqual(MotionTokens.reduceMotionFadeDuration, 0.15, accuracy: 0.001)
    }

    func test_motionTokens_statusDotRippleValues_matchSpec() {
        XCTAssertEqual(MotionTokens.statusDotRippleDuration, 1.0, accuracy: 0.001)
        XCTAssertEqual(MotionTokens.statusDotRippleEndScale, 2.4, accuracy: 0.001)
        XCTAssertEqual(MotionTokens.statusDotRippleStartOpacity, 0.6, accuracy: 0.001)
        XCTAssertEqual(MotionTokens.statusDotRippleRepeatCount, 3)
    }

    func test_motionTokens_waitingDotPulseValues_matchPrototype() {
        XCTAssertEqual(MotionTokens.waitingDotPulseDuration, 1.6, accuracy: 0.001)
        XCTAssertEqual(MotionTokens.waitingDotPulseMinOpacity, 0.5, accuracy: 0.001)
    }

    // MARK: - MotionTokens reduce-motion gate (D4 / SC#3)

    // MARK: - EffectTokens (WO-010 aging)

    func test_effectTokens_agedSaturation_is0_4() {
        XCTAssertEqual(EffectTokens.agedSaturation, 0.4, accuracy: 0.001)
    }

    private func assertColor(_ actual: Color, matches expected: Color, file: StaticString = #filePath, line: UInt = #line) {
        let actualColor = NSColor(actual).usingColorSpace(.sRGB)
        let expectedColor = NSColor(expected).usingColorSpace(.sRGB)
        XCTAssertEqual(actualColor?.redComponent ?? 0, expectedColor?.redComponent ?? 0, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(actualColor?.greenComponent ?? 0, expectedColor?.greenComponent ?? 0, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(actualColor?.blueComponent ?? 0, expectedColor?.blueComponent ?? 0, accuracy: 0.005, file: file, line: line)
        XCTAssertEqual(actualColor?.alphaComponent ?? 0, expectedColor?.alphaComponent ?? 0, accuracy: 0.005, file: file, line: line)
    }

    private func readDesignTokensSource(_ thisFile: StaticString = #filePath) -> String {
        let here = URL(fileURLWithPath: "\(thisFile)")
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/DesignTokens.swift")
        guard let data = try? String(contentsOf: target, encoding: .utf8) else {
            XCTFail("Could not read App/DesignTokens.swift at \(target.path)")
            return ""
        }
        return data
    }
}
