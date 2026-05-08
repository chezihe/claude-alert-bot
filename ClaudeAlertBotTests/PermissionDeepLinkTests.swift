// PermissionDeepLinkTests.swift — D2-36 URL list regression guard.
// The URL sequence is locked by D2-36 (CONTEXT) + RESEARCH Pattern 12.
// Drift in any string fails these tests on next CI / `xcodebuild test` run,
// preventing well-meaning future edits from silently breaking the
// macOS Sequoia → Sonoma → root fallback chain.
import XCTest
@testable import ClaudeAlertBot

final class PermissionDeepLinkTests: XCTestCase {
    func test_urlList_matchesD2_36_verbatim() {
        XCTAssertEqual(PermissionDeepLink.urls.count, 3, "D2-36 locks exactly 3 URLs in sequence")
        XCTAssertEqual(PermissionDeepLink.urls[0],
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
            "Index 0 must be macOS 15 Sequoia URL")
        XCTAssertEqual(PermissionDeepLink.urls[1],
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
            "Index 1 must be macOS 14/13 Ventura URL")
        XCTAssertEqual(PermissionDeepLink.urls[2],
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
            "Index 2 must be Privacy root fallback")
    }

    func test_urlList_allParseAsURL() {
        for s in PermissionDeepLink.urls {
            XCTAssertNotNil(URL(string: s), "Failed to parse URL: \(s)")
        }
    }
}
