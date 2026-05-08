// App/SettingsView.swift — Phase 2 SET-01..04, plus D2-35 Path A permission trigger.
// UI-SPEC §"Settings Window" — Form with 4 sections + conditional permission banner.
// D2-29: SwiftUI Settings { ... } scene + @AppStorage; zero external deps.
// D2-30: View → Store → Registry/Helper single-direction.
// D2-21: Test button → SessionRegistry.shared.injectTest (in-memory, NOT persisted).
// D2-35 Path A: .onAppear → if permission == .unknown, trigger TCC dialog via cheap-query.
import SwiftUI
import AppKit

struct SettingsView: View {
    /// Locked Korean copy — exposed for SettingsViewTests regression guards.
    static let thresholdHeading = "알림 임계값"
    static let thresholdCaption = "이 시간 이상 걸린 작업만 알려요"
    static let soundHeading = "사운드"
    static let soundToggleLabel = "알림 사운드 재생"
    static let widgetPositionHeading = "위젯 위치"
    static let cornerLabel = "코너"
    static let offsetXLabel = "가로 오프셋"
    static let offsetYLabel = "세로 오프셋"
    static let testHeading = "테스트"
    static let testButtonLabel = "테스트 알림 보내기"

    @StateObject private var store = SettingsStore.shared

    var body: some View {
        Form {
            // Permission banner (D2-36 — visible only when denied)
            if store.applescriptPermission == .denied {
                Section {
                    PermissionBannerView()
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

            Section(Self.widgetPositionHeading) {
                Picker(Self.cornerLabel, selection: store.cornerBinding) {
                    ForEach(WidgetCorner.allCases) { c in
                        Text(c.localizedLabel).tag(c)
                    }
                }
                .pickerStyle(.menu)
                Stepper("\(Self.offsetXLabel): \(store.offsetX) pt", value: $store.offsetX, in: 0...64)
                Stepper("\(Self.offsetYLabel): \(store.offsetY) pt", value: $store.offsetY, in: 0...64)
            }

            Section(Self.testHeading) {
                Button(Self.testButtonLabel) {
                    Task { await SessionRegistry.shared.injectTest(soundEnabled: store.soundEnabled) }
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .padding(.vertical, 32)
        .padding(.horizontal, 24)
        .onAppear {
            // D2-35 Path A — trigger Apple Events permission dialog when user explicitly opens Settings.
            // The cheap-query is a no-op result; what matters is that macOS displays the TCC dialog.
            if store.applescriptPermission == .unknown {
                Task { await AppleScriptHelper.shared.triggerPermissionPrompt() }
            }
        }
    }
}
