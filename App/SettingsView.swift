// App/SettingsView.swift — Phase 2 SET-01..04, plus D2-35 Path A permission trigger.
// UI-SPEC §"Settings Window" — Form with 4 sections + conditional permission banner.
// D2-29: SwiftUI Settings { ... } scene + @AppStorage; zero external deps.
// D2-30: View → Store → Registry/Helper single-direction.
// D2-21: Test button → SessionRegistry.shared.injectTest (in-memory, NOT persisted).
// D2-35 Path A: .onAppear → verify Apple Events permission via cheap-query.
import SwiftUI
import AppKit

struct SettingsView: View {
    /// Locked Korean copy — exposed for SettingsViewTests regression guards.
    static let thresholdHeading = "알림 임계값"
    static let thresholdCaption = "이 시간 이상 걸린 작업만 알려요"
    static let soundHeading = "사운드"
    static let soundToggleLabel = "알림 사운드 재생"
    static let quietHoursHeading = "Quiet Hours"
    static let quietHoursToggleLabel = "Quiet Hours"
    static let idleAnimationHeading = "Idle Animation"
    static let idleAnimationLabel = "Animation"
    static let themeHeading = "Theme"
    static let themeLabel = "Appearance"
    static let reduceMotionHeading = "Reduce Motion"
    static let reduceMotionLabel = "Mode"
    static let startupHeading = "Startup"
    static let launchAtLoginToggleLabel = "Open at Login"
    static let widgetPositionHeading = "Widget Position"
    static let cornerLabel = "Corner"
    static let offsetXLabel = "Horizontal Offset"
    static let offsetYLabel = "Vertical Offset"
    static let mutedProjectsHeading = "Muted Projects"
    static let unmuteButtonLabel = "Unmute"
    static let testHeading = "테스트"
    static let testButtonLabel = "테스트 알림 보내기"

    // D3-15 — Korean section header + button label (T-COPY-DRIFT-01;
    // matches Phase 2 settings tone for buttons like testButtonLabel).
    static let connectionTestHeading = "iTerm2 연결"
    static let connectionTestLabel = "iTerm2 연결 테스트"

    // D3-19 — minimal English status labels (T-COPY-DRIFT-01;
    // Korean→English split for status only per minimal-UI-copy memory rule).
    static let connectionTestSuccessFmt = "Connected at %@"           // %@ = HH:mm
    static let iTermNotRunningLabel = "iTerm2 is not running"
    static let connectionDeniedLabel = "Automation permission denied"

    @StateObject private var store = SettingsStore.shared

    // D3-18 — transient SET-05 result (auto-hides after 5s; persisted last-success
    // time lives in store.lastConnectionTestAt).
    @State private var connectionTestResult: JumpResult? = nil
    @State private var connectionTestResultAt: Date = Date()
    @State private var hideResultTask: Task<Void, Never>? = nil
    @State private var accessibilityTrusted = true
    @State private var hasCheckedAccessibilityTrust = false
    @State private var isCheckingAutomationPermission = false
    @State private var automationPermissionCheckTask: Task<Void, Never>? = nil

