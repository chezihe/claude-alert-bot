// App/SettingsStore.swift — Phase 2 SET-01..03, THR-01, AUD-02, WIDG-06.
// RESEARCH Pattern 4 (lines 587-612). Single-direction: View → Store → (call args) → Registry/Orch.
// Pitfall #7: WidgetCorner uses String rawValue for @AppStorage compatibility.
// D2-29 — SwiftUI Settings { … } scene + @AppStorage. Zero external deps.
// D2-30 — UserDefaults access lives only inside this Store.
import SwiftUI
import Combine

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private let defaults: UserDefaults

    @AppStorage("threshold_seconds") var thresholdSeconds: Int = 30   // THR-01 default per ROADMAP
    @AppStorage("sound_enabled")     var soundEnabled: Bool = true    // AUD-02
    @AppStorage("widget_corner")     private var cornerRaw: String = WidgetCorner.topRight.rawValue  // D2-26
    @AppStorage("widget_offset_x")   var offsetX: Int = 16            // D2-27
    @AppStorage("widget_offset_y")   var offsetY: Int = 16            // D2-27

    /// Computed enum binding for SwiftUI Picker.
    var widgetCorner: WidgetCorner {
        get { WidgetCorner(rawValue: cornerRaw) ?? .topRight }
        set { cornerRaw = newValue.rawValue; objectWillChange.send() }
    }

    /// SwiftUI binding helper for the Picker (Pitfall #7 ergonomics).
    var cornerBinding: Binding<WidgetCorner> {
        Binding(get: { self.widgetCorner }, set: { self.widgetCorner = $0 })
    }

    /// D2-35/D2-36 — written by AppleScriptHelper after first cheap-query, then persisted.
    /// Not @AppStorage because (a) the helper is `actor`-isolated and (b) we want @Published broadcast.
    @Published var applescriptPermission: PermissionStatus {
        didSet { defaults.set(applescriptPermission.rawValue, forKey: "applescript_permission") }
    }

    @Published var mutedProjects: [String: Date] {
        didSet { persistMutedProjects() }
    }

    /// D3-18 — written by SettingsView SET-05 button after testConnection() returns .ok.
    /// Sentinel: stored as TimeInterval; 0 (or absent) maps to nil.
    /// @Published so SettingsView re-renders when the value updates after a successful test.
    /// Mirrors the applescriptPermission @Published+UserDefaults bridge above —
    /// Date? has no native @AppStorage support, so this is the locked pattern.
    @Published var lastConnectionTestAt: Date? {
        didSet {
            if let d = lastConnectionTestAt {
                defaults.set(d.timeIntervalSince1970, forKey: "last_connection_test_at")
            } else {
                defaults.removeObject(forKey: "last_connection_test_at")
            }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self._thresholdSeconds = AppStorage(wrappedValue: 30, "threshold_seconds", store: defaults)
        self._soundEnabled = AppStorage(wrappedValue: true, "sound_enabled", store: defaults)
        self._cornerRaw = AppStorage(wrappedValue: WidgetCorner.topRight.rawValue, "widget_corner", store: defaults)
        self._offsetX = AppStorage(wrappedValue: 16, "widget_offset_x", store: defaults)
        self._offsetY = AppStorage(wrappedValue: 16, "widget_offset_y", store: defaults)
        let raw = defaults.string(forKey: "applescript_permission") ?? PermissionStatus.unknown.rawValue
        self.applescriptPermission = PermissionStatus(rawValue: raw) ?? .unknown
        if let data = defaults.data(forKey: "muted_projects"),
           let decoded = try? JSONDecoder().decode([String: Date].self, from: data) {
            self.mutedProjects = decoded
        } else {
            self.mutedProjects = [:]
        }
        let ti = defaults.double(forKey: "last_connection_test_at")
        self.lastConnectionTestAt = ti > 0 ? Date(timeIntervalSince1970: ti) : nil
    }

    func mute(project: String, duration: TimeInterval = 3600, now: Date) {
        mutedProjects[project] = now.addingTimeInterval(duration)
    }

    func unmute(project: String) {
        mutedProjects.removeValue(forKey: project)
    }

    func isMuted(project: String, now: Date) -> Bool {
        (mutedProjects[project] ?? .distantPast) > now
    }

    private func persistMutedProjects() {
        guard let data = try? JSONEncoder().encode(mutedProjects) else { return }
        defaults.set(data, forKey: "muted_projects")
    }
}
