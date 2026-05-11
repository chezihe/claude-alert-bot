// App/ITerm2Jumper.swift — Phase 3 D-ADAPTER v1 single conformer.
// CONTEXT D-ADAPTER + D3-06 / D3-07 / D3-10 / D3-13. Phase 6 README CREDIT cites
// TokenEater (AThevon/TokenEater, MIT) as v2 reference for env-stripped-shell
// fallback (D3-08) — v1 borrows no code.
//
// PITFALL #1 regression guard (D3-10): NEVER call `NSApp.activate(...)` in this file.
// iTerm2 activation lives downstream in AppleScriptHelper: AppleScript selects the
// target session, then Accessibility raises the exact iTerm2 window. NSApp.activate
// would activate Claude Alert Bot itself, defeating LSUIElement=true and surfacing
// the app in Cmd-Tab. Verifier 03-09 enforces this:
//     grep -v '^\s*//' App/ITerm2Jumper.swift App/AppleScriptHelper.swift | grep -c 'NSApp\.activate'  → MUST be 0
//
// PATTERNS §ITerm2Jumper: paradigm match with NotificationOrchestrator —
//   thin coordinator translating one signal (CompletedSession) into one typed
//   downstream call (AppleScriptHelper.runJumpByUUID → JumpResult).
import Foundation
import os

@MainActor
final class ITerm2Jumper: TerminalJumper {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "widget")
    private let helper: AppleScriptHelper

    init(helper: AppleScriptHelper = .shared) {
        self.helper = helper
    }

    /// D3-06 — UUID single-strategy jump. No TTY fallback (D3-07; v2 JUMP-FALLBACK-01).
    /// Emits OSLog with the D3-13 [jump*] 4-prefix contract:
    ///   .ok               → [jumped session=<uuid>]
    ///   .missing          → [jump-missed session=<uuid>]
    ///   .permissionDenied → [jump-denied session=<uuid>]
    ///   .iTermNotRunning  → [jump-error session=<uuid>] (treated as recoverable error path)
    ///   .timeout          → [jump-error session=<uuid>] (3s AppleScript timeout)
    ///   .otherError(c)    → [jump-error session=<uuid> code=<c>]
    func jump(to session: CompletedSession) async -> JumpResult {
        // Phase 3 D3-02: itermSessionID is already normalized (UUID-only) by 03-03 ingestion.
        // Defensive: also validate here in case of orphan-stop fallback or test-fixture nil.
        guard let raw = session.itermSessionID,
              let uuid = iTermSessionID.uuid(fromRaw: raw),   // idempotent — handles colon and colonless
              iTermSessionID.isValid(uuid) else {
            log.notice("[jump-missed session=\(session.sessionID, privacy: .public)] (no iterm UUID)")
            return .missing
        }

        let result = await helper.runJumpByUUID(uuid)
        switch result {
        case .ok:
            log.notice("[jumped session=\(session.sessionID, privacy: .public)]")
        case .missing:
            log.notice("[jump-missed session=\(session.sessionID, privacy: .public)]")
        case .permissionDenied:
            log.warning("[jump-denied session=\(session.sessionID, privacy: .public)]")
        case .iTermNotRunning:
            log.warning("[jump-error session=\(session.sessionID, privacy: .public) reason=iterm-not-running]")
        case .timeout:
            log.warning("[jump-error session=\(session.sessionID, privacy: .public) reason=timeout]")
        case .otherError(let code):
            log.warning("[jump-error session=\(session.sessionID, privacy: .public) code=\(code, privacy: .public)]")
        }
        return result
    }
}
