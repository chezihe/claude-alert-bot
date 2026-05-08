import XCTest
@testable import ClaudeAlertBot

final class ProjectNameTests: XCTestCase {

    func test_derive_prefersCwdBasename() {
        let name = ProjectName.derive(
            cwd: "/Users/me/Study/source/claude_alert_bot",
            claudeProjectDir: "/foo/bar"
        )
        XCTAssertEqual(name, "claude_alert_bot")
    }

    func test_derive_fallsBackToClaudeProjectDir() {
        let name = ProjectName.derive(
            cwd: nil,
            claudeProjectDir: "/Users/me/projects/myapp"
        )
        XCTAssertEqual(name, "myapp")
    }

    func test_derive_handlesTrailingSlash() {
        let name = ProjectName.derive(cwd: "/Users/me/foo/", claudeProjectDir: nil)
        XCTAssertEqual(name, "foo")
    }

    func test_derive_handlesRoot() {
        let name = ProjectName.derive(cwd: "/", claudeProjectDir: nil)
        XCTAssertEqual(name, "/")
    }

    func test_derive_bothNil() {
        let name = ProjectName.derive(cwd: nil, claudeProjectDir: nil)
        XCTAssertEqual(name, "unknown")
    }
}
