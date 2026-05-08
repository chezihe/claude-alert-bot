// App/SessionGCTimer.swift — Phase 2 SESS-04 30-min GC tick.
// RESEARCH Pattern 6 — DispatchSourceTimer; sleep-aware via WakeObserver complement.
// PATTERNS.md §"DispatchSource / observer retention" — source MUST be retained.
// CRITICAL: retain the source — otherwise it's deallocated and signals are silently ignored.
import Foundation
import os

@MainActor
final class SessionGCTimer {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "lifecycle")
    private var source: DispatchSourceTimer?
    private let interval: TimeInterval
    private let onTick: () -> Void

    /// Default 30-min interval per RESEARCH Pattern 6. Tests pass shorter intervals.
    init(interval: TimeInterval = 30 * 60, onTick: @escaping () -> Void) {
        self.interval = interval
        self.onTick = onTick
    }

    func start() {
        let s = DispatchSource.makeTimerSource(queue: .main)
        s.schedule(deadline: .now() + interval, repeating: interval, leeway: .seconds(1))
        s.setEventHandler { [weak self] in
            self?.log.notice("GC tick")
            self?.onTick()
        }
        s.resume()
        self.source = s
        log.notice("SessionGCTimer started interval=\(self.interval)")
    }

    func cancel() {
        source?.cancel()
        source = nil
        log.notice("SessionGCTimer cancelled")
    }

    deinit {
        // Cancel synchronously — DispatchSource cancellation is thread-safe.
        // Note: deinit on @MainActor class runs on main; source.cancel() is fine here.
        source?.cancel()
    }
}
