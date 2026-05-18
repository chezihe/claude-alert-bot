// SessionRegistryTests.swift — Phase 2 Wave 2 (02-04 Task 2).
// 13 tests (A–M) covering ingest dispatch, threshold, dedupe, GC,
// THR-02 fallback, D2-13 auto-clear, injectTest, restore.
import XCTest
@testable import ClaudeAlertBot

@MainActor
final class SessionRegistryTests: XCTestCase {
    private var tempURL: URL!
    private var notifier: MockNotifier!

    override func setUp() async throws {
        try await super.setUp()
        tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cab-reg-\(UUID().uuidString).json")
        notifier = MockNotifier()
    }

    override func tearDown() async throws {
        let dir = tempURL.deletingLastPathComponent()
        let prefix = tempURL.lastPathComponent
        if let entries = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for name in entries where name.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }
        }
        notifier = nil
        tempURL = nil
        try await super.tearDown()
    }

    // MARK: helpers

    private func makeRegistry() -> SessionRegistry {
        let store = SessionStore(url: tempURL)
        var clock = Clock()
        clock.sleepNanoseconds = { _ in /* no-op for tests */ }
        let registry = SessionRegistry(persistence: store, clock: clock)
        return registry
    }

    private func bind(_ registry: SessionRegistry) async {
        await registry.bind(notifier: notifier)
    }

    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }

    private func suppressNo(_ id: String?) async -> Bool { false }
    private func suppressYes(_ id: String?) async -> Bool { true }

    // MARK: tests

    /// Test A — user_prompt_submit registers an InFlightStart.
    func test_ingest_userPromptSubmit_registersInFlight() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-A"
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let evt = HookEventFactory.userPromptSubmit(sessionID: sid, ts: iso(start), termProgram: "iTerm.app")
        await r.ingest(evt, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let snap = await r.snapshotForTesting()
        XCTAssertNotNil(snap.inFlight[sid])
        XCTAssertEqual(snap.inFlight[sid]?.startedAt, start)
    }

    /// Test B — D2-13: a fresh user_prompt_submit silently clears unpinned pending
    ///         Stop alerts for the same session_id.
    func test_ingest_userPromptSubmit_clearsPendingStop_D2_13() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-B"
        let pending = CompletedSession(sessionID: sid, projectName: "p",
                                       stoppedAt: Date(), durationSec: 99,
                                       itermSessionID: nil, tty: nil, cwd: nil)
        await r.seedCompletedForTesting(pending)

        let evt = HookEventFactory.userPromptSubmit(sessionID: sid, ts: iso(Date()))
        await r.ingest(evt, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let snap = await r.snapshotForTesting()
        XCTAssertFalse(snap.completed.contains(where: { $0.sessionID == sid }),
                       "D2-13 must remove pending Stop alerts for the same session_id.")
        XCTAssertNotNil(snap.inFlight[sid], "user_prompt_submit also registers in-flight start.")
    }

    func test_ingest_userPromptSubmit_preservesPinnedPendingStop_D2_13() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-B-pinned"
        let pinned = CompletedSession(sessionID: sid, projectName: "p",
                                      stoppedAt: Date(), durationSec: 99,
                                      itermSessionID: nil, tty: nil, cwd: nil,
                                      pinned: true)
        let unpinned = CompletedSession(sessionID: sid, projectName: "p",
                                        stoppedAt: Date(), durationSec: 100,
                                        itermSessionID: nil, tty: nil, cwd: nil)
        await r.seedCompletedForTesting(pinned)
        await r.seedCompletedForTesting(unpinned)

        let evt = HookEventFactory.userPromptSubmit(sessionID: sid, ts: iso(Date()))
        await r.ingest(evt, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.count, 1)
        XCTAssertEqual(snap.completed.first?.sessionID, sid)
        XCTAssertTrue(snap.completed.first?.pinned ?? false)
        XCTAssertNotNil(snap.inFlight[sid], "user_prompt_submit still registers the new in-flight start.")

        let loaded = await SessionStore(url: tempURL).load()
        XCTAssertEqual(loaded?.completed.count, 1)
        XCTAssertTrue(loaded?.completed.first?.pinned ?? false)
    }

    func test_ingest_userPromptSubmit_fromExplicitNonITerm_isIgnored() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-non-iterm-start"
        let evt = HookEventFactory.userPromptSubmit(
            sessionID: sid,
            ts: iso(Date()),
            termProgram: "Apple_Terminal"
        )

        await r.ingest(evt, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let snap = await r.snapshotForTesting()
        XCTAssertNil(snap.inFlight[sid])
        XCTAssertTrue(snap.completed.isEmpty)
        XCTAssertTrue(notifier.refreshCalls.isEmpty)
    }

    /// Test C — Stop arriving below threshold drops the alert silently.
    func test_ingest_stop_belowThreshold_dropsAlert() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-C"
        // Use a "now"-anchored, whole-second timestamp so (a) lazy GC at ingest() does not
        // evict the seed and (b) ISO8601 round-trip (no fractional seconds) preserves duration.
        let t0 = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        await r.seedInFlightForTesting(sessionID: sid, started: t0, cwd: "/x")
        let stop = HookEventFactory.stop(sessionID: sid, ts: iso(t0.addingTimeInterval(5)))

        await r.ingest(stop, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.count, 0)
        XCTAssertEqual(notifier.presentCalls.count, 0)
    }

    /// Test D — Stop above threshold emits an alert with the computed duration.
    func test_ingest_stop_aboveThreshold_emitsAlert() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-D"
        // Use a "now"-anchored, whole-second timestamp so (a) lazy GC at ingest() does not
        // evict the seed and (b) ISO8601 round-trip (no fractional seconds) preserves duration.
        let t0 = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        await r.seedInFlightForTesting(sessionID: sid, started: t0, cwd: "/x")
        let stop = HookEventFactory.stop(sessionID: sid, ts: iso(t0.addingTimeInterval(31)), termProgram: "iTerm.app")

        await r.ingest(stop, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.count, 1)
        XCTAssertEqual(snap.completed.first?.durationSec, 31)
        XCTAssertEqual(notifier.presentCalls.count, 1)
        XCTAssertEqual(notifier.presentCalls.first?.session, sid)
    }

    func test_ingest_stop_errorBelowThreshold_emitsAlert() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-error-below-threshold"
        let t0 = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        await r.seedInFlightForTesting(sessionID: sid, started: t0, cwd: "/x")
        let stop = HookEventFactory.stop(
            sessionID: sid,
            ts: iso(t0.addingTimeInterval(5)),
            termProgram: "iTerm.app",
            kind: .error
        )

        await r.ingest(stop, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let session = await r.snapshotForTesting().completed.first
        XCTAssertEqual(session?.sessionID, sid)
        XCTAssertEqual(session?.durationSec, 5)
        XCTAssertEqual(session?.kind, .error)
        XCTAssertEqual(notifier.presentCalls.map(\.session), [sid])
    }

    func test_ingest_stop_nonZeroExitCodeWithoutKind_emitsErrorBelowThreshold() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-exit-code-error"
        let t0 = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        await r.seedInFlightForTesting(sessionID: sid, started: t0, cwd: "/x")
        let stop = HookEventFactory.stop(
            sessionID: sid,
            ts: iso(t0.addingTimeInterval(5)),
            termProgram: "iTerm.app",
            exitCode: 1
        )

        await r.ingest(stop, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let session = await r.snapshotForTesting().completed.first
        XCTAssertEqual(session?.sessionID, sid)
        XCTAssertEqual(session?.durationSec, 5)
        XCTAssertEqual(session?.kind, .error)
        XCTAssertEqual(session?.exitCode, 1)
        XCTAssertEqual(notifier.presentCalls.map(\.session), [sid])
    }

    func test_ingest_stop_fromExplicitNonITerm_skipsAppendAndPresent() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-non-iterm-stop"
        let stop = HookEventFactory.stop(
            sessionID: sid,
            ts: iso(Date()),
            termProgram: "Apple_Terminal"
        )

        await r.ingest(stop, thresholdSeconds: 0, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let snap = await r.snapshotForTesting()
        XCTAssertTrue(snap.inFlight.isEmpty)
        XCTAssertTrue(snap.completed.isEmpty)
        XCTAssertTrue(notifier.presentCalls.isEmpty)
        XCTAssertTrue(notifier.refreshCalls.isEmpty)
    }

    func test_ingest_stop_fromExplicitNonITerm_clearsMatchingInFlight() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-non-iterm-existing"
        await r.seedInFlightForTesting(sessionID: sid, started: Date(), cwd: "/x")
        let stop = HookEventFactory.stop(
            sessionID: sid,
            ts: iso(Date()),
            termProgram: "Apple_Terminal"
        )

        await r.ingest(stop, thresholdSeconds: 0, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let snap = await r.snapshotForTesting()
        XCTAssertNil(snap.inFlight[sid])
        XCTAssertTrue(snap.completed.isEmpty)
        XCTAssertTrue(notifier.presentCalls.isEmpty)
        XCTAssertTrue(notifier.refreshCalls.isEmpty)

        let persisted = await SessionStore(url: tempURL).load()
        XCTAssertNil(persisted?.inFlight[sid])
    }

    func test_ingest_stop_refreshesWidgetWithFullCompletedQueue() async {
        let r = makeRegistry()
        await bind(r)
        let existing = CompletedSession(sessionID: "existing", projectName: "p",
                                        stoppedAt: Date(), durationSec: 10,
                                        itermSessionID: nil, tty: nil, cwd: nil)
        await r.seedCompletedForTesting(existing)
        let sid = "sid-D2"
        let t0 = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        await r.seedInFlightForTesting(sessionID: sid, started: t0, cwd: "/x")
        let stop = HookEventFactory.stop(sessionID: sid, ts: iso(t0.addingTimeInterval(31)))

        await r.ingest(stop, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        XCTAssertEqual(notifier.presentCalls.map(\.session), [sid])
        XCTAssertEqual(notifier.presentCalls.first?.pendingQueue, ["existing", sid])
        XCTAssertEqual(notifier.refreshCalls.last, 2)
        XCTAssertEqual(notifier.refreshQueueCalls.last, ["existing", sid])
    }

    func test_ingest_stop_refreshUsesLatestQueueAfterReentrantPresent() async {
        let r = makeRegistry()
        let reentrantNotifier = ReentrantNotifier()
        await r.bind(notifier: reentrantNotifier)
        let firstID = "sid-reentrant-1"
        let secondID = "sid-reentrant-2"
        let stoppedAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let secondStop = HookEventFactory.stop(
            sessionID: secondID,
            iTermSessionID: "w0t0p1:22222222-2222-4222-8222-222222222222",
            ts: iso(stoppedAt.addingTimeInterval(1))
        )
        reentrantNotifier.onFirstPresent = {
            await r.ingest(secondStop, thresholdSeconds: 0, soundEnabled: true,
                           suppressIfFrontmost: self.suppressNo)
        }

        let firstStop = HookEventFactory.stop(
            sessionID: firstID,
            iTermSessionID: "w0t0p1:11111111-1111-4111-8111-111111111111",
            ts: iso(stoppedAt)
        )
        await r.ingest(firstStop, thresholdSeconds: 0, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        XCTAssertEqual(reentrantNotifier.presentQueues.last, [firstID, secondID])
        XCTAssertEqual(reentrantNotifier.refreshQueueCalls.last, [firstID, secondID])
    }

    /// Test E — THR-02: orphan Stop emits with durationSec=nil regardless of threshold.
    func test_THR_02_orphanStop_emitsWithNilDuration() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-E"
        let stop = HookEventFactory.stop(sessionID: sid, ts: iso(Date()))

        await r.ingest(stop, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.count, 1)
        XCTAssertNil(snap.completed.first?.durationSec)
        XCTAssertEqual(notifier.presentCalls.count, 1)
    }

    func test_ingest_stop_propagatesExtendedPayloadFields() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-E2"
        let startedAt = Date(timeIntervalSince1970: 1_730_000_000)
        let stop = HookEventFactory.stop(sessionID: sid,
                                         ts: iso(Date()),
                                         exitCode: 2,
                                         startedAt: startedAt,
                                         kind: .error,
                                         lastOutput: "tail output")

        await r.ingest(stop, thresholdSeconds: 0, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let session = await r.snapshotForTesting().completed.first
        XCTAssertEqual(session?.kind, .error)
        XCTAssertEqual(session?.exitCode, 2)
        XCTAssertEqual(session?.startedAt, startedAt)
        XCTAssertEqual(session?.lastOutput, "tail output")
    }

    func test_ingest_notification_emitsWaitingAlert() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-notification"
        let notifiedAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let notification = HookEventFactory.notification(
            sessionID: sid,
            ts: iso(notifiedAt),
            termProgram: "iTerm.app",
            lastOutput: "Claude needs your permission to use Bash"
        )

        await r.ingest(notification, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let session = await r.snapshotForTesting().completed.first
        XCTAssertEqual(session?.sessionID, sid)
        XCTAssertEqual(session?.kind, .waiting)
        XCTAssertNil(session?.durationSec)
        XCTAssertEqual(session?.lastOutput, "Claude needs your permission to use Bash")
        XCTAssertEqual(notifier.presentCalls.map(\.session), [sid])
        XCTAssertEqual(notifier.refreshCalls.last, 1)
    }

    func test_ingest_stop_replacesUnpinnedWaitingAlertForSameSession() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-notification-stop"
        let waiting = CompletedSession(sessionID: sid, projectName: "p",
                                       stoppedAt: Date(), durationSec: nil,
                                       itermSessionID: nil, tty: nil, cwd: nil,
                                       kind: .waiting)
        await r.seedCompletedForTesting(waiting)
        let stop = HookEventFactory.stop(sessionID: sid, ts: iso(Date()))

        await r.ingest(stop, thresholdSeconds: 0, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let completed = await r.snapshotForTesting().completed
        XCTAssertEqual(completed.count, 1)
        XCTAssertEqual(completed.first?.sessionID, sid)
        XCTAssertEqual(completed.first?.kind, .success)
    }

    func test_ingest_stop_replacesUnpinnedRowsByItermSessionID() async {
        let r = makeRegistry()
        await bind(r)
        let itermUUID = "550e8400-e29b-41d4-a716-446655440000"
        let pinned = CompletedSession(sessionID: "sid-prev-pinned", projectName: "old",
                                      stoppedAt: Date(), durationSec: 40,
                                      itermSessionID: itermUUID, tty: nil, cwd: nil,
                                      pinned: true)
        let unpinned = CompletedSession(sessionID: "sid-prev-unpinned", projectName: "old",
                                        stoppedAt: Date(), durationSec: 41,
                                        itermSessionID: itermUUID, tty: nil, cwd: nil)
        await r.seedCompletedForTesting(pinned)
        await r.seedCompletedForTesting(unpinned)

        let nextStop = HookEventFactory.stop(
            sessionID: "sid-next",
            iTermSessionID: "w0t0p1:\(itermUUID)",
            ts: iso(Date()),
            termProgram: "iTerm.app"
        )
        await r.ingest(nextStop, thresholdSeconds: 0, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let completed = await r.snapshotForTesting().completed
        XCTAssertEqual(completed.count, 2)
        XCTAssertFalse(completed.contains { $0.sessionID == "sid-prev-unpinned" })
        XCTAssertEqual(completed.map(\.sessionID), ["sid-prev-pinned", "sid-next"])
    }

    func test_ingest_notification_replacesUnpinnedRowsByItermSessionID() async {
        let r = makeRegistry()
        await bind(r)
        let itermUUID = "550e8400-e29b-41d4-a716-446655440111"
        let pinned = CompletedSession(sessionID: "notif-prev-pinned", projectName: "old",
                                       stoppedAt: Date(), durationSec: 30,
                                       itermSessionID: itermUUID, tty: nil, cwd: nil,
                                       kind: .success, pinned: true)
        let unpinned = CompletedSession(sessionID: "notif-prev-unpinned", projectName: "old",
                                         stoppedAt: Date(), durationSec: 31,
                                         itermSessionID: itermUUID, tty: nil, cwd: nil,
                                         kind: .waiting)
        await r.seedCompletedForTesting(pinned)
        await r.seedCompletedForTesting(unpinned)

        let nextNotification = HookEventFactory.notification(
            sessionID: "sid-notification-next",
            iTermSessionID: "w0t0p1:\(itermUUID)",
            ts: iso(Date()),
            termProgram: "iTerm.app"
        )
        await r.ingest(nextNotification, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let completed = await r.snapshotForTesting().completed
        XCTAssertEqual(completed.count, 2)
        XCTAssertFalse(completed.contains { $0.sessionID == "notif-prev-unpinned" })
        XCTAssertEqual(completed.last?.sessionID, "sid-notification-next")
        XCTAssertEqual(completed.last?.kind, .waiting)
    }

    /// Test F — AUD-01 dedupe: same (sid, ts/2s bucket) twice → second present.playSound=false.
    func test_AUD_01_dedupe_sameKey_secondCallNoSound() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-F"
        let stoppedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let stop1 = HookEventFactory.stop(sessionID: sid, ts: iso(stoppedAt))
        let stop2 = HookEventFactory.stop(sessionID: sid, ts: iso(stoppedAt.addingTimeInterval(0.5)))

        await r.ingest(stop1, thresholdSeconds: 0, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)
        await r.ingest(stop2, thresholdSeconds: 0, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        XCTAssertEqual(notifier.presentCalls.count, 2)
        XCTAssertEqual(notifier.presentCalls[0].playSound, true)
        XCTAssertEqual(notifier.presentCalls[1].playSound, false)
    }

    /// Test G — D2-14: suppressIfFrontmost closure returning true silently drops the alert.
    func test_suppressIfFrontmost_dropsAlertSilently_D2_14() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-G"
        let stop = HookEventFactory.stop(sessionID: sid, iTermSessionID: "w0t0p1:X",
                                         ts: iso(Date()))

        await r.ingest(stop, thresholdSeconds: 0, soundEnabled: true,
                       suppressIfFrontmost: suppressYes)

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.count, 0)
        XCTAssertEqual(notifier.presentCalls.count, 0)
    }

    func test_suppressIfFrontmost_persistsClearedInFlight() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-G2"
        let start = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let startEvent = HookEventFactory.userPromptSubmit(sessionID: sid, ts: iso(start))
        await r.ingest(startEvent, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)
        let initialPersisted = await SessionStore(url: tempURL).load()
        XCTAssertNotNil(initialPersisted?.inFlight[sid])

        let stop = HookEventFactory.stop(sessionID: sid,
                                         iTermSessionID: "w0t0p1:X",
                                         ts: iso(start.addingTimeInterval(31)))
        await r.ingest(stop, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressYes)

        let snap = await r.snapshotForTesting()
        XCTAssertNil(snap.inFlight[sid])
        XCTAssertEqual(snap.completed.count, 0)
        let persisted = await SessionStore(url: tempURL).load()
        XCTAssertNil(persisted?.inFlight[sid],
                     "D2-14 suppress should persist the cleared in-flight start so it does not restore after relaunch.")
    }

    /// Test H — SESS-04: runGC removes inFlight entries older than 6 hours.
    func test_runGC_removesStaleInFlight_SESS_04() async {
        let r = makeRegistry()
        await bind(r)
        let now = Date()
        let stale = now.addingTimeInterval(-7 * 3600)
        await r.seedInFlightForTesting(sessionID: "stale", started: stale, cwd: nil)
        await r.seedInFlightForTesting(sessionID: "fresh", started: now, cwd: nil)

        await r.runGC(now: now)

        let snap = await r.snapshotForTesting()
        XCTAssertNil(snap.inFlight["stale"])
        XCTAssertNotNil(snap.inFlight["fresh"])
    }

    /// Test I — clearOne removes a single completed entry and refreshes notifier state.
    func test_clearOne_removesAndRefreshes() async {
        let r = makeRegistry()
        await bind(r)
        let a = CompletedSession(sessionID: "a", projectName: "p", stoppedAt: Date(),
                                 durationSec: 10, itermSessionID: nil, tty: nil, cwd: nil)
        let b = CompletedSession(sessionID: "b", projectName: "p", stoppedAt: Date(),
                                 durationSec: 20, itermSessionID: nil, tty: nil, cwd: nil)
        await r.seedCompletedForTesting(a)
        await r.seedCompletedForTesting(b)

        await r.clearOne(sessionID: "a")

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.map(\.sessionID), ["b"])
        XCTAssertTrue(notifier.refreshCalls.contains(1))
    }

    func test_clearUnpinned_preservesPinnedDuplicateSessionIDs() async {
        let r = makeRegistry()
        await bind(r)
        let pinned = CompletedSession(sessionID: "dup", projectName: "p", stoppedAt: Date(),
                                      durationSec: 10, itermSessionID: "target", tty: nil, cwd: nil,
                                      pinned: true)
        let unpinned = CompletedSession(sessionID: "dup", projectName: "p", stoppedAt: Date(),
                                        durationSec: 11, itermSessionID: "target", tty: nil, cwd: nil)
        await r.seedCompletedForTesting(pinned)
        await r.seedCompletedForTesting(unpinned)

        await r.clearUnpinned(sessionID: "dup")

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.count, 1)
        XCTAssertEqual(snap.completed.first?.sessionID, "dup")
        XCTAssertTrue(snap.completed.first?.pinned ?? false)
        XCTAssertTrue(notifier.refreshCalls.contains(1))

        let loaded = await SessionStore(url: tempURL).load()
        XCTAssertEqual(loaded?.completed.count, 1)
        XCTAssertTrue(loaded?.completed.first?.pinned ?? false)
    }

    func test_clearOneByAlertID_preservesPinnedDuplicateSessionID() async {
        let r = makeRegistry()
        await bind(r)
        let pinned = CompletedSession(sessionID: "dup", projectName: "p", stoppedAt: Date(),
                                      durationSec: 10, itermSessionID: "target", tty: nil, cwd: nil,
                                      pinned: true, alertID: "pinned-alert")
        let unpinned = CompletedSession(sessionID: "dup", projectName: "p", stoppedAt: Date(),
                                        durationSec: 11, itermSessionID: "target", tty: nil, cwd: nil,
                                        alertID: "new-alert")
        await r.seedCompletedForTesting(pinned)
        await r.seedCompletedForTesting(unpinned)

        await r.clearOne(alertID: "new-alert")

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.map(\.id), ["pinned-alert"])
        XCTAssertTrue(snap.completed.first?.pinned ?? false)
        XCTAssertTrue(notifier.refreshCalls.contains(1))
    }

    func test_togglePinByAlertID_targetsOnlyMatchingDuplicateSessionID() async {
        let r = makeRegistry()
        await bind(r)
        let pinned = CompletedSession(sessionID: "dup", projectName: "p", stoppedAt: Date(),
                                      durationSec: 10, itermSessionID: "target", tty: nil, cwd: nil,
                                      pinned: true, alertID: "pinned-alert")
        let unpinned = CompletedSession(sessionID: "dup", projectName: "p", stoppedAt: Date(),
                                        durationSec: 11, itermSessionID: "target", tty: nil, cwd: nil,
                                        alertID: "new-alert")
        await r.seedCompletedForTesting(pinned)
        await r.seedCompletedForTesting(unpinned)

        await r.togglePin(alertID: "new-alert")

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.map(\.id), ["pinned-alert", "new-alert"])
        XCTAssertEqual(snap.completed.map(\.pinned), [true, true])
    }

    func test_markUnavailable_keepsRowAndRefreshes() async {
        let r = makeRegistry()
        await bind(r)
        let session = CompletedSession(sessionID: "a", projectName: "p", stoppedAt: Date(),
                                       durationSec: 10, itermSessionID: nil, tty: nil, cwd: nil)
        await r.seedCompletedForTesting(session)

        await r.markUnavailable(sessionID: "a")

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.map(\.sessionID), ["a"])
        XCTAssertFalse(snap.completed.first?.available ?? true)
        XCTAssertTrue(notifier.refreshCalls.contains(1))
    }

    func test_markUnavailableByAlertID_targetsOnlyMatchingDuplicateSessionID() async {
        let r = makeRegistry()
        await bind(r)
        let pinned = CompletedSession(sessionID: "dup", projectName: "p", stoppedAt: Date(),
                                      durationSec: 10, itermSessionID: "target", tty: nil, cwd: nil,
                                      pinned: true, alertID: "pinned-alert")
        let unpinned = CompletedSession(sessionID: "dup", projectName: "p", stoppedAt: Date(),
                                        durationSec: 11, itermSessionID: "target", tty: nil, cwd: nil,
                                        alertID: "new-alert")
        await r.seedCompletedForTesting(pinned)
        await r.seedCompletedForTesting(unpinned)

        await r.markUnavailable(alertID: "new-alert")

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.map(\.available), [true, false])
        XCTAssertTrue(notifier.refreshCalls.contains(2))
    }

    /// Test J — clearAll empties the queue and broadcasts count=0.
    func test_clearAll_emptiesQueue() async {
        let r = makeRegistry()
        await bind(r)
        for sid in ["x", "y", "z"] {
            await r.seedCompletedForTesting(
                CompletedSession(sessionID: sid, projectName: "p", stoppedAt: Date(),
                                 durationSec: 1, itermSessionID: nil, tty: nil, cwd: nil)
            )
        }

        await r.clearAll()

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.count, 0)
        XCTAssertTrue(notifier.refreshCalls.contains(0))
    }

    func test_togglePin_togglesAndPersistsSession() async {
        let r = makeRegistry()
        await bind(r)
        let session = CompletedSession(sessionID: "pin-me", projectName: "p", stoppedAt: Date(),
                                       durationSec: 10, itermSessionID: nil, tty: nil, cwd: nil)
        await r.seedCompletedForTesting(session)

        await r.togglePin(sessionID: "pin-me")

        let snap = await r.snapshotForTesting()
        XCTAssertTrue(snap.completed.first?.pinned ?? false)
        XCTAssertTrue(notifier.refreshCalls.contains(1))

        let loaded = await SessionStore(url: tempURL).load()
        XCTAssertTrue(loaded?.completed.first?.pinned ?? false)
    }

    func test_clearAll_preservesPinnedSessions() async {
        let r = makeRegistry()
        await bind(r)
        let pinned = CompletedSession(sessionID: "pinned", projectName: "p", stoppedAt: Date(),
                                      durationSec: 10, itermSessionID: nil, tty: nil, cwd: nil,
                                      pinned: true)
        let unpinned = CompletedSession(sessionID: "unpinned", projectName: "p", stoppedAt: Date(),
                                        durationSec: 10, itermSessionID: nil, tty: nil, cwd: nil)
        await r.seedCompletedForTesting(pinned)
        await r.seedCompletedForTesting(unpinned)

        await r.clearAll()

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.map(\.sessionID), ["pinned"])
        XCTAssertTrue(snap.completed.first?.pinned ?? false)
        XCTAssertTrue(notifier.refreshCalls.contains(1))
    }

    func test_workspaceFrontmostObserver_autoClearSkipsPinnedSessionsBeforeMatching() {
        let src = readWorkspaceFrontmostObserverSource()
        guard let loopStart = src.range(of: "for session in pending {") else {
            return XCTFail("WorkspaceFrontmostObserver must iterate pending sessions")
        }
        guard let matchStart = src.range(
            of: "AppleScriptHelper.shared.frontmostMatches",
            range: loopStart.upperBound..<src.endIndex
        ) else {
            return XCTFail("WorkspaceFrontmostObserver must still perform frontmost matching")
        }
        let beforeMatch = String(src[loopStart.upperBound..<matchStart.lowerBound])

        XCTAssertTrue(beforeMatch.contains("session.pinned"),
                      "Pinned alerts must not be auto-cleared when iTerm2 becomes frontmost.")
        XCTAssertTrue(beforeMatch.contains("continue"),
                      "Pinned alerts should be skipped before the AppleScript matching path.")
        XCTAssertTrue(src.contains("SessionRegistry.shared.clearUnpinned(sessionID: session.sessionID)"),
                      "Frontmost auto-clear must remove only unpinned rows for the matched sessionID.")
        XCTAssertFalse(src.contains("SessionRegistry.shared.clearOne(sessionID: session.sessionID)"),
                       "Frontmost auto-clear must not call clearOne because duplicate pinned rows can share the sessionID.")
    }

    func test_ingestStop_mutedProjectSkipsAppendAndPresent() async {
        let r = makeRegistry()
        await bind(r)
        let sid = "sid-muted"
        let project = "muted-\(UUID().uuidString)"
        let stoppedAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        SettingsStore.shared.mute(project: project, duration: 3600, now: stoppedAt)
        defer { SettingsStore.shared.unmute(project: project) }
        await r.seedInFlightForTesting(sessionID: sid,
                                       started: stoppedAt.addingTimeInterval(-31),
                                       cwd: "/tmp/\(project)")
        let stop = HookEventFactory.stop(sessionID: sid,
                                         cwd: "/tmp/\(project)",
                                         ts: iso(stoppedAt))

        await r.ingest(stop, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let snap = await r.snapshotForTesting()
        XCTAssertNil(snap.inFlight[sid])
        XCTAssertEqual(snap.completed.count, 0)
        XCTAssertEqual(notifier.presentCalls.count, 0)
    }

    func test_ingestStop_usesCurrentTimeForMutedProjectExpiry() async {
        let muteStart = Date(timeIntervalSince1970: 1_700_000_000)
        let stoppedAt = muteStart.addingTimeInterval(120)
        let arrivalNow = muteStart.addingTimeInterval(3_700)
        var clock = Clock()
        clock.now = { arrivalNow }
        clock.sleepNanoseconds = { _ in }
        let r = SessionRegistry(persistence: SessionStore(url: tempURL), clock: clock)
        await bind(r)
        let sid = "sid-muted-expired"
        let project = "muted-expired-\(UUID().uuidString)"
        SettingsStore.shared.mute(project: project, duration: 3_600, now: muteStart)
        defer { SettingsStore.shared.unmute(project: project) }
        await r.seedInFlightForTesting(sessionID: sid,
                                       started: stoppedAt.addingTimeInterval(-31),
                                       cwd: "/tmp/\(project)")
        let stop = HookEventFactory.stop(sessionID: sid,
                                         cwd: "/tmp/\(project)",
                                         ts: iso(stoppedAt))

        await r.ingest(stop, thresholdSeconds: 30, soundEnabled: true,
                       suppressIfFrontmost: suppressNo)

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.map(\.sessionID), [sid])
        XCTAssertEqual(notifier.presentCalls.count, 1)
    }

    /// Test K — D2-21: injectTest appends a test fixture and schedules auto-dismiss.
    /// With stub clock.sleepNanoseconds returning immediately, the dismiss Task fires fast.
    func test_injectTest_appendsAndScheduleAutoDismiss() async {
        let r = makeRegistry()
        await bind(r)

        await r.injectTest(soundEnabled: true)

        // Right after injection the test row is present.
        let pre = await r.snapshotForTesting()
        XCTAssertEqual(pre.completed.count, 1)
        XCTAssertTrue(pre.completed.first?.sessionID.hasPrefix("test-") == true)
        XCTAssertEqual(notifier.presentCalls.count, 1)

        // The auto-dismiss Task hops back into the actor; spin briefly waiting for it.
        for _ in 0..<50 {
            let snap = await r.snapshotForTesting()
            if snap.completed.isEmpty && notifier.refreshCalls.contains(0) { break }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        let post = await r.snapshotForTesting()
        XCTAssertEqual(post.completed.count, 0,
                       "injectTest should auto-dismiss unpinned rows after sleepNanoseconds returns.")
        XCTAssertTrue(notifier.refreshCalls.contains(0))
    }

    func test_injectTest_autoDismissPreservesPinnedTestAlert() async {
        let gate = SleepGate()
        var clock = Clock()
        clock.sleepNanoseconds = { _ in await gate.wait() }
        let r = SessionRegistry(persistence: SessionStore(url: tempURL), clock: clock)
        await bind(r)

        await r.injectTest(soundEnabled: true)
        let pre = await r.snapshotForTesting()
        let alertID = try! XCTUnwrap(pre.completed.first?.id)

        await r.togglePin(alertID: alertID)
        let refreshCountBeforeRelease = notifier.refreshCalls.count
        await gate.release()

        for _ in 0..<50 {
            if notifier.refreshCalls.count > refreshCountBeforeRelease { break }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        let post = await r.snapshotForTesting()
        XCTAssertEqual(post.completed.map(\.id), [alertID])
        XCTAssertTrue(post.completed.first?.pinned ?? false,
                      "Pinned test alert must survive the synthetic auto-dismiss timer.")
        XCTAssertFalse(notifier.refreshCalls.contains(0))
    }

    func test_injectTest_pinnedAlertStaysTransientAfterAutoDismiss() async {
        let gate = SleepGate()
        var clock = Clock()
        clock.sleepNanoseconds = { _ in await gate.wait() }
        let r = SessionRegistry(persistence: SessionStore(url: tempURL), clock: clock)
        await bind(r)

        await r.injectTest(soundEnabled: true)
        let pre = await r.snapshotForTesting()
        let alertID = try! XCTUnwrap(pre.completed.first?.id)

        await r.togglePin(alertID: alertID)
        await gate.release()

        for _ in 0..<50 {
            let snap = await r.snapshotForTesting()
            if snap.completed.map(\.id) == [alertID] { break }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        let persisted = await SessionStore(url: tempURL).load()
        XCTAssertFalse(persisted?.completed.contains(where: { $0.id == alertID }) ?? false,
                       "Pinned test alert must remain in memory only and never restore from disk.")

        let restored = SessionRegistry(persistence: SessionStore(url: tempURL), clock: clock)
        await restored.restore()
        let restoredSnapshot = await restored.snapshotForTesting()
        XCTAssertFalse(restoredSnapshot.completed.contains(where: { $0.id == alertID }))
    }

    func test_injectTest_refreshesWidgetWithFullInMemoryQueue() async {
        let r = makeRegistry()
        await bind(r)
        let existing = CompletedSession(sessionID: "existing", projectName: "p",
                                        stoppedAt: Date(), durationSec: 10,
                                        itermSessionID: nil, tty: nil, cwd: nil)
        await r.seedCompletedForTesting(existing)

        await r.injectTest(soundEnabled: true)

        guard let testSessionID = notifier.presentCalls.last?.session else {
            return XCTFail("injectTest should present the synthetic session.")
        }
        XCTAssertEqual(notifier.presentCalls.count, 1)
        XCTAssertTrue(notifier.refreshCalls.contains(2))
        XCTAssertTrue(notifier.refreshQueueCalls.contains(["existing", testSessionID]))
    }

    /// Test L — D2-22: injectTest must not persist the test row to disk.
    func test_injectTest_notPersisted() async {
        let r = makeRegistry()
        await bind(r)
        await r.injectTest(soundEnabled: false)

        // The store at tempURL should either not exist or contain no test- row.
        if FileManager.default.fileExists(atPath: tempURL.path) {
            let data = try! Data(contentsOf: tempURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snap = try! decoder.decode(SessionsSnapshot.self, from: data)
            XCTAssertFalse(snap.completed.contains { $0.sessionID.hasPrefix("test-") },
                           "Test fixture must not be persisted (D2-22).")
        }
    }

    /// Test M — restore() repopulates the registry from disk on boot.
    func test_restore_loadsCompletedQueue() async {
        // Seed disk via a separate SessionStore at the same URL.
        let seedStore = SessionStore(url: tempURL)
        let seeded = SessionsSnapshot(
            schema: SessionsSnapshot.currentSchema,
            inFlight: [:],
            completed: [
                CompletedSession(sessionID: "restored",
                                 projectName: "p",
                                 stoppedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                 durationSec: 99,
                                 itermSessionID: nil, tty: nil, cwd: nil)
            ]
        )
        await seedStore.save(seeded)

        let r = makeRegistry()
        await bind(r)
        await r.restore()

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.map(\.sessionID), ["restored"])
        XCTAssertTrue(notifier.refreshCalls.contains(1))
    }

    func test_restore_dropsPersistedSyntheticTestFixture() async {
        let seedStore = SessionStore(url: tempURL)
        var synthetic = CompletedSession.testFixture()
        synthetic.pinned = true
        let real = CompletedSession(sessionID: "test-real",
                                    projectName: "p",
                                    stoppedAt: Date(timeIntervalSince1970: 1_700_000_100),
                                    durationSec: 31,
                                    itermSessionID: nil,
                                    tty: nil,
                                    cwd: nil,
                                    pinned: true,
                                    alertID: "real-alert")
        let seeded = SessionsSnapshot(schema: SessionsSnapshot.currentSchema,
                                      inFlight: [:],
                                      completed: [synthetic, real])
        await seedStore.save(seeded)

        let r = makeRegistry()
        await bind(r)
        await r.restore()

        let snap = await r.snapshotForTesting()
        XCTAssertEqual(snap.completed.map(\.id), ["real-alert"])
        XCTAssertTrue(notifier.refreshCalls.contains(1))

        let cleaned = await SessionStore(url: tempURL).load()
        XCTAssertEqual(cleaned?.completed.map(\.id), ["real-alert"])
    }

    private func readWorkspaceFrontmostObserverSource(_ thisFile: StaticString = #filePath) -> String {
        let here = URL(fileURLWithPath: "\(thisFile)")
        let repoRoot = here.deletingLastPathComponent().deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/WorkspaceFrontmostObserver.swift")
        guard let data = try? String(contentsOf: target, encoding: .utf8) else {
            XCTFail("Could not read App/WorkspaceFrontmostObserver.swift at \(target.path)")
            return ""
        }
        return data
    }
}

private actor SleepGate {
    private var released = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class ReentrantNotifier: NotifierProtocol {
    var onFirstPresent: (() async -> Void)?
    private(set) var presentQueues: [[String]] = []
    private(set) var refreshQueueCalls: [[String]] = []
    private var didReenter = false

    func present(session: CompletedSession, pendingQueue: [CompletedSession], playSoundOnce: Bool) async {
        presentQueues.append(pendingQueue.map(\.sessionID))
        guard !didReenter else { return }
        didReenter = true
        await onFirstPresent?()
    }

    func refreshQueueState(completed: [CompletedSession], count: Int) async {
        refreshQueueCalls.append(completed.map(\.sessionID))
    }
}
