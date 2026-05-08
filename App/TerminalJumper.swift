// App/TerminalJumper.swift — Phase 3 D-ADAPTER seam.
// CONTEXT.md D-ADAPTER + D3-06..09. v1 single impl = ITerm2Jumper (plan 03-05).
// v2 multi-terminal adds new conformers (MTERM-01..04 in REQUIREMENTS.md v2).
//
// JumpResult is the protocol's contract surface — covers BOTH the row-click path
// (D3-06) and the SET-05 testConnection path (D3-16/D3-19). One enum, one wave
// dependency edge — keeps 03-04 / 03-05 / 03-08 importing the same type.
//
// `permissionDenied` ↔ AppleScript -1743
// `timeout`          ↔ AppleScript -1712 (or future Swift-side timeout)
// `iTermNotRunning`  ↔ SET-05 focus-frontmost script empty response (D3-19 label)
// `missing`          ↔ jump-by-uuid loop fell through (D3-11 도리도리 UX)
// `otherError(Int)`  ↔ NSAppleScript errorNumber that is none of the above
import Foundation

enum JumpResult: Equatable {
    case ok
    case missing
    case permissionDenied
    case iTermNotRunning
    case timeout
    case otherError(Int)
}

@MainActor
protocol TerminalJumper: AnyObject {
    /// D3-06: jump to the iTerm2 session associated with this completed alert.
    /// Result is mapped from AppleScriptHelper's internal ScriptResult by the
    /// concrete adapter (ITerm2Jumper, plan 03-05).
    func jump(to session: CompletedSession) async -> JumpResult
}
