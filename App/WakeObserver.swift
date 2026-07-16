// App/WakeObserver.swift — Phase 2 SESS-04 wake-trigger.
// RESEARCH Pattern 6 (lines 660-670) — `didWakeNotification` covers DispatchSourceTimer freezing during sleep.
// PATTERNS.md §"DispatchSource / observer retention" — token MUST be retained.
// CRITICAL: retain the token — otherwise it's deallocated and signals are silently ignored.
// (Verbatim Phase 1 institutional comment — copy-pasted across all observer files.)
import AppKit
import os

@MainActor
final class WakeObserver {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "lifecycle")
    private var token: NSObjectProtocol?
    private let onWake: () -> Void

    init(onWake: @escaping () -> Void) {
        self.onWake = onWake
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.log.notice("wake — kicking GC")
                self?.onWake()
            }
        }
        log.notice("WakeObserver installed")
    }

    deinit {
        if let t = token {
            NSWorkspace.shared.notificationCenter.removeObserver(t)
        }
    }
}
