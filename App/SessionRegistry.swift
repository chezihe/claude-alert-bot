// App/SessionRegistry.swift — Phase 2 actor (SESS-01..04, THR-01/02, AUD-01).
// RESEARCH Pattern 2 (lines 345-475) is the canonical template.
// PATTERNS.md §SessionRegistry: actor isolation closes Pitfall #9 by construction.
// Pitfall #11: restore() must complete before listener.start() — AppDelegate (Wave 6) enforces.
import Foundation
import os

@MainActor protocol NotifierProtocol: AnyObject {
    func present(session: CompletedSession, pendingQueue: [CompletedSession], playSoundOnce: Bool) async
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
    /// Formatter construction is expensive — cache both accepted ISO-8601 variants per actor.
    private let isoFormatter = ISO8601DateFormatter()
    private let fractionalISOFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter
    }()

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
        let restoredCompleted = snap.completed.filter { !Self.isSyntheticTestFixture($0) }
        self.completed = restoredCompleted
        if restoredCompleted.count != snap.completed.count {
            await persist()
        }
        await notifyQueueChanged()
        log.notice("restore: inFlight=\(snap.inFlight.count) completed=\(self.completed.count)")
    }

    func ingest(_ event: HookEvent,
                thresholdSeconds: Int,
                soundEnabled: Bool,
                suppressIfFrontmost: @Sendable (String?) async -> Bool) async {
        // Lazy GC kick (Pattern 6 third trigger)
        await runGC()
        guard Self.isSupportedTerminal(event.term_program) else {
            await discardUnsupportedTerminalEvent(event)
            return
        }
        switch event.event {
        case "user_prompt_submit": await handleStart(event)
        case "notification": await handleNotification(event, soundEnabled: soundEnabled)
        case "question_answered": await handleQuestionAnswered(event)
        case "stop": await handleStop(event,
                                     thresholdSeconds: thresholdSeconds,
                                     soundEnabled: soundEnabled,
                                     suppressIfFrontmost: suppressIfFrontmost)
        default: log.warning("unknown event=\(event.event, privacy: .public)")
        }
    }

    private func handleStart(_ event: HookEvent) async {
        guard let sid = event.session_id, let ts = parseTS(event.ts) else { return }
        // D2-13 — silently remove unpinned pending stop alerts for same sid.
        let before = completed.count
        completed.removeAll(where: { $0.sessionID == sid && !$0.pinned })
        if completed.count < before {
            log.notice("D2-13 auto-clear session=\(sid, privacy: .public)")
        }
        inFlight[sid] = InFlightStart(startedAt: ts, cwd: event.cwd)
        await persist()
        await notifyQueueChanged()
    }

    private func handleStop(_ event: HookEvent,
                            thresholdSeconds: Int,
                            soundEnabled: Bool,
                            suppressIfFrontmost: @Sendable (String?) async -> Bool) async {
        guard let sid = event.session_id, let stoppedAt = parseTS(event.ts) else { return }
        // Removing the waiting alert in memory is not enough — early-return paths below must
        // refresh the widget too, or the cleared alert lingers on screen (e.g. the user answered
        // a confirmation prompt while iTerm2 was frontmost → D2-14 suppress).
        let clearedWaiting = clearUnpinnedWaitingAlert(sessionID: sid)
        // Reorder guard: cab-report.sh's stop hook lags (it waits up to ~0.8s reading the
        // transcript for last_output). If the user replied within that window, a newer
        // user_prompt_submit landed first and this stop's ts predates that in-flight start —
        // the stop is stale. Discard it without creating an alert; the new turn stays in flight.
        if await discardStaleStopIfNeeded(sessionID: sid,
                                           stoppedAt: stoppedAt,
                                           clearedWaiting: clearedWaiting) { return }
        // D2-14 cheap-query (only relevant when permission granted — caller decides via closure)
        let shouldSuppress = await suppressIfFrontmost(event.iterm_session_id)
        // The actor can accept a newer prompt while the frontmost query is suspended.
        // Re-check before consuming inFlight so this older stop cannot remove the new turn.
        if await discardStaleStopIfNeeded(sessionID: sid,
                                           stoppedAt: stoppedAt,
                                           clearedWaiting: clearedWaiting) { return }
        if shouldSuppress {
            log.notice("D2-14 pre-suppress session=\(sid, privacy: .public)")
            inFlight.removeValue(forKey: sid)
            await persist()
            if clearedWaiting { await notifyQueueChanged() }
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
        let effectiveKind: AlertKind = {
            if event.exit_code.map({ $0 != 0 }) == true { return .error }
            return event.kind ?? .success
        }()
        let passes: Bool = {
            if effectiveKind == .error { return true }
            switch durationSec {
            case .some(let d): return d >= thresholdSeconds
            case .none:        return true   // THR-02 — never silently drop
            }
        }()
        guard passes else {
            log.notice("THR-01 below-threshold session=\(sid, privacy: .public) dur=\(durationSec ?? -1)")
            await persist()
            if clearedWaiting { await notifyQueueChanged() }
            return
        }
        let projectName = ProjectName.derive(cwd: event.cwd, claudeProjectDir: event.claude_project_dir)
        let muteCheckNow = clock.now()
        if await MainActor.run(body: { SettingsStore.shared.isMuted(project: projectName, now: muteCheckNow) }) {
            log.notice("ingest_stop muted project=\(projectName, privacy: .public) session=\(sid, privacy: .public)")
            await persist()
            if clearedWaiting { await notifyQueueChanged() }
            return
        }
        let session = CompletedSession(
            sessionID: sid,
            projectName: projectName,
            stoppedAt: stoppedAt,
            durationSec: durationSec,
            itermSessionID: iTermSessionID.uuid(fromRaw: event.iterm_session_id),   // D3-02 — UUID-only on write
            tty: event.tty,
            cwd: event.cwd,
            kind: effectiveKind,
            exitCode: event.exit_code,
            startedAt: event.started_at,
            lastOutput: event.last_output
        )
        clearUnpinnedByItermSession(session.itermSessionID)
        completed.append(session)
        await persist()
        let snapshot = self.completed
        await notifier?.present(session: session, pendingQueue: snapshot, playSoundOnce: soundEnabled && !isDup)
        await notifyQueueChanged()
    }

    private func handleNotification(_ event: HookEvent, soundEnabled: Bool) async {
        guard let sid = event.session_id, let notifiedAt = parseTS(event.ts) else { return }
        let projectName = ProjectName.derive(cwd: event.cwd, claudeProjectDir: event.claude_project_dir)
        let muteCheckNow = clock.now()
        if await MainActor.run(body: { SettingsStore.shared.isMuted(project: projectName, now: muteCheckNow) }) {
            log.notice("ingest_notification muted project=\(projectName, privacy: .public) session=\(sid, privacy: .public)")
            return
        }
        let key = DedupeKey.from(sessionID: sid, at: notifiedAt)
        let isDup = !dedupeSet.insert(key).inserted
        clearUnpinnedWaitingAlert(sessionID: sid)
        let session = CompletedSession(
            sessionID: sid,
            projectName: projectName,
            stoppedAt: notifiedAt,
            durationSec: nil,
            itermSessionID: iTermSessionID.uuid(fromRaw: event.iterm_session_id),
            tty: event.tty,
            cwd: event.cwd,
            kind: event.kind ?? .waiting,
            exitCode: event.exit_code,
            startedAt: event.started_at,
            lastOutput: event.last_output
        )
        clearUnpinnedByItermSession(session.itermSessionID)
        completed.append(session)
        await persist()
        let snapshot = self.completed
        await notifier?.present(session: session, pendingQueue: snapshot, playSoundOnce: soundEnabled && !isDup)
        await notifyQueueChanged()
    }

    /// A "Claude's questions" dialog (AskUserQuestion / elicitation_dialog) was resolved —
    /// Claude Code fires PostToolUse(AskUserQuestion) when the user answers or dismisses it.
    /// That tool result is the only signal the answer happened: no stop / user_prompt_submit
    /// follows, so without this the waiting alert created by handleNotification lingers until
    /// the next same-session event happens to arrive (often minutes later, or only when the
    /// next question appears). Clear it now; leave inFlight untouched so the turn's eventual
    /// stop still computes duration. Mirrors the stale-stop clear path.
    private func handleQuestionAnswered(_ event: HookEvent) async {
        guard let sid = event.session_id else { return }
        guard clearUnpinnedWaitingAlert(sessionID: sid) else { return }
        await persist()
        await notifyQueueChanged()
        log.notice("question_answered cleared waiting session=\(sid, privacy: .public)")
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
        // Dedupe keys are 2s buckets — anything 6h older than the newest key can never
        // match again. Without pruning, the set grows unbounded over the app's
        // weeks-long residency. The window is anchored to the newest EVENT time (not
        // wall clock) so backdated event timestamps stay comparable to each other.
        if let newestBucket = dedupeSet.map(\.bucketedTS).max() {
            let cutoffBucket = newestBucket - Int(sixHours) / 2
            dedupeSet = dedupeSet.filter { $0.bucketedTS >= cutoffBucket }
        }
        if !stale.isEmpty { await persist() }
    }

    func clearOne(alertID: String) async {
        completed.removeAll(where: { $0.id == alertID })
        await persist()
        await notifyQueueChanged()
        log.notice("clearOne alert=\(alertID, privacy: .public)")
    }

    func clearUnpinned(sessionID: String) async {
        completed.removeAll(where: { $0.sessionID == sessionID && !$0.pinned })
        await persist()
        await notifyQueueChanged()
        log.notice("clearUnpinned session=\(sessionID, privacy: .public)")
    }

    func markUnavailable(alertID: String) async {
        guard let idx = completed.firstIndex(where: { $0.id == alertID }) else {
            log.notice("markUnavailable alert=\(alertID, privacy: .public) ignored (no longer in queue)")
            return
        }
        completed[idx].available = false
        await persist()
        await notifyQueueChanged()
        log.notice("markUnavailable alert=\(alertID, privacy: .public)")
    }

    func togglePin(alertID: String) async {
        guard let idx = completed.firstIndex(where: { $0.id == alertID }) else {
            log.notice("togglePin alert=\(alertID, privacy: .public) ignored (no longer in queue)")
            return
        }
        completed[idx].pinned.toggle()
        let pinned = completed[idx].pinned
        await persist()
        await notifyQueueChanged()
        log.notice("togglePin alert=\(alertID, privacy: .public) pinned=\(pinned, privacy: .public)")
    }

    /// Read-only snapshot of pending completed sessions. Used by 02-09 WorkspaceFrontmostObserver (D2-15).
    /// Returns a copy so iteration outside the actor cannot data-race the queue.
    func peekPending() -> [CompletedSession] {
        Array(completed)
    }

    func clearAll() async {
        completed.removeAll(where: { !$0.pinned })
        await persist()
        await notifyQueueChanged()
        log.notice("clearAll remaining=\(self.completed.count, privacy: .public)")
    }

    /// D2-21 — synthetic injection that walks the standard alert path but does NOT persist.
    func injectTest(soundEnabled: Bool) async {
        let session = CompletedSession.testFixture()
        completed.append(session)   // in-memory only — NO `await persist()` (D2-22)
        let snapshot = self.completed
        await notifier?.present(session: session, pendingQueue: snapshot, playSoundOnce: soundEnabled)
        await notifyQueueChanged()
        // Auto-dismiss after 30s (D2-21). Clock injection enables fast-forward in tests.
        let sid = session.sessionID
        Task { [weak self, clock = self.clock] in
            try? await clock.sleepNanoseconds(30 * 1_000_000_000)
            await self?.clearUnpinned(sessionID: sid)
        }
    }

    // MARK: helpers

    private func discardStaleStopIfNeeded(sessionID: String,
                                          stoppedAt: Date,
                                          clearedWaiting: Bool) async -> Bool {
        guard let start = inFlight[sessionID]?.startedAt, stoppedAt < start else { return false }
        log.notice("stale stop discarded session=\(sessionID, privacy: .public) (reordered behind newer prompt)")
        if clearedWaiting {
            await persist()
            await notifyQueueChanged()
        }
        return true
    }

    private func persist() async {
        let snap = SessionsSnapshot(schema: SessionsSnapshot.currentSchema,
                                    inFlight: inFlight,
                                    completed: completed.filter { !Self.isSyntheticTestFixture($0) })
        await persistence.save(snap)
    }

    /// Returns true iff a waiting alert was actually removed, so callers on early-return
    /// paths know whether the widget still needs a refresh.
    @discardableResult
    private func clearUnpinnedWaitingAlert(sessionID: String) -> Bool {
        let before = completed.count
        completed.removeAll(where: { $0.sessionID == sessionID && $0.kind == .waiting && !$0.pinned })
        return completed.count != before
    }

    private func notifyQueueChanged() async {
        let snapshot = self.completed
        let n = self.notifier
        await n?.refreshQueueState(completed: snapshot, count: snapshot.count)
    }

    private func clearUnpinnedByItermSession(_ itermSessionID: String?) {
        guard let itermSessionID else { return }
        completed.removeAll(where: {
            !$0.pinned && $0.itermSessionID == itermSessionID
        })
    }

    private static func isSyntheticTestFixture(_ session: CompletedSession) -> Bool {
        session.sessionID.hasPrefix("test-")
            && session.projectName == "Test"
            && session.durationSec == 31
            && session.itermSessionID == nil
            && session.tty == nil
            && session.cwd == nil
            && session.kind == .success
            && session.exitCode == nil
            && session.startedAt == nil
            && session.lastOutput == nil
    }

    private func parseTS(_ s: String?) -> Date? {
        guard let s = s else { return nil }
        return fractionalISOFormatter.date(from: s) ?? isoFormatter.date(from: s)
    }

    private func discardUnsupportedTerminalEvent(_ event: HookEvent) async {
        log.notice("ignoring unsupported terminal=\(event.term_program ?? "nil", privacy: .public) event=\(event.event, privacy: .public)")
        guard event.event == "stop",
              let sid = event.session_id,
              inFlight.removeValue(forKey: sid) != nil
        else { return }
        await persist()
    }

    static func isSupportedTerminal(_ termProgram: String?) -> Bool {
        guard let termProgram, !termProgram.isEmpty else { return true }
        return termProgram == "iTerm.app"
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
