// ClaudeAlertBotTests/EmptyStateViewTests.swift — WO-009 popover empty-state contract.
import XCTest
import SwiftUI
@testable import ClaudeAlertBot

final class EmptyStateViewTests: XCTestCase {

    func test_emptyStateMessage_isLockedCopy() {
        XCTAssertEqual(EmptyStateView.message, "Listening to iTerm")
    }

    func test_emptyStateView_canBeConstructed() {
        _ = EmptyStateView()
    }

    func test_emptyStateViewSource_rendersMessageText() {
        let src = readEmptyStateViewSource()

        XCTAssertTrue(src.contains("Text(Self.message)"))
    }

    func test_emptyStateViewSource_usesSecondaryStyleAndAccessibilityLabel() {
        let src = readEmptyStateViewSource()

        XCTAssertTrue(src.contains(".foregroundStyle(.secondary)"))
        XCTAssertTrue(src.contains(".accessibilityLabel(Self.message)"))
    }

    func test_emptyStateViewSource_importsOnlySwiftUI() {
        let src = readEmptyStateViewSource()

        XCTAssertTrue(src.contains("import SwiftUI"))
        XCTAssertFalse(src.contains("import AppKit"))
        XCTAssertFalse(src.contains("import Foundation"))
    }

    private func readEmptyStateViewSource(_ thisFile: StaticString = #filePath) -> String {
        let here = URL(fileURLWithPath: "\(thisFile)")
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/EmptyStateView.swift")
        guard let data = try? String(contentsOf: target, encoding: .utf8) else {
            XCTFail("Could not read App/EmptyStateView.swift at \(target.path)")
            return ""
        }
        return data
    }
}
