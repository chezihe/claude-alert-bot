// App/PermissionDeepLink.swift — D2-36 sequential System Settings deep-link.
// macOS Sequoia (15+) changed the Privacy_Automation URL scheme. Try Sequoia → Ventura → root.
// Source: 02-RESEARCH.md Pattern 12; CONTEXT.md D2-36.
import AppKit

enum PermissionDeepLink {
    /// Locked URL sequence per D2-36. Order matters — first match wins.
    /// DO NOT reorder without updating CONTEXT D2-36 + RESEARCH Pattern 12 + this file's tests.
    static let urls: [String] = [
        // macOS 15 Sequoia — extension-model URL
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Automation",
        // macOS 14 Sonoma + 13 Ventura — legacy URL
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation",
        // Final fallback — root Privacy & Security pane (no anchor)
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension",
    ]

    /// Opens System Settings → Privacy & Security → Automation. Tries each URL in order;
    /// first one that NSWorkspace can open returns. Silent no-op if all three fail
    /// (extremely unlikely — root URL is generic and always handled by Settings.app).
    static func openAutomationPreferences() {
        for s in urls {
            guard let u = URL(string: s) else { continue }
            if NSWorkspace.shared.open(u) { return }
        }
    }
}
