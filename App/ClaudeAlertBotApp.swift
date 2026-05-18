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
    private var menuIdleAnimations: [IdleAnimation] {
        IdleAnimation.allCases.filter { $0 != .rage }
    }

    var body: some View {
        let activeMutes = MutedProjectsRules.activeMutes(store.mutedProjects, now: Date())
        let now = Date()

        Menu("Notification") {
            Toggle(Self.menuSoundToggleLabel, isOn: $store.soundEnabled)
            Toggle(Self.menuQuietHoursToggleLabel, isOn: $store.quietHoursEnabled)
            Menu(Self.menuThresholdHeading) {
                ForEach(Self.thresholdPresets) { preset in
                    Button {
                        store.thresholdSeconds = preset.seconds
                    } label: {
                        HStack {
                            Text(preset.label)
                            if store.thresholdSeconds == preset.seconds {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Text(Self.menuThresholdCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Menu(Self.menuAlertDetailsHeading) {
                Button {
                    store.detailShowLastOutput = false
                } label: {
                    HStack {
                        Text(Self.menuAlertDetailsNoneLabel)
                        if !store.detailShowLastOutput {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                Button {
                    store.detailShowLastOutput = true
                } label: {
                    HStack {
                        Text(Self.menuAlertDetailsLastOutputLabel)
                        if store.detailShowLastOutput {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        }

        Menu("Style") {
            Picker(SettingsView.widgetIconLabel, selection: store.widgetIconStyleBinding) {
                ForEach(WidgetIconStyle.allCases, id: \.self) { style in
                    Text(SettingsView.widgetIconStyleName(style)).tag(style)
                }
            }
            if store.widgetIconStyle == .zelda {
                Picker(SettingsView.idleAnimationLabel, selection: store.zeldaAlertEffectBinding) {
                    ForEach(WidgetAlertEffect.allCases, id: \.self) { effect in
                        Text(SettingsView.zeldaAlertEffectName(effect)).tag(effect)
                    }
                }
            } else {
                Picker(SettingsView.idleAnimationLabel, selection: store.idleAnimationBinding) {
                    ForEach(menuIdleAnimations, id: \.self) { animation in
                        Text(SettingsView.idleAnimationName(animation)).tag(animation)
                    }
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

        Menu(Self.menuWidgetPositionHeading) {
            Picker(Self.menuCornerLabel, selection: store.cornerBinding) {
                ForEach(WidgetCorner.allCases) { c in
                    Text(SettingsView.widgetCornerLabel(c)).tag(c)
                }
            }
            Menu(Self.menuOffsetXLabel) {
                ForEach(Self.offsetPresets) { preset in
                    Button {
                        store.offsetX = preset.value
                    } label: {
                        HStack {
                            Text(preset.label)
                            if store.offsetX == preset.value {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
            Menu(Self.menuOffsetYLabel) {
                ForEach(Self.offsetPresets) { preset in
                    Button {
                        store.offsetY = preset.value
                    } label: {
                        HStack {
                            Text(preset.label)
                            if store.offsetY == preset.value {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        }

        Toggle(Self.menuLaunchAtLoginLabel, isOn: $store.launchAtLoginEnabled)
            .onChange(of: store.launchAtLoginEnabled) { _, enabled in
                LoginItemController.applyFromSettings(enabled: enabled)
            }

        Menu(Self.menuMutedProjectsHeading) {
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

        Menu(Self.menuConnectionTestHeading) {
            Button(Self.menuTestNotificationLabel) {
                Task { await SessionRegistry.shared.injectTest(soundEnabled: store.soundEnabled) }
            }
            Button(Self.menuConnectionTestLabel) {
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

        Button("Grant Accessibility…") {
            AccessibilityRaiser.requestTrust()
            PermissionDeepLink.openAccessibilityPreferences()
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

    private struct OffsetPreset: Identifiable {
        let id = UUID()
        let label: String
        let value: Int
    }

    private struct ThresholdPreset: Identifiable {
        let id = UUID()
        let label: String
        let seconds: Int
    }

    private static let menuSoundToggleLabel = "Play notification sound"
    private static let menuQuietHoursToggleLabel = "Quiet Hours"
    private static let menuThresholdHeading = "Notification Threshold"
    private static let menuThresholdCaption = "Notify only after threshold elapsed"
    private static let menuAlertDetailsHeading = "Alert Details"
    private static let menuAlertDetailsNoneLabel = "None"
    private static let menuAlertDetailsLastOutputLabel = "Last Output"
    private static let menuWidgetPositionHeading = "Widget Position"
    private static let menuCornerLabel = "Corner"
    private static let menuOffsetXLabel = "Horizontal Offset"
    private static let menuOffsetYLabel = "Vertical Offset"
    private static let menuLaunchAtLoginLabel = "Open at Login"
    private static let menuMutedProjectsHeading = "Muted Projects"
    private static let menuTestNotificationLabel = "Send test notification"
    private static let menuConnectionTestHeading = "iTerm2 Connection"
    private static let menuConnectionTestLabel = "Test iTerm2 connection"

    private static let thresholdPresets: [ThresholdPreset] = [
        .init(label: "Direct (0s)", seconds: 0),
        .init(label: "5 sec", seconds: 5),
        .init(label: "10 sec", seconds: 10),
        .init(label: "30 sec", seconds: 30),
        .init(label: "1 min", seconds: 60),
        .init(label: "3 min", seconds: 180),
        .init(label: "5 min", seconds: 300),
        .init(label: "10 min", seconds: 600)
    ]

    private static let offsetPresets: [OffsetPreset] = [
        .init(label: "Close to edge (8 pt)", value: 8),
        .init(label: "Default (16 pt)", value: 16),
        .init(label: "Roomy (32 pt)", value: 32),
        .init(label: "Far (48 pt)", value: 48),
        .init(label: "Maximum (64 pt)", value: 64)
    ]
}
