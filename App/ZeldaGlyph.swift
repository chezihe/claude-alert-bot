// App/ZeldaGlyph.swift — Zelda-style widget icon: frame-animated character + heart badge.
// Idle: 2-frame loop at 0.45s/frame. Alert: one-shot heal/hit sequence at 0.18s/frame
// (final frame ×1.5), then falls back to the idle loop.
// Heart badge replaces the "+N" capsule: 1–3 hearts, plus a "+N" overflow past 3.
import SwiftUI
import AppKit

struct ZeldaGlyph: View {
    let widgetSide: WidgetSide
    let alertEffect: WidgetAlertEffect
    let idleStartedAt: Date
    let alertStartedAt: Date

    static let idleFrameDuration: TimeInterval = 0.45
    static let alertFrameDuration: TimeInterval = 0.18

    var body: some View {
        TimelineView(.animation) { context in
            let frameName = Self.frameName(
                at: context.date,
                idleStartedAt: idleStartedAt,
                alertStartedAt: alertStartedAt,
                effect: alertEffect
            )
            Image(nsImage: bundleImage(named: frameName, subdirectory: ZeldaFrame.characterSubdirectory(side: widgetSide)))
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }

    static func frameName(
        at date: Date,
        idleStartedAt: Date,
        alertStartedAt: Date,
        effect: WidgetAlertEffect
    ) -> String {
        let alertFrames = ZeldaFrame.alertFrames(effect: effect)
        let alertAge = date.timeIntervalSince(alertStartedAt)
        if alertAge >= 0 {
            var elapsed: TimeInterval = 0
            for frameName in alertFrames {
                let duration = alertFrameDuration * ZeldaFrame.alertFrameDurationMultiplier(frameName: frameName)
                if alertAge < elapsed + duration {
                    return frameName
                }
                elapsed += duration
            }
        }
        let idleAge = max(0, date.timeIntervalSince(idleStartedAt))
        let index = Int(idleAge / idleFrameDuration) % ZeldaFrame.idleFrames.count
        return ZeldaFrame.idleFrames[index]
    }
}

struct ZeldaHeartBadge: View {
    let pendingCount: Int

    static let offset = CGSize(width: -1, height: -18)

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Image(nsImage: bundleImage(named: Self.frameName(pendingCount: pendingCount), subdirectory: "adventure-widget/status-badge"))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 45, height: 24)
            if let overflow = Self.overflowText(pendingCount: pendingCount) {
                Text(overflow)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)
            }
        }
        .offset(x: Self.offset.width, y: Self.offset.height)
        .accessibilityHidden(true)
    }

    static func frameName(pendingCount: Int) -> String {
        switch min(max(pendingCount, 1), 3) {
        case 1: return "heart_frame_01"
        case 2: return "heart_frame_02"
        default: return "heart_frame_03"
        }
    }

    /// Plain "+N" (no capsule) for sessions beyond the three drawn hearts.
    static func overflowText(pendingCount: Int) -> String? {
        pendingCount > 3 ? "+\(pendingCount - 3)" : nil
    }
}

private func bundleImage(named name: String, subdirectory: String) -> NSImage {
    if let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: subdirectory),
       let image = NSImage(contentsOf: url) {
        return image
    }
    return NSImage(size: NSSize(width: 1, height: 1))
}
