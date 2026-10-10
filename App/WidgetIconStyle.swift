// App/WidgetIconStyle.swift — widget icon selector.
// Persisted by SettingsStore; drives WidgetIconView's glyph asset.
// New case = add rawValue + glyph rendering in WidgetIconView + matching assets.
import Foundation

enum WidgetIconStyle: String, CaseIterable {
    case claude
    case zelda

    static let `default`: WidgetIconStyle = .claude

    func alertSoundCue(effect: WidgetAlertEffect) -> SoundCue {
        switch self {
        case .claude: return .defaultAlert
        case .zelda:
            switch effect {
            case .heal: return .zeldaHeal
            case .hit: return .zeldaHit
            }
        }
    }
}

enum WidgetAlertEffect: String, CaseIterable {
    case heal
    case hit

    static let `default`: WidgetAlertEffect = .heal
}

enum WidgetSide {
    case left
    case right
}

extension WidgetCorner {
    var widgetSide: WidgetSide {
        switch self {
        case .topLeft, .bottomLeft:
            return .left
        case .topRight, .bottomRight:
            return .right
        }
    }
}

enum ZeldaFrame {
    static let idleFrames = ["zelda_frame_00", "zelda_frame_01"]

    static func alertFrames(effect: WidgetAlertEffect) -> [String] {
        switch effect {
        case .heal:
            return ["zelda_frame_02", "zelda_frame_03", "zelda_frame_04_heal"]
        case .hit:
            return ["zelda_frame_02", "zelda_frame_03", "zelda_frame_04_hit"]
        }
    }

    static func characterSubdirectory(side: WidgetSide) -> String {
        switch side {
        case .left:
            return "adventure-widget/character/left"
        case .right:
            return "adventure-widget/character/right"
        }
    }

    static func alertFrameDurationMultiplier(frameName: String) -> Double {
        switch frameName {
        case "zelda_frame_04_heal", "zelda_frame_04_hit":
            return 1.5
        default:
            return 1.0
        }
    }
}
