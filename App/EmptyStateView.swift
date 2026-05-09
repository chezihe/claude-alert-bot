// App/EmptyStateView.swift — WO-009 popover empty-state placeholder.
// SPEC §5 Behaviors row "Onboarding" + FEATURES §3 row "빈 상태 온보딩".
// Note: this WO does NOT gate on `everHadAlerts` (separate follow-up). Always renders when queue.isEmpty.
import SwiftUI

struct EmptyStateView: View {
    static let message = "Listening for Claude sessions"

    var body: some View {
        Text(Self.message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .accessibilityLabel(Self.message)
    }
}
