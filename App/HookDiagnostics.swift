// App/HookDiagnostics.swift — menu bar Diagnostics: where the hook → reporter → socket → App
// chain is broken when alerts stop arriving. The reporter always exits 0 silently, so this
// is the only place a failure becomes visible.
import Foundation

struct HookDiagnosticsReport: Equatable {
    var claudeHooksInstalled: Bool
    /// nil when Codex is not installed.
    var codexHooksInstalled: Bool?
    var reporterInstalled: Bool
    var socketListening: Bool
    /// Not part of alert delivery, but row clicks raise the wrong iTerm2 window without it.
    var accessibilityGranted: Bool
    var lastEventAt: Date?

    var allOK: Bool {
        claudeHooksInstalled && codexHooksInstalled != false && reporterInstalled && socketListening
            && accessibilityGranted
    }
}

struct HookDiagnosticsRow: Equatable {
    let ok: Bool
    let text: String

    var systemImage: String { ok ? "checkmark.circle" : "xmark.circle" }
}

enum HookDiagnostics {
    static func check(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
                      socketPath: String = SocketPaths.socketPath,
                      accessibilityGranted: Bool = AccessibilityRaiser.isTrusted(),
                      lastEventAt: Date?,
                      fileManager: FileManager = .default) -> HookDiagnosticsReport {
        HookDiagnosticsReport(
            claudeHooksInstalled: HookInstaller.claudeHooksInstalled(homeDirectory: homeDirectory,
                                                                     fileManager: fileManager),
            codexHooksInstalled: HookInstaller.codexHooksInstalled(homeDirectory: homeDirectory,
                                                                   fileManager: fileManager),
            reporterInstalled: fileManager.isExecutableFile(
                atPath: HookInstaller.reporterURL(homeDirectory: homeDirectory).path
            ),
            socketListening: HookListener.socketIdentity(at: socketPath) != nil,
            accessibilityGranted: accessibilityGranted,
            lastEventAt: lastEventAt
        )
    }

    static func rows(_ report: HookDiagnosticsReport) -> [HookDiagnosticsRow] {
        var rows = [
            HookDiagnosticsRow(ok: report.claudeHooksInstalled,
                               text: report.claudeHooksInstalled ? "Claude hooks registered" : "Claude hooks missing"),
        ]
        if let codex = report.codexHooksInstalled {
            rows.append(HookDiagnosticsRow(ok: codex, text: codex ? "Codex hooks registered" : "Codex hooks missing"))
        }
        rows += [
            HookDiagnosticsRow(ok: report.reporterInstalled,
                               text: report.reporterInstalled ? "Reporter installed" : "Reporter missing"),
            HookDiagnosticsRow(ok: report.socketListening,
                               text: report.socketListening ? "App listening for hooks" : "App not listening for hooks"),
            HookDiagnosticsRow(ok: report.accessibilityGranted,
                               text: report.accessibilityGranted ? "Accessibility granted" : "Accessibility not granted"),
        ]
        return rows
    }

    static func lastEventLabel(_ date: Date?, now: Date) -> String {
        guard let date else { return "Last hook event: none yet" }
        let minutes = Int(now.timeIntervalSince(date) / 60)
        if minutes < 1 { return "Last hook event: just now" }
        if minutes < 60 { return "Last hook event: \(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return "Last hook event: \(hours)h ago" }
        return "Last hook event: \(hours / 24)d ago"
    }

    static var hookLogURL: URL {
        URL(fileURLWithPath: SocketPaths.logsDir).appendingPathComponent("hook.log")
    }
}
