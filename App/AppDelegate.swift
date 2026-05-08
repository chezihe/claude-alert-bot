// App/AppDelegate.swift — Phase 1 application lifecycle.
// Steps in applicationDidFinishLaunching match RESEARCH "System Architecture Diagram → App lifecycle":
//   1. validate sun_path length (Pitfall #6)
//   2. ensure ~/Library/Application Support/ClaudeAlertBot/ + ~/Library/Logs/ClaudeAlertBot/ exist (Pitfall #7)
//   3. reclaim stale socket (Pattern 6 — probe-connect; only remove if no live listener)
//   4. start NWListener (D-09: bind exclusivity = single-instance lock; .failed → terminate)
//   5. install SIGTERM/SIGINT handlers for clean shutdown (must retain DispatchSource refs)
import AppKit
import Foundation
import Network
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "lifecycle")
    private var listener: HookListener?
    private var signalSources: [DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Validate socket path length (Pitfall #6)
        guard SocketPaths.validateSocketPathLength() else {
            log.error("socket path > 103 bytes — refusing to bind")
            NSApp.terminate(nil)
            return
        }

        // 2. Ensure directories exist with mode 0700 (Pitfall #7 + T-IPC-01 mitigation)
        ensureDirectories()

        // 3. Stale-socket reclaim (Pattern 6)
        reclaimSocketIfStale(at: SocketPaths.socketPath)

        // 4. Start listener — failure (D-09) → terminate is wired inside HookListener.stateUpdateHandler
        do {
            let l = HookListener(socketPath: SocketPaths.socketPath)
            try l.start()
            self.listener = l
        } catch {
            log.error("failed to construct listener: \(String(describing: error), privacy: .public)")
            NSApp.terminate(nil)
            return
        }

        // 5. Signal handlers — clean shutdown removes socket file
        installSignalHandler(SIGTERM)
        installSignalHandler(SIGINT)
    }

    private func ensureDirectories() {
        let fm = FileManager.default
        for dir in [SocketPaths.appSupportDir, SocketPaths.logsDir] {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
            // Re-apply 0700 in case the directory pre-existed with different perms.
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir)
        }
    }

    private func reclaimSocketIfStale(at path: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }

        let probe = NWConnection(to: .unix(path: path), using: NWParameters.tcp)
        let group = DispatchGroup()
        group.enter()
        var alive = false
        // NWConnection states are not single-shot — `.failed`/`.cancelled`/`.waiting`
        // can fire repeatedly (e.g. after our own probe.cancel()). Multiple group.leave()
        // calls crash libdispatch ("Unbalanced call to dispatch_group_leave()"), which
        // surfaced as test-runner crashes when the TEST_HOST app boots.
        var leftOnce = false
        probe.stateUpdateHandler = { state in
            guard !leftOnce else { return }
            switch state {
            case .ready:
                alive = true
                leftOnce = true
                group.leave()
            case .failed, .cancelled, .waiting:
                leftOnce = true
                group.leave()
            default: break
            }
        }
        probe.start(queue: DispatchQueue.global())
        _ = group.wait(timeout: .now() + .milliseconds(200))
        probe.cancel()

        if !alive {
            try? fm.removeItem(atPath: path)
            log.info("removed stale socket at \(path, privacy: .public)")
        }
        // If alive, leave the file — listener.start() will report .failed and we exit cleanly.
    }

    private func installSignalHandler(_ sig: Int32) {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler { [weak self] in
            self?.log.info("received signal \(sig) — shutting down")
            self?.listener?.cancel()
            NSApp.terminate(nil)
        }
        src.resume()
        // CRITICAL: retain the source — otherwise it's deallocated and signals are silently ignored.
        signalSources.append(src)
    }
}
