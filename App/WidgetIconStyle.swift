// App/WidgetIconStyle.swift — widget icon selector.
// Persisted by SettingsStore; drives WidgetIconView's glyph asset.
// New case = add rawValue + assetName mapping + matching imageset.
import Foundation

enum WidgetIconStyle: String, CaseIterable {
    case claude

    static let `default`: WidgetIconStyle = .claude

    var assetName: String {
        switch self {
        case .claude: return "ClaudeCodeIcon"
        }
    }
}
