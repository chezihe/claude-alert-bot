// App/IdleAnimation.swift — idle animation selector.
// SPEC §4 lists multiple idle animations; this enum is persisted by SettingsStore
// and drives WidgetIconView's selected idle motion.
import Foundation

enum IdleAnimation: String, CaseIterable {
    case bounce
    case heart
    case ring
    case roam
    case rage

    static let `default`: IdleAnimation = .bounce
}
