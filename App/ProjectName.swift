// App/ProjectName.swift — Phase 2 D2-06 project-name derivation.
// Rule: prefer cwd basename. Fall back to claude_project_dir basename. Sentinel "unknown" if both nil.
// PATTERNS.md §ProjectName: small enum-of-static-funcs Foundation-only, mirrors SocketPaths style.
import Foundation

enum ProjectName {
    /// D2-06: "프로젝트명만 (cwd basename 또는 CLAUDE_PROJECT_DIR basename)"
    /// Rule: cwd wins when present (the *current* working directory is closer to the user's mental model
    /// than the project root). claude_project_dir is the fallback for shells that didn't propagate cwd.
    static func derive(cwd: String?, claudeProjectDir: String?) -> String {
        if let s = cwd, !s.isEmpty {
            return basename(of: s)
        }
        if let s = claudeProjectDir, !s.isEmpty {
            return basename(of: s)
        }
        return "unknown"
    }

    private static func basename(of path: String) -> String {
        var p = path
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        if p == "/" { return "/" }
        let comps = p.split(separator: "/", omittingEmptySubsequences: true)
        return comps.last.map(String.init) ?? "/"
    }
}
