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

    // Phase 2 — retained components (Wave 6 wiring per Pitfall #11)
    private var notificationOrchestrator: NotificationOrchestrator?
    private var widgetController: FloatingWidgetWindowController?
    private var popoverController: WidgetPopoverController?
    private var wakeObserver: WakeObserver?
    private var frontmostObserver: WorkspaceFrontmostObserver?
    private var gcTimer: SessionGCTimer?

    // D2-29: previously set in main.swift; relocated here so it lands BEFORE SwiftUI
    // realizes any scene. willFinishLaunching is the canonical Apple-blessed slot for
    // this when using SwiftUI App lifecycle. Belt-and-suspenders alongside LSUIElement=true.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // === Phase 1 steps (preserved verbatim) ===
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

        // === Phase 2 wiring (Wave 6 — Pitfall #11 ordering) ===
        // listener.start() (Phase 1 step 4) is DEFERRED into this Task so it runs
        // strictly AFTER SessionRegistry.restore() completes — otherwise in-flight
        // events arriving in the boot window can be dropped.
        Task { @MainActor in
            // 6. Restore session state from disk BEFORE listener accepts events.
            await SessionRegistry.shared.restore()

            // 7. Construct widget + popover + notification orchestrator.
            let widget = FloatingWidgetWindowController()
            let popover = WidgetPopoverController(widgetController: widget, jumper: ITerm2Jumper())
            widget.hoverDelegate = popover
            let orchestrator = NotificationOrchestrator(widget: widget)
            self.widgetController = widget
            self.popoverController = popover
            self.notificationOrchestrator = orchestrator

            // 8. Bind orchestrator to registry — registry can now broadcast UI updates.
            await SessionRegistry.shared.bind(notifier: orchestrator)

            // 9. Restore-broadcast — registry already replayed any restored queue,
            //    but the orchestrator was nil at that time. Re-emit current state.
            let pending = await SessionRegistry.shared.peekPending()
            await orchestrator.refreshQueueState(completed: pending, count: pending.count)

            // 10. Lifecycle observers + GC timer (SESS-04 Pattern 6 triple-trigger).
            self.wakeObserver = WakeObserver { Task { await SessionRegistry.shared.runGC() } }
            self.frontmostObserver = WorkspaceFrontmostObserver()
            let timer = SessionGCTimer { Task { await SessionRegistry.shared.runGC() } }
            timer.start()
            self.gcTimer = timer

            // 11. AppleScriptHelper eager compile — keeps first cheap-query latency low.
            //     No permission trigger here: D2-35 Path A lives in SettingsView.onAppear,
            //     Path B lives in HookListener.handle on the first Stop with .unknown perm.
            _ = AppleScriptHelper.shared

            self.log.notice("Phase 2 components wired (orchestrator, widget, popover, observers, GC timer)")

            // === Phase 1 step 4 (DEFERRED to here per Pitfall #11) ===
            // 4. Start listener AFTER all Phase 2 wiring completes.
            do {
                let l = HookListener(socketPath: SocketPaths.socketPath)
                try l.start()
                self.listener = l
                self.log.notice("listener bound (Phase 2 wiring complete)")
            } catch {
                self.log.error("listener.start failed: \(String(describing: error), privacy: .public)")
                NSApp.terminate(nil)
            }
        }

        // === Phase 1 step 5 (preserved — outside Task; signal handlers don't depend on Phase 2 wiring) ===
        installSignalHandler(SIGTERM)
        installSignalHandler(SIGINT)
        // NOTE: D2-29 — no NSMenu / settingsWindow / NSApp.activate. The SwiftUI
        // `Settings { … }` scene in ClaudeAlertBotApp.swift handles ⌘, automatically.
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
