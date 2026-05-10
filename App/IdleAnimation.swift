// App/IdleAnimation.swift — WO-012 idle animation selector.
// SPEC §4 lists multiple idle animations; this enum lets WidgetIconView
// switch between them. Settings UI for user selection is a follow-up.
import Foundation

enum IdleAnimation: String, CaseIterable {
    case bounce
    case breathe
    case ring
    case roam

    static let `default`: IdleAnimation = .breathe
}
