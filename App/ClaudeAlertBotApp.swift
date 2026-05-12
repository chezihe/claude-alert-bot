// App/ClaudeAlertBotApp.swift — @main SwiftUI App entry (D2-29).
// LSUIElement=true in Info.plist suppresses Dock/menu-bar/Cmd-Tab.
// AppDelegate.applicationWillFinishLaunching sets `.accessory` activation policy
// so policy is in place before SwiftUI realizes any scene.
// The Settings scene is OS-managed: ⌘, in the app menu opens it; SwiftUI hosts SettingsView.
// File deliberately NOT named main.swift — `@main` cannot coexist with a file named
// main.swift in the same module (Swift treats main.swift as an implicit script entry).
import SwiftUI
import AppKit

@main
struct ClaudeAlertBotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
        }
        // Phase 3 03-09 fix — accessory apps (LSUIElement=true) have no Dock icon
        // and no automatic Settings entry. MenuBarExtra is the canonical macOS-native
        // way to give the user a visible handle to inline settings + Quit.
        MenuBarExtra {
            MenuBarMenuContent()
        } label: {
            Image(systemName: "bell.badge")
        }
    }
}

private struct MenuBarMenuContent: View {
    @ObservedObject private var store = SettingsStore.shared

    var body: some View {
        Toggle(SettingsView.soundToggleLabel, isOn: $store.soundEnabled)
        Toggle(SettingsView.quietHoursToggleLabel, isOn: $store.quietHoursEnabled)

        Picker(SettingsView.idleAnimationLabel, selection: store.idleAnimationBinding) {
            ForEach(IdleAnimation.allCases, id: \.self) { animation in
                Text(SettingsView.idleAnimationName(animation)).tag(animation)
            }
        }

        Picker(SettingsView.themeLabel, selection: store.themeModeBinding) {
            ForEach(ThemeMode.allCases, id: \.self) { mode in
                Text(SettingsView.themeModeName(mode)).tag(mode)
            }
        }

        Picker(SettingsView.reduceMotionLabel, selection: store.reduceMotionPreferenceBinding) {
            ForEach(ReduceMotionPreference.allCases, id: \.self) { preference in
                Text(SettingsView.reduceMotionPreferenceName(preference)).tag(preference)
            }
        }

        Toggle(SettingsView.launchAtLoginToggleLabel, isOn: $store.launchAtLoginEnabled)
            .onChange(of: store.launchAtLoginEnabled) { _, enabled in
                LoginItemController.applyFromSettings(enabled: enabled)
            }

        Button(SettingsView.testButtonLabel) {
            Task { await SessionRegistry.shared.injectTest(soundEnabled: store.soundEnabled) }
        }

        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }
}
