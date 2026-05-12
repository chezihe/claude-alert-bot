// iTermSessionIDTests.swift — Phase 3 / 03-01 D3-01 + T-INJECTION-01 regression matrix.
// Mirror of ProjectNameTests structure (one method per branch).
import XCTest
@testable import ClaudeAlertBot

final class iTermSessionIDTests: XCTestCase {

    // MARK: - uuid(fromRaw:) extractor (D3-01)

    func test_uuid_extractsExpectedSessionID() {
        let canonical = "79C4699F-1234-5678-9ABC-DEF012345678"

        XCTAssertEqual(iTermSessionID.uuid(fromRaw: "w0t0p1:\(canonical)"), canonical)
        XCTAssertEqual(iTermSessionID.uuid(fromRaw: canonical), canonical)
        XCTAssertNil(iTermSessionID.uuid(fromRaw: nil))
        XCTAssertNil(iTermSessionID.uuid(fromRaw: ""))
        XCTAssertNil(iTermSessionID.uuid(fromRaw: ":"))
        XCTAssertNil(iTermSessionID.uuid(fromRaw: "w0t0p1:"))
    }

    // MARK: - isValid(_:) whitelist (T-INJECTION-01)

    func test_isValid_acceptsCanonicalUUIDAndRejectsUnsafeInput() {
        XCTAssertTrue(iTermSessionID.isValid("79C4699F-1234-5678-9ABC-DEF012345678"))
        // The literal threat: `targetUUID = "..."; tell ... to do shell script "..."` —
        // any non-UUID character must fail Foundation's parser.
        XCTAssertFalse(iTermSessionID.isValid("\"; tell application \"iTerm2\" to activate; \""))
        XCTAssertFalse(iTermSessionID.isValid("not-a-uuid"))
        XCTAssertFalse(iTermSessionID.isValid(""))
        XCTAssertFalse(iTermSessionID.isValid("79C4699F-1234-5678-9ABC-DEF01234567"))   // 35 chars
    }
}
