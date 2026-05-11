// App/AppleScriptHelper.swift — Phase 2 Wave 2 — D2-14 cheap-query + D2-35 permission trigger.
// RESEARCH Pattern 3 (lines 505-580): compile-once NSAppleScript + serial queue + AppleScript-side
//   `with timeout of 1 second` block + error-code → ScriptResult classification.
// Pitfall 3: NSAppleScript is not main-thread-safe — dedicated serial queue required.
// Pitfall 9: state mirror to SettingsStore via MainActor hop.
// D2-34: 1s hard timeout (AppleScript-side `with timeout` block).
// D2-37: OSLog category `applescript`.
import Foundation
import Carbon.OpenScripting   // errAEEventNotPermitted = -1743, errAEEventTimeout = -1712
import os
import AppKit                 // NSAppleScript

enum ScriptResult: Equatable {
    case success(String)
    case denied
    case timeout
    case otherError(Int)
}

actor AppleScriptHelper {
    static let shared = AppleScriptHelper()

    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "applescript")
    private let queue = DispatchQueue(label: "com.claudealert.bot.applescript", qos: .userInitiated)
    private var compiled: NSAppleScript?
    private(set) var lastKnownPermission: PermissionStatus = .unknown

    /// AppleScript source — read-only cheap-query against iTerm2 frontmost session.
    /// `with timeout of 1 second` is the AppleScript-side hard timeout (D2-34, Pitfall 3).
    /// SECURITY (T-INJECTION-01): static string constant — no `target` interpolation. Match is in Swift.
    private static let scriptSource: String = """
    with timeout of 1 second
        tell application "iTerm2"
            if (count of windows) is 0 then return ""
            return id of current session of current tab of current window
        end tell
    end timeout
    """

    /// jump-by-uuid script (D3-06 + D3-09). 3-second AppleScript-side timeout.
    /// SECURITY (T-INJECTION-01): UUID is whitelist-validated by iTermSessionID.isValid(_:)
    /// BEFORE substitution. Foundation UUID(uuidString:) rejects any character outside
    /// [A-Fa-f0-9-] and any deviation from 8-4-4-4-12 form, which guarantees the
    /// String(format:) substitution cannot inject AppleScript code.
    ///
    /// Options A/B/C/D considered (RESEARCH §Pattern 1):
    ///   A: static source + AppleScript-internal `set target to ...` substituted before compile = SAME AS C.
    ///   B: compile once + executeAppleEvent(:error:) parameter binding = REJECTED (macOS 14 cases sparse, AE descriptor boilerplate).
    ///   C: per-call NSAppleScript(source: substituted) + whitelist-validate before substitution = LOCKED HERE.
    ///   D: 2-step (UUID list → Swift match → select-by-index) = REJECTED (violates "by UUID, never by index").
    ///
    /// Per-call compile cost = 1-5ms (RESEARCH cited measurement) — sub-perceptual.
    /// Returns "<windowID>|<windowTitle>" on success (e.g. "12345|fish — myproject"),
    /// empty string when no session matches. The windowID + title are consumed by
    /// AccessibilityRaiser to cross-Space-raise the window — AppleScript prepares
    /// the target selection but must not activate iTerm2 before AX raises the exact
    /// window, otherwise macOS can surface a different iTerm2 Space/window.
    private static let jumpByUUIDTemplate: String = """
    with timeout of 3 seconds
        tell application "iTerm2"
            set targetUUID to "%@"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if id of s is targetUUID then
                            tell s to select
                            tell t to select
                            tell w to set index to 1
                            return ((id of w) as string) & "|" & (name of w)
                        end if
                    end repeat
                end repeat
            end repeat
            return ""
        end tell
    end timeout
    """

    /// focus-frontmost script (D3-17 #3 + SET-05). 3-second AppleScript-side timeout.
    /// SECURITY: fully static source — no external input. T-INJECTION-01 trivially satisfied.
    /// Returns:
    ///   - empty string if iTerm2 has 0 windows (mapped to .iTermNotRunning by caller)
    ///   - frontmost session UUID otherwise (mapped to .ok)
    /// Activates iTerm2 and brings frontmost session to focus — used by SettingsView SET-05
    /// "iTerm2 연결 테스트" button (D3-15) as a self-test of permission + automation.
    private static let focusFrontmostSource: String = """
    with timeout of 3 seconds
        tell application "iTerm2"
            if (count of windows) is 0 then return ""
            activate
            tell current window to set index to 1
            return id of current session of current tab of current window
        end tell
    end timeout
    """

    private var compiledFocusFrontmost: NSAppleScript?

    private init() {}

    private func ensureCompiled() {
        guard compiled == nil else { return }
        let s = NSAppleScript(source: Self.scriptSource)
        _ = s?.compileAndReturnError(nil)
        compiled = s
    }

    private func ensureCompiledFocusFrontmost() {
        guard compiledFocusFrontmost == nil else { return }
        let s = NSAppleScript(source: Self.focusFrontmostSource)
        _ = s?.compileAndReturnError(nil)
        compiledFocusFrontmost = s
    }

    /// D2-14 — returns true iff frontmost iTerm2 session id matches `target`.
    /// Permission denial / timeout / other failure → returns false (silent skip per D2-36).
    func frontmostMatches(itermSessionID target: String) async -> Bool {
        // Phase 3 03-09 fix — gate cheap-query while permission is unknown so the
        // FIRST AppleScript call against TCC is the deliberate 30s prompt from
        // Settings (D2-35 Path A). Otherwise this 1s cheap-query races the user
        // (Stop hook auto-suppress, NSWorkspace iTerm2-frontmost re-query) and
        // poisons lastKnownPermission to .denied before the prompt completes —
        // observed via -1712 timeout followed by -1743 silent skips on launch.
        // Returning false = "treat as different session, don't suppress" — safe.
        if lastKnownPermission == .unknown {
            return false
        }
        let result = await runQuery()
        switch result {
        case .success(let s):
            await markGranted()
            return !s.isEmpty && s == target
        case .denied:
            await markDenied()
            log.error("permission denied (-1743) — silent skip")
            return false
        case .timeout:
            log.warning("AppleScript timeout (-1712)")
            return false
        case .otherError(let code):
            log.warning("AppleScript error code=\(code, privacy: .public)")
            return false
        }
    }

    /// D2-35 — used by Path A (Settings open) and Path B (first Stop) to surface the TCC dialog.
    /// Uses a 30-second AppleScript-side timeout (vs. cheap-query's 1s in `scriptSource`)
    /// so the user has time to read and respond to the system permission dialog. Without
    /// the longer window the dialog is auto-dismissed by the AppleScript timeout after 1s
    /// before the user can click Allow/Deny. The cheap-query 1s contract (D2-34) is
    /// unaffected — only this prompt-trigger path uses 30s.
    func triggerPermissionPrompt() async {
        let source = """
        with timeout of 30 seconds
            tell application "iTerm2"
                if (count of windows) is 0 then return ""
                return id of current session of current tab of current window
            end tell
        end timeout
        """
        let result: ScriptResult = await withCheckedContinuation { (cont: CheckedContinuation<ScriptResult, Never>) in
            queue.async {
                guard let script = NSAppleScript(source: source) else {
                    cont.resume(returning: .otherError(0)); return
                }
                var compileErr: NSDictionary?
                guard script.compileAndReturnError(&compileErr) else {
                    cont.resume(returning: Self.classify(error: compileErr, result: ""))
                    return
                }
                var runErr: NSDictionary?
                let value = script.executeAndReturnError(&runErr)
                let s = value.stringValue ?? ""
                cont.resume(returning: Self.classify(error: runErr, result: s))
            }
        }
        switch result {
        case .success:
            await markGranted()
            log.notice("triggerPermissionPrompt: granted")
        case .denied:
            await markDenied()
            log.notice("triggerPermissionPrompt: denied")
        case .timeout:
            log.warning("triggerPermissionPrompt: timeout (-1712) after 30s")
        case .otherError(let code):
            log.warning("triggerPermissionPrompt: error code=\(code, privacy: .public)")
        }
    }

    /// D3-06 — jump to the iTerm2 session matching `uuid`.
    /// Returns .ok on match-and-activate; .missing when the loop fell through (no UUID match)
    /// or Accessibility could not raise the exact matched window.
    /// Returns .permissionDenied / .timeout / .otherError per AppleScript classify result.
    /// SECURITY (T-INJECTION-01): rejects any non-UUID input via iTermSessionID.isValid before substitution.
    func runJumpByUUID(_ uuid: String) async -> JumpResult {
        guard iTermSessionID.isValid(uuid) else {
            log.error("runJumpByUUID rejected non-UUID input — possible injection attempt")
            return .otherError(0)
        }
        let source = String(format: Self.jumpByUUIDTemplate, uuid)
        let result: JumpResult = await withCheckedContinuation { (cont: CheckedContinuation<JumpResult, Never>) in
            queue.async {
                guard let script = NSAppleScript(source: source) else {
                    cont.resume(returning: .otherError(0)); return
                }
                var compileErr: NSDictionary?
                guard script.compileAndReturnError(&compileErr) else {
                    let r = Self.classify(error: compileErr, result: "")
                    cont.resume(returning: Self.scriptResultToJump(r, emptyMeans: .missing))
                    return
                }
                var runErr: NSDictionary?
                let value = script.executeAndReturnError(&runErr)
                let s = value.stringValue ?? ""
                let r = Self.classify(error: runErr, result: s)
                // D3-21 — cross-Space raise via Accessibility API. AppleScript can
                // select the target session, but AX kAXRaiseAction is the exact-window
                // activation gate. If AX cannot raise that window, do not report .ok:
                // treating this as success clears the row while macOS may leave a
                // different iTerm2 window visible in the current Space.
                if case .success(let payload) = r, !payload.isEmpty {
                    guard let (winID, title) = Self.parseJumpPayload(payload),
                          let pid = AccessibilityRaiser.itermPID() else {
                        cont.resume(returning: .missing)
                        return
                    }
                    guard AccessibilityRaiser.raise(itermPID: pid, windowID: winID, title: title) else {
                        cont.resume(returning: .missing)
                        return
                    }
                    cont.resume(returning: .ok)
                    return
                }
                cont.resume(returning: Self.scriptResultToJump(r, emptyMeans: .missing))
            }
        }
        // State mirror — same contract as frontmostMatches (D2-35/D2-36 inheritance).
        switch result {
        case .ok:               await markGranted()
        case .permissionDenied: await markDenied()
        default: break
        }
        return result
    }

    /// D3-16 — SET-05 "iTerm2 연결 테스트" button dispatch.
    /// Permission-state branching:
    ///   .denied   → return .permissionDenied immediately (caller deep-links to Privacy & Security).
    ///   .unknown  → trigger TCC prompt via triggerPermissionPrompt() then return .permissionDenied
    ///               (post-prompt success will reflect on next press; this press surfaces the dialog).
    ///   .granted  → run focus-frontmost. Empty result → .iTermNotRunning. UUID returned → .ok.
    func testConnection() async -> JumpResult {
        switch lastKnownPermission {
        case .denied:
            log.notice("testConnection: lastKnownPermission == .denied — returning early")
            return .permissionDenied
        case .unknown:
            log.notice("testConnection: lastKnownPermission == .unknown — triggering TCC prompt")
            await triggerPermissionPrompt()
            // After the prompt, lastKnownPermission may have flipped to .granted or .denied
            // depending on the user's choice. Return .permissionDenied here regardless;
            // the user re-presses to actually exercise focus-frontmost.
            return .permissionDenied
        case .granted:
            return await runFocusFrontmost()
        }
    }

    private func runFocusFrontmost() async -> JumpResult {
        ensureCompiledFocusFrontmost()
        guard let script = compiledFocusFrontmost else { return .otherError(0) }
        let result: JumpResult = await withCheckedContinuation { (cont: CheckedContinuation<JumpResult, Never>) in
            queue.async {
                var errInfo: NSDictionary?
                let value = script.executeAndReturnError(&errInfo)
                let s = value.stringValue ?? ""
                let r = Self.classify(error: errInfo, result: s)
                cont.resume(returning: Self.scriptResultToJump(r, emptyMeans: .iTermNotRunning))
            }
        }
        switch result {
        case .ok:               await markGranted()
        case .permissionDenied: await markDenied()
        default: break
        }
        return result
    }

    /// Maps the actor's internal ScriptResult into the public JumpResult contract.
    /// `emptyMeans` = which JumpResult to return when the AppleScript succeeded with empty string.
    ///   For runJumpByUUID: .missing (loop fell through, UUID not found).
    ///   For runFocusFrontmost (testConnection): .iTermNotRunning (no windows).
    private static func scriptResultToJump(_ result: ScriptResult, emptyMeans: JumpResult) -> JumpResult {
        switch result {
        case .success(let s):
            if s == "ok" { return .ok }
            return s.isEmpty ? emptyMeans : .ok   // non-empty non-"ok" treated as success (focus-frontmost returns UUID string)
        case .denied:    return .permissionDenied
        case .timeout:   return .timeout
        case .otherError(let c): return .otherError(c)
        }
    }

    // MARK: - private

    private func runQuery() async -> ScriptResult {
        ensureCompiled()
        guard let script = compiled else { return .otherError(0) }
        return await withCheckedContinuation { (cont: CheckedContinuation<ScriptResult, Never>) in
            queue.async {
                var errInfo: NSDictionary?
                let result = script.executeAndReturnError(&errInfo)
                let value = result.stringValue ?? ""
                cont.resume(returning: Self.classify(error: errInfo, result: value))
            }
        }
    }

    /// Parse "<windowID>|<title>" payload from jumpByUUIDTemplate. Returns nil if
    /// the windowID portion is non-numeric (defensive — iTerm could theoretically
    /// change its AppleScript `id` representation across versions).
    static func parseJumpPayload(_ payload: String) -> (CGWindowID?, String?)? {
        let parts = payload.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard let first = parts.first else { return nil }
        let winID: CGWindowID? = UInt32(first)
        let title = parts.count > 1 ? String(parts[1]) : nil
        guard winID != nil || (title?.isEmpty == false) else { return nil }
        return (winID, title)
    }

    /// Pure classification — extracted for unit testing without live AppleScript.
    /// Maps -1743 → .denied, -1712 → .timeout, other non-nil → .otherError, nil → .success(result).
    static func classify(error: NSDictionary?, result: String) -> ScriptResult {
        guard let err = error else { return .success(result) }
        let code = err[NSAppleScript.errorNumber] as? Int ?? 0
        switch code {
        case -1743: return .denied
        case -1712: return .timeout
        default: return .otherError(code)
        }
    }

    private func markGranted() async {
        lastKnownPermission = .granted
        await MainActor.run { SettingsStore.shared.applescriptPermission = .granted }
    }

    private func markDenied() async {
        lastKnownPermission = .denied
        await MainActor.run { SettingsStore.shared.applescriptPermission = .denied }
    }

    #if DEBUG
    /// Test seams. Production callers must not use these.
    var rawSource: String { Self.scriptSource }
    static var jumpRawTemplate: String { jumpByUUIDTemplate }
    static var focusFrontmostRawSource: String { focusFrontmostSource }
    var compiledForTesting: NSAppleScript? {
        ensureCompiled()
        return compiled
    }
    func markGrantedForTesting() async { await markGranted() }
    func markDeniedForTesting() async { await markDenied() }
    func markUnknownForTesting() async {
        lastKnownPermission = .unknown
        await MainActor.run { SettingsStore.shared.applescriptPermission = .unknown }
    }
    #endif
}
