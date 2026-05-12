// App/SettingsWindowPresenter.swift — opens SwiftUI Settings and raises its window.
import AppKit

@MainActor
enum SettingsWindowPresenter {
    static func open() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        raiseSettingsWindowSoon()
    }

    private static func raiseSettingsWindowSoon() {
        DispatchQueue.main.async {
            bringSettingsWindowToFront()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) {
            bringSettingsWindowToFront()
        }
    }

    private static func bringSettingsWindowToFront() {
        for window in NSApp.windows where window.isVisible && !(window is NSPanel) {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }
}
