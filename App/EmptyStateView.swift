// App/EmptyStateView.swift — WO-009 popover empty-state placeholder.
// SPEC §5 Behaviors row "Onboarding" + FEATURES §3 row "빈 상태 온보딩".
// Visibility is gated by PopoverContentView: queue.isEmpty && !everHadAlerts.
import SwiftUI

struct EmptyStateView: View {
    static let message = "Listening to iTerm"

    var body: some View {
        Text(Self.message)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .accessibilityLabel(Self.message)
    }
}
