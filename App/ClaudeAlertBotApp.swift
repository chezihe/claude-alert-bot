// App/ClaudeAlertBotApp.swift — @main SwiftUI App entry (D2-29).
// LSUIElement=true in Info.plist suppresses Dock/menu-bar/Cmd-Tab.
// AppDelegate.applicationWillFinishLaunching sets `.accessory` activation policy
// so policy is in place before SwiftUI realizes any scene.
// Settings are now exposed directly from the menu bar extras menu (no separate Settings scene).
// File deliberately NOT named main.swift — `@main` cannot coexist with a file named
// main.swift in the same module (Swift treats main.swift as an implicit script entry).
import SwiftUI
import AppKit

@main
struct ClaudeAlertBotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Phase 3 03-09 fix — accessory apps (LSUIElement=true) have no Dock icon
        // and no automatic Settings entry. MenuBarExtra is the canonical macOS-native
        // way to give the user inline settings + Quit.
        MenuBarExtra {
            MenuBarMenuContent()
        } label: {
            Image(systemName: "bell.badge")
        }
    }
}

private struct MenuBarMenuContent: View {
    @ObservedObject private var store = SettingsStore.shared
    @State private var connectionTestResult: JumpResult? = nil
    @State private var connectionTestResultAt: Date = Date()
    @State private var hideResultTask: Task<Void, Never>? = nil

    var body: some View {
        let activeMutes = MutedProjectsRules.activeMutes(store.mutedProjects, now: Date())
        let now = Date()

        Menu("Notification") {
            Toggle(SettingsView.soundToggleLabel, isOn: $store.soundEnabled)
            Toggle(SettingsView.quietHoursToggleLabel, isOn: $store.quietHoursEnabled)
            Menu(SettingsView.thresholdHeading) {
                Stepper("\(store.thresholdSeconds)초", value: $store.thresholdSeconds, in: 5...600, step: 5)
                Text(SettingsView.thresholdCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Menu("Style") {
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
        }

        Menu(SettingsView.widgetPositionHeading) {
            Picker(SettingsView.cornerLabel, selection: store.cornerBinding) {
                ForEach(WidgetCorner.allCases) { c in
                    Text(SettingsView.widgetCornerLabel(c)).tag(c)
                }
            }
            Stepper("\(SettingsView.offsetXLabel): \(store.offsetX) pt", value: $store.offsetX, in: 0...64)
            Stepper("\(SettingsView.offsetYLabel): \(store.offsetY) pt", value: $store.offsetY, in: 0...64)
        }

        Toggle(SettingsView.launchAtLoginToggleLabel, isOn: $store.launchAtLoginEnabled)
            .onChange(of: store.launchAtLoginEnabled) { _, enabled in
                LoginItemController.applyFromSettings(enabled: enabled)
            }

        Menu(SettingsView.mutedProjectsHeading) {
            if activeMutes.isEmpty {
                Text("No muted projects")
            } else {
                ForEach(activeMutes, id: \.project) { entry in
                    Menu(entry.project) {
                        Text(MutedProjectsRules.remainingMinutesLabel(expiresAt: entry.expiresAt, now: now))
                        Button(SettingsView.unmuteButtonLabel) {
                            store.unmute(project: entry.project)
                        }
                    }
                }
            }
        }

        Menu(SettingsView.connectionTestHeading) {
            Button(SettingsView.testButtonLabel) {
                Task { await SessionRegistry.shared.injectTest(soundEnabled: store.soundEnabled) }
            }
            Button(SettingsView.connectionTestLabel) {
                Task { await runConnectionTest() }
            }

            if let result = connectionTestResult {
                switch result {
                case .ok:
                    Text(String(format: SettingsView.connectionTestSuccessFmt, hhmm(connectionTestResultAt)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .iTermNotRunning:
                    Text(SettingsView.iTermNotRunningLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .permissionDenied:
                    Text(SettingsView.connectionDeniedLabel)
                        .font(.caption)
                        .foregroundStyle(.red)
                case .missing, .timeout, .otherError:
                    Text(SettingsView.iTermNotRunningLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if let last = store.lastConnectionTestAt {
                Text(String(format: SettingsView.connectionTestSuccessFmt, hhmm(last)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Divider()
        Button("Quit") { NSApp.terminate(nil) }
    }

    private func runConnectionTest() async {
        let result = await AppleScriptHelper.shared.testConnection()
        await MainActor.run {
            connectionTestResult = result
            connectionTestResultAt = Date()

            if case .ok = result {
                store.lastConnectionTestAt = Date()
            }

            if case .permissionDenied = result {
                PermissionDeepLink.openAutomationPreferences()
            }

            hideResultTask?.cancel()
            hideResultTask = Task {
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run { connectionTestResult = nil }
            }
        }
    }

    private func hhmm(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
