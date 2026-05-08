// App/PopoverRowView.swift — Phase 2 / Plan 02-08 popover row.
// UI-SPEC §"Popover row states" — default / hover / orphan / same-project-duplicate.
// D2-06 row display rules (project name + optional time suffix); D2-08 click action;
// D2-16 orphan `?` trailing indicator in secondaryLabelColor.
import SwiftUI
import AppKit

struct PopoverRowView: View {
    let session: CompletedSession
    let showTimeSuffix: Bool
    let onClick: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onClick) {
            HStack(spacing: 8) {
                Text(session.projectName)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(NSColor.labelColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer()
                if showTimeSuffix {
                    Text("· \(PopoverContentRules.timeSuffix(for: session.stoppedAt))")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                }
                if PopoverContentRules.showsOrphanIndicator(session: session) {
                    Text("?")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(NSColor.secondaryLabelColor))
                        .accessibilityLabel("경과 시간 알 수 없음")
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isHovered ? Color(NSColor.controlAccentColor).opacity(0.12) : Color.clear
            )
            .animation(.easeInOut(duration: 0.12), value: isHovered)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .accessibilityLabel("\(session.projectName) 작업 완료, 클릭하여 정리")
    }
}
