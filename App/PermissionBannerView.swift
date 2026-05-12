// App/PermissionBannerView.swift — Phase 2 D2-36 denied-state banner.
// UI-SPEC §"Permission Banner" — yellow-tint banner with explainer + System Settings CTA.
// D2-36 — button calls PermissionDeepLink.openAutomationPreferences() (sequential URL fallback).
import SwiftUI
import AppKit

struct PermissionBannerView: View {
    /// Locked Korean copy — referenced by SettingsViewTests for regression protection.
    static let headlineCopy = "자동화 권한이 꺼져 있어요"
    static let bodyCopy = "이미 보고 있는 터미널에서도 알림이 뜰 수 있습니다."
    static let buttonCopy = "시스템 설정 열기"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(NSColor.systemYellow))
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.headlineCopy)
                    .font(.system(size: 13, weight: .semibold))
                Text(Self.bodyCopy)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
            Spacer()
            Button(Self.buttonCopy) {
                PermissionDeepLink.openAutomationPreferences()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.systemYellow).opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.systemYellow).opacity(0.4), lineWidth: 1)
                )
        )
    }
}

/// D3-21 — Accessibility permission banner, shown when AX is not trusted. Required
/// for cross-Space iTerm2 window raising (full-screen iTerm windows in separate
/// Mission Control Spaces).
struct AccessibilityPermissionBannerView: View {
    static let headlineCopy = "손쉬운 사용 권한이 필요해요"
    static let bodyCopy = "전체화면 Space의 iTerm 창으로 점프하려면 필요합니다."
    static let buttonCopy = "시스템 설정 열기"

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "accessibility")
                .foregroundStyle(Color(NSColor.systemBlue))
                .font(.system(size: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.headlineCopy)
                    .font(.system(size: 13, weight: .semibold))
                Text(Self.bodyCopy)
                    .font(.system(size: 12))
                    .foregroundStyle(Color(NSColor.secondaryLabelColor))
            }
            Spacer()
            Button(Self.buttonCopy) {
                PermissionDeepLink.openAccessibilityPreferences()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.systemBlue).opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.systemBlue).opacity(0.35), lineWidth: 1)
                )
        )
    }
}
