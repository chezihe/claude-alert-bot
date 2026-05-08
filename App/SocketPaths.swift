// App/SocketPaths.swift — single source of truth for paths (D-10).
// Pitfall #6: AF_UNIX sun_path is 104 bytes on Darwin (incl. NUL); path must fit.
// Pitfall #7: containing directory must exist before bind() — AppDelegate.ensureDirectories().
import Foundation

enum SocketPaths {
    static let appSupportDir: String = {
        "\(NSHomeDirectory())/Library/Application Support/ClaudeAlertBot"
    }()
    static let socketPath: String = "\(appSupportDir)/sock"
    static let logsDir: String = "\(NSHomeDirectory())/Library/Logs/ClaudeAlertBot"
    static let sessionsJSONPath: String = "\(appSupportDir)/sessions.json"

    /// Pitfall #6 — AF_UNIX sun_path is 104 bytes on Darwin (incl. NUL).
    /// Returns true iff the socket path fits.
    static func validateSocketPathLength() -> Bool {
        return socketPath.utf8.count < 104
    }
}
