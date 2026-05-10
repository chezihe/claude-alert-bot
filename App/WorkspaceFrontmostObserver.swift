// App/WorkspaceFrontmostObserver.swift — Phase 2 D2-15.
// On NSWorkspace.didActivateApplicationNotification: re-evaluate pending alerts.
// If iTerm2 is now frontmost AND its current session matches a pending alert's iterm_session_id → clear unpinned.
// Permission-aware: if AppleScriptHelper permission is denied, this observer's body silently skips
// (the cheap-query returns false; auto-clear is not invoked).
// CRITICAL: retain the token — otherwise it's deallocated and signals are silently ignored.
import AppKit
import os

@MainActor
final class WorkspaceFrontmostObserver {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "lifecycle")
    private var token: NSObjectProtocol?

    init() {
        token = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            guard let self else { return }
            // Cheap heuristic — only run the AppleScript path if the activated app is iTerm2.
            // (Other apps gain frontmost frequently; we don't want to spam AppleScript on every Cmd-Tab.)
            let app = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            guard app?.bundleIdentifier == "com.googlecode.iterm2" else { return }
            self.log.notice("iTerm2 became frontmost — D2-15 re-query")
            Task { await self.evaluatePendingAlerts() }
        }
        log.notice("WorkspaceFrontmostObserver installed")
    }

    deinit {
        if let t = token {
            NSWorkspace.shared.notificationCenter.removeObserver(t)
        }
    }

    private func evaluatePendingAlerts() async {
        let pending = await SessionRegistry.shared.peekPending()
        for session in pending {
            guard !session.pinned else { continue }
            guard let target = session.itermSessionID else { continue }
            if await AppleScriptHelper.shared.frontmostMatches(itermSessionID: target) {
                log.notice("D2-15 auto-clear session=\(session.sessionID, privacy: .public)")
                await SessionRegistry.shared.clearUnpinned(sessionID: session.sessionID)
            }
        }
    }
}
