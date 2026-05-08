// App/SessionRegistry.swift — Phase 2 actor (SESS-01..04, THR-01/02, AUD-01).
// RESEARCH Pattern 2 (lines 345-475) is the canonical template.
// PATTERNS.md §SessionRegistry: actor isolation closes Pitfall #9 by construction.
// Pitfall #11: restore() must complete before listener.start() — AppDelegate (Wave 6) enforces.
import Foundation
import os

@MainActor protocol NotifierProtocol: AnyObject {
    func present(session: CompletedSession, playSoundOnce: Bool) async
    func refreshQueueState(completed: [CompletedSession], count: Int) async
}

struct Clock {
    var now: () -> Date = { Date() }
    var sleepNanoseconds: (UInt64) async throws -> Void = {
        try await Task.sleep(nanoseconds: $0)
    }
}

actor SessionRegistry {
    static let shared = SessionRegistry(persistence: SessionStore.atDefaultLocation())

    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "registry")
    private let persistence: SessionStore
    private weak var notifier: (any NotifierProtocol)?
    private let clock: Clock

    private var inFlight: [String: InFlightStart] = [:]
    private var completed: [CompletedSession] = []
    private var dedupeSet: Set<DedupeKey> = []

    init(persistence: SessionStore, clock: Clock = Clock()) {
        self.persistence = persistence
        self.clock = clock
    }

    func bind(notifier: any NotifierProtocol) {
        self.notifier = notifier
    }

    /// Pitfall #11 — call before listener.start(). Idempotent.
    func restore() async {
        guard let snap = await persistence.load() else { return }
        self.inFlight = snap.inFlight
        self.completed = snap.completed
        let n = self.notifier
        let snapshot = self.completed
        let count = snapshot.count
        await n?.refreshQueueState(completed: snapshot, count: count)
        log.notice("restore: inFlight=\(snap.inFlight.count) completed=\(snap.completed.count)")
    }

    func ingest(_ event: HookEvent,
                thresholdSeconds: Int,
                soundEnabled: Bool,
                suppressIfFrontmost: @Sendable (String?) async -> Bool) async {
        // Lazy GC kick (Pattern 6 third trigger)
        await runGC()
        switch event.event {
        case "user_prompt_submit": await handleStart(event)
        case "stop": await handleStop(event,
                                     thresholdSeconds: thresholdSeconds,
                                     soundEnabled: soundEnabled,
                                     suppressIfFrontmost: suppressIfFrontmost)
        default: log.warning("unknown event=\(event.event, privacy: .public)")
        }
    }

    private func handleStart(_ event: HookEvent) async {
        guard let sid = event.session_id, let ts = parseTS(event.ts) else { return }
        // D2-13 — silently remove pending stop alert for same sid.
        let before = completed.count
        completed.removeAll(where: { $0.sessionID == sid })
        if completed.count < before {
            log.notice("D2-13 auto-clear session=\(sid, privacy: .public)")
        }
        inFlight[sid] = InFlightStart(startedAt: ts, cwd: event.cwd)
        await persist()
        let snapshot = self.completed
        let count = snapshot.count
        let n = self.notifier
        await n?.refreshQueueState(completed: snapshot, count: count)
    }

    private func handleStop(_ event: HookEvent,
                            thresholdSeconds: Int,
                            soundEnabled: Bool,
                            suppressIfFrontmost: @Sendable (String?) async -> Bool) async {
        guard let sid = event.session_id, let stoppedAt = parseTS(event.ts) else { return }
        // D2-14 cheap-query (only relevant when permission granted — caller decides via closure)
        if await suppressIfFrontmost(event.iterm_session_id) {
            log.notice("D2-14 pre-suppress session=\(sid, privacy: .public)")
            inFlight.removeValue(forKey: sid)
            return
        }
        // AUD-01 dedupe (sound-only scope per D2-20)
        let key = DedupeKey.from(sessionID: sid, at: stoppedAt)
        let isDup = !dedupeSet.insert(key).inserted
        // Threshold + THR-02 fallback
        let durationSec: Int? = {
            guard let start = inFlight.removeValue(forKey: sid)?.startedAt else { return nil }
            return Int(stoppedAt.timeIntervalSince(start))
        }()
        let passes: Bool = {
            switch durationSec {
            case .some(let d): return d >= thresholdSeconds
            case .none:        return true   // THR-02 — never silently drop
            }
        }()
        guard passes else {
            log.notice("THR-01 below-threshold session=\(sid, privacy: .public) dur=\(durationSec ?? -1)")
            await persist()
            return
        }
        let session = CompletedSession(
            sessionID: sid,
            projectName: ProjectName.derive(cwd: event.cwd, claudeProjectDir: event.claude_project_dir),
            stoppedAt: stoppedAt,
            durationSec: durationSec,
            itermSessionID: event.iterm_session_id,
            tty: event.tty,
            cwd: event.cwd
        )
        completed.append(session)
        await persist()
        let n = self.notifier
        await n?.present(session: session, playSoundOnce: soundEnabled && !isDup)
    }

    /// SESS-04 — 6h GC. Called from ingest (lazy), wake observer (Wave 4), and timer (Wave 4).
    func runGC(now: Date? = nil) async {
        let n = now ?? clock.now()
        let sixHours: TimeInterval = 6 * 3600
        let stale = inFlight.filter { n.timeIntervalSince($0.value.startedAt) > sixHours }
        for (sid, _) in stale {
            inFlight.removeValue(forKey: sid)
            log.notice("GC stale in-flight session=\(sid, privacy: .public)")
        }
        if !stale.isEmpty { await persist() }
    }

    func clearOne(sessionID: String) async {
        completed.removeAll(where: { $0.sessionID == sessionID })
        await persist()
        let snapshot = self.completed
        let count = snapshot.count
        let n = self.notifier
        await n?.refreshQueueState(completed: snapshot, count: count)
        log.notice("clearOne session=\(sessionID, privacy: .public)")
    }

    /// Read-only snapshot of pending completed sessions. Used by 02-09 WorkspaceFrontmostObserver (D2-15).
    /// Returns a copy so iteration outside the actor cannot data-race the queue.
    func peekPending() -> [CompletedSession] {
        Array(completed)
    }

    func clearAll() async {
        completed.removeAll()
        await persist()
        let n = self.notifier
        await n?.refreshQueueState(completed: [], count: 0)
        log.notice("clearAll")
    }

    /// D2-21 — synthetic injection that walks the standard alert path but does NOT persist.
    func injectTest(soundEnabled: Bool) async {
        let session = CompletedSession.testFixture()
        completed.append(session)   // in-memory only — NO `await persist()` (D2-22)
        let n = self.notifier
        await n?.present(session: session, playSoundOnce: soundEnabled)
        // Auto-dismiss after 30s (D2-21). Clock injection enables fast-forward in tests.
        let sid = session.sessionID
        Task { [weak self, clock = self.clock] in
            try? await clock.sleepNanoseconds(30 * 1_000_000_000)
            await self?.clearOne(sessionID: sid)
        }
    }

    // MARK: helpers

    private func persist() async {
        let snap = SessionsSnapshot(schema: SessionsSnapshot.currentSchema,
                                    inFlight: inFlight,
                                    completed: completed)
        await persistence.save(snap)
    }

    private func parseTS(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        let f = ISO8601DateFormatter()
        return f.date(from: s)
    }

    #if DEBUG
    /// Test seams — never used in production code.
    func seedCompletedForTesting(_ s: CompletedSession) { completed.append(s) }
    func seedInFlightForTesting(sessionID: String, started: Date, cwd: String?) {
        inFlight[sessionID] = InFlightStart(startedAt: started, cwd: cwd)
    }
    func snapshotForTesting() -> (inFlight: [String: InFlightStart], completed: [CompletedSession]) {
        (inFlight, completed)
    }
    #endif
}
