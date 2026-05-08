// App/ClaudeAlertBotApp.swift — @main SwiftUI App entry (D2-29).
// LSUIElement=true in Info.plist suppresses Dock/menu-bar/Cmd-Tab.
// AppDelegate.applicationWillFinishLaunching sets `.accessory` activation policy
// so policy is in place before SwiftUI realizes any scene.
// The Settings scene is OS-managed: ⌘, in the app menu opens it; SwiftUI hosts SettingsView.
// File deliberately NOT named main.swift — `@main` cannot coexist with a file named
// main.swift in the same module (Swift treats main.swift as an implicit script entry).
import SwiftUI

@main
struct ClaudeAlertBotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
