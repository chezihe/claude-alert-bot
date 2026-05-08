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
        didSet { UserDefaults.standard.set(applescriptPermission.rawValue, forKey: "applescript_permission") }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "applescript_permission") ?? PermissionStatus.unknown.rawValue
        self.applescriptPermission = PermissionStatus(rawValue: raw) ?? .unknown
    }
}
