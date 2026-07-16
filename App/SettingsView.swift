// App/SettingsView.swift — locked copy constants + label helpers.
// The standalone Settings window was removed in Phase 3 (03-09): every user-facing
// setting lives in MenuBarMenuContent (ClaudeAlertBotApp.swift). This namespace keeps
// the copy contract (SettingsViewTests regression guards) and the label helpers the
// menu consumes — there is deliberately no View here.
import Foundation

enum SettingsView {
    /// Locked Korean copy — exposed for SettingsViewTests regression guards.
    static let thresholdHeading = "알림 임계값"
    static let thresholdCaption = "이 시간 이상 걸린 작업만 알려요"
    static let soundHeading = "사운드"
    static let soundToggleLabel = "알림 사운드 재생"
    static let quietHoursHeading = "Quiet Hours"
    static let quietHoursToggleLabel = "Quiet Hours"
    static let idleAnimationHeading = "Idle Animation"
    static let idleAnimationLabel = "Animation"
    static let widgetIconLabel = "Icon"
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
        case .magic: return "Magic"
        }
    }

    static func widgetIconStyleName(_ style: WidgetIconStyle) -> String {
        switch style {
        case .claude: return "Claude"
        case .zelda: return "Zelda"
        }
    }

    static func zeldaAlertEffectName(_ effect: WidgetAlertEffect) -> String {
        switch effect {
        case .heal: return "Heal"
        case .hit: return "Hit"
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
}
