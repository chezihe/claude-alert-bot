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
                                 durationSec: 42, itermSessionID: "UUID", tty: "/dev/ttys001",
                                 cwd: "/tmp/a"),
                CompletedSession(sessionID: "c2", projectName: "beta",
                                 stoppedAt: Date(timeIntervalSince1970: 1_700_000_300),
                                 durationSec: nil, itermSessionID: nil, tty: nil, cwd: nil),
                CompletedSession(sessionID: "c3", projectName: "gamma",
                                 stoppedAt: Date(timeIntervalSince1970: 1_700_000_400),
                                 durationSec: 7, itermSessionID: "OTHER", tty: "/dev/ttys002",
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

    // MARK: - D3-03 / D3-04 migration regression (Phase 3 03-03)

    /// D3-03 — load() must strip the wXtYpZ: prefix in-memory.
    func test_load_migratesEnvelopeFormatItermID() async throws {
        let snap = SessionsSnapshot(
            schema: 1,
            inFlight: [:],
            completed: [
                CompletedSession(
                    sessionID: "test-1",
                    projectName: "MigrateMe",
                    stoppedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    durationSec: 31,
                    itermSessionID: "w0t0p1:79C4699F-1234-5678-9ABC-DEF012345678",
                    tty: "/dev/ttys001",
                    cwd: "/tmp"
                )
            ]
        )
        let store = SessionStore(url: tempURL)
        await store.save(snap)
        let loaded = await store.load()
        XCTAssertEqual(loaded?.completed.first?.itermSessionID, "79C4699F-1234-5678-9ABC-DEF012345678",
                       "D3-03: load() must strip the wXtYpZ: prefix in-memory")
    }

    /// D3-04 idempotency — already-normalized value passes through unchanged.
    func test_load_idempotentWhenAlreadyNormalized() async throws {
        let snap = SessionsSnapshot(
            schema: 1,
            inFlight: [:],
            completed: [
                CompletedSession(
                    sessionID: "test-2",
                    projectName: "AlreadyClean",
                    stoppedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    durationSec: 31,
                    itermSessionID: "79C4699F-1234-5678-9ABC-DEF012345678",
                    tty: "/dev/ttys001",
                    cwd: "/tmp"
                )
            ]
        )
        let store = SessionStore(url: tempURL)
        await store.save(snap)
        let loaded = await store.load()
        XCTAssertEqual(loaded?.completed.first?.itermSessionID, "79C4699F-1234-5678-9ABC-DEF012345678",
                       "D3-04 idempotency: already-normalized value must pass through unchanged")
    }

    /// THR-02 orphan path — nil itermSessionID must survive migration unchanged.
    func test_load_handlesNilItermSessionIDDuringMigration() async throws {
        let snap = SessionsSnapshot(
            schema: 1,
            inFlight: [:],
            completed: [
                CompletedSession(
                    sessionID: "test-3",
                    projectName: "NoITermID",
                    stoppedAt: Date(timeIntervalSince1970: 1_700_000_000),
                    durationSec: nil,   // THR-02 orphan path
                    itermSessionID: nil,
                    tty: nil,
                    cwd: nil
                )
            ]
        )
        let store = SessionStore(url: tempURL)
        await store.save(snap)
        let loaded = await store.load()
        XCTAssertNil(loaded?.completed.first?.itermSessionID,
                     "Migration must preserve nil itermSessionID (orphan path).")
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