    var body: some View {
        Form {
            // Permission banner (D2-36 — visible only when denied)
            if store.applescriptPermission == .denied && !isCheckingAutomationPermission {
                Section {
                    PermissionBannerView()
                }
            }

            // D3-21 — Accessibility permission banner. Cross-Space window raise requires AX.
            if hasCheckedAccessibilityTrust && !accessibilityTrusted {
                Section {
                    AccessibilityPermissionBannerView()
                }
            }

            Section(Self.thresholdHeading) {
                Stepper(value: $store.thresholdSeconds, in: 5...600, step: 5) {
                    Text("\(store.thresholdSeconds) 초")
                }
                Text(Self.thresholdCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(Self.soundHeading) {
                Toggle(Self.soundToggleLabel, isOn: $store.soundEnabled)
            }

            Section(Self.quietHoursHeading) {
                Toggle(Self.quietHoursToggleLabel, isOn: $store.quietHoursEnabled)
            }

            Section(Self.idleAnimationHeading) {
                Picker(Self.idleAnimationLabel, selection: store.idleAnimationBinding) {
                    ForEach(IdleAnimation.allCases, id: \.self) { animation in
                        Text(Self.idleAnimationName(animation)).tag(animation)
                    }
                }
                .pickerStyle(.menu)
            }

            Section(Self.themeHeading) {
                Picker(Self.themeLabel, selection: store.themeModeBinding) {
                    ForEach(ThemeMode.allCases, id: \.self) { mode in
                        Text(Self.themeModeName(mode)).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            Section(Self.reduceMotionHeading) {
                Picker(Self.reduceMotionLabel, selection: store.reduceMotionPreferenceBinding) {
                    ForEach(ReduceMotionPreference.allCases, id: \.self) { preference in
                        Text(Self.reduceMotionPreferenceName(preference)).tag(preference)
                    }
                }
                .pickerStyle(.menu)
            }

            Section(Self.startupHeading) {
                Toggle(Self.launchAtLoginToggleLabel, isOn: $store.launchAtLoginEnabled)
                    .onChange(of: store.launchAtLoginEnabled) { _, enabled in
                        LoginItemController.applyFromSettings(enabled: enabled)
                    }
            }

            Section(Self.widgetPositionHeading) {
                Picker(Self.cornerLabel, selection: store.cornerBinding) {
                    ForEach(WidgetCorner.allCases) { c in
                        Text(Self.widgetCornerLabel(c)).tag(c)
                    }
                }
                .pickerStyle(.menu)
                Stepper("\(Self.offsetXLabel): \(store.offsetX) pt", value: $store.offsetX, in: 0...64)
                Stepper("\(Self.offsetYLabel): \(store.offsetY) pt", value: $store.offsetY, in: 0...64)
            }

            let now = Date()
            let activeMutes = MutedProjectsRules.activeMutes(store.mutedProjects, now: now)
            if !activeMutes.isEmpty {
                Section(Self.mutedProjectsHeading) {
                    ForEach(activeMutes, id: \.project) { entry in
                        HStack {
                            Text(entry.project)
                            Text("· " + MutedProjectsRules.remainingMinutesLabel(expiresAt: entry.expiresAt, now: now))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button(Self.unmuteButtonLabel) {
                                store.unmute(project: entry.project)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }

            Section(Self.testHeading) {
                Button(Self.testButtonLabel) {
                    Task { await SessionRegistry.shared.injectTest(soundEnabled: store.soundEnabled) }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }

            // D3-15..20 SET-05 — iTerm2 connection self-test (Apple Events permission + reachability).
            Section(Self.connectionTestHeading) {
                Button(Self.connectionTestLabel) {
                    Task { await runConnectionTest() }
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                // Transient result (5s) takes precedence; otherwise show persisted last-success.
                if let result = connectionTestResult {
                    switch result {
                    case .ok:
                        Text(String(format: Self.connectionTestSuccessFmt, hhmm(connectionTestResultAt)))
                            .font(.caption).foregroundStyle(.secondary)
                    case .iTermNotRunning:
                        Text(Self.iTermNotRunningLabel).font(.caption).foregroundStyle(.secondary)
                    case .permissionDenied:
                        Text(Self.connectionDeniedLabel).font(.caption).foregroundStyle(.red)
                    case .missing, .timeout, .otherError:
                        // testConnection should never return these — they belong to the jump path.
                        // Defensive fallback: show "not running" since the connection isn't actionable.
                        Text(Self.iTermNotRunningLabel).font(.caption).foregroundStyle(.secondary)
                    }
                } else if let last = store.lastConnectionTestAt {
                    Text(String(format: Self.connectionTestSuccessFmt, hhmm(last)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .onAppear {
            refreshAccessibilityTrust()
            refreshAutomationPermissionIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshAccessibilityTrust()
            refreshAutomationPermissionIfNeeded()
        }
    }

    // MARK: - SET-05 helpers (D3-15..20)

    private func refreshAccessibilityTrust() {
        accessibilityTrusted = AccessibilityRaiser.isTrusted()
        hasCheckedAccessibilityTrust = true
    }

    private func refreshAutomationPermissionIfNeeded() {
        guard automationPermissionCheckTask == nil else { return }
        guard store.applescriptPermission != .granted else {
            isCheckingAutomationPermission = false
            return
        }
        isCheckingAutomationPermission = true
        automationPermissionCheckTask = Task {
            await AppleScriptHelper.shared.triggerPermissionPrompt()
            await MainActor.run {
                isCheckingAutomationPermission = false
                automationPermissionCheckTask = nil
            }
        }
    }

    static func widgetCornerLabel(_ corner: WidgetCorner) -> String {
        switch corner {
        case .topLeft: return "Top Left"
        case .topRight: return "Top Right"
        case .bottomLeft: return "Bottom Left"
        case .bottomRight: return "Bottom Right"
        }
    }

    static func idleAnimationName(_ animation: IdleAnimation) -> String {
        switch animation {
        case .bounce: return "Bounce"
        case .heart: return "Heart"
        case .ring: return "Ring"
        case .roam: return "Roam"
        case .rage: return "🤬 Rage"
        }
    }

    static func themeModeName(_ mode: ThemeMode) -> String {
        switch mode {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    static func reduceMotionPreferenceName(_ preference: ReduceMotionPreference) -> String {
        switch preference {
        case .system: return "System"
        case .reduced: return "Reduced"
        }
    }

    /// D3-16 — SET-05 button handler. Calls AppleScriptHelper.testConnection() and
    /// branches on the result: .ok persists lastConnectionTestAt; .permissionDenied
    /// also opens the System Settings deep-link (D3-16 deny path: button + banner +
    /// deep-link all surface together so the user has every recovery affordance visible).
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

            // 5s auto-hide. Cancel any prior pending hide so the latest press wins.
            hideResultTask?.cancel()
            hideResultTask = Task {
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                if Task.isCancelled { return }
                await MainActor.run { connectionTestResult = nil }
            }
        }
    }

    /// D3-19 — HH:mm formatter for the "Connected at %@" status label.
    private func hhmm(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
