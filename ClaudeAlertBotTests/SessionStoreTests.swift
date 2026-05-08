// SessionStoreTests.swift — Phase 2 Wave 2 (02-04 Task 1).
// Tests for atomic save/load + corrupt-file recovery (SESS-03, T-FILE-01, T-SCHEMA-01).
// Each test writes to a temp URL — never touches the real ~/Library/Application Support path.
import XCTest
@testable import ClaudeAlertBot

final class SessionStoreTests: XCTestCase {
    private var tempURL: URL!

    override func setUp() {
        super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cab-test-\(UUID().uuidString).json")
    }

    override func tearDown() {
        // Best-effort cleanup of the test artifact + any corrupt-renamed siblings.
        let dir = tempURL.deletingLastPathComponent()
        let prefix = tempURL.lastPathComponent
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for name in entries where name.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }
        }
        tempURL = nil
        super.tearDown()
    }

    /// Test 1: SessionsSnapshot round-trips through save→load unchanged.
    func test_saveAndLoad_roundTrip() async {
        let store = SessionStore(url: tempURL)
        let snapshot = SessionsSnapshot(
            schema: SessionsSnapshot.currentSchema,
            inFlight: [
                "sid-1": InFlightStart(startedAt: Date(timeIntervalSince1970: 1_700_000_000), cwd: "/tmp/a"),
                "sid-2": InFlightStart(startedAt: Date(timeIntervalSince1970: 1_700_000_100), cwd: nil)
            ],
            completed: [
                CompletedSession(sessionID: "c1", projectName: "alpha",
                                 stoppedAt: Date(timeIntervalSince1970: 1_700_000_200),
                                 durationSec: 42, itermSessionID: "w0t0p1:UUID", tty: "/dev/ttys001",
                                 cwd: "/tmp/a"),
                CompletedSession(sessionID: "c2", projectName: "beta",
                                 stoppedAt: Date(timeIntervalSince1970: 1_700_000_300),
                                 durationSec: nil, itermSessionID: nil, tty: nil, cwd: nil),
                CompletedSession(sessionID: "c3", projectName: "gamma",
                                 stoppedAt: Date(timeIntervalSince1970: 1_700_000_400),
                                 durationSec: 7, itermSessionID: "w0t1p0:OTHER", tty: "/dev/ttys002",
                                 cwd: "/tmp/g")
            ]
        )

        await store.save(snapshot)
        let loaded = await store.load()

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.schema, snapshot.schema)
        XCTAssertEqual(loaded?.inFlight, snapshot.inFlight)
        XCTAssertEqual(loaded?.completed, snapshot.completed)
    }

    /// Test 2: load returns nil (not throws) when file does not exist.
    func test_load_missingFile_returnsNil() async {
        let store = SessionStore(url: tempURL)
        let loaded = await store.load()
        XCTAssertNil(loaded)
    }

    /// Test 3: garbage bytes → load renames file to *.corrupt-{ts} and returns nil.
    func test_load_corruptFile_renamesAndReturnsNil() async {
        try! Data("not a json file at all".utf8).write(to: tempURL)
        let store = SessionStore(url: tempURL)

        let loaded = await store.load()
        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path),
                       "Corrupt file should have been renamed away from the original path.")

        // Sibling with .corrupt-{ts} suffix should now exist.
        let dir = tempURL.deletingLastPathComponent()
        let prefix = tempURL.lastPathComponent + ".corrupt-"
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertTrue(entries.contains(where: { $0.hasPrefix(prefix) }),
                      "Expected a sibling file with prefix \(prefix); got \(entries)")
    }

    /// Test 4: save writes the file with 0600 POSIX permissions.
    func test_save_setsFile_0600_perms() async {
        let store = SessionStore(url: tempURL)
        let snapshot = SessionsSnapshot(schema: SessionsSnapshot.currentSchema,
                                        inFlight: [:], completed: [])
        await store.save(snapshot)

        let attrs = try! FileManager.default.attributesOfItem(atPath: tempURL.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600,
                       "sessions.json must be 0600; got \(String(describing: perms))")
    }

    /// Test 5: schema-mismatched JSON → load renames + returns nil (forward-compat guard).
    func test_load_schemaMismatch_renamesAndReturnsNil() async {
        let mismatched = """
        {"schema":2,"inFlight":{},"completed":[]}
        """
        try! Data(mismatched.utf8).write(to: tempURL)
        let store = SessionStore(url: tempURL)

        let loaded = await store.load()
        XCTAssertNil(loaded)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempURL.path),
                       "Schema-mismatched file should be renamed away.")

        let dir = tempURL.deletingLastPathComponent()
        let prefix = tempURL.lastPathComponent + ".corrupt-"
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        XCTAssertTrue(entries.contains(where: { $0.hasPrefix(prefix) }),
                      "Expected a corrupt-renamed sibling for schema mismatch.")
    }
}
