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

    private init() {}

    private func ensureCompiled() {
        guard compiled == nil else { return }
        let s = NSAppleScript(source: Self.scriptSource)
        _ = s?.compileAndReturnError(nil)
        compiled = s
    }

    /// D2-14 — returns true iff frontmost iTerm2 session id matches `target`.
    /// Permission denial / timeout / other failure → returns false (silent skip per D2-36).
    func frontmostMatches(itermSessionID target: String) async -> Bool {
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
    /// Same script, target string we know won't match (so the bool result is irrelevant).
    func triggerPermissionPrompt() async {
        _ = await frontmostMatches(itermSessionID: "<no-match>")
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
    var compiledForTesting: NSAppleScript? {
        ensureCompiled()
        return compiled
    }
    func markGrantedForTesting() async { await markGranted() }
    func markDeniedForTesting() async { await markDenied() }
    #endif
}
