// App/NotificationOrchestrator.swift — Phase 2 Wave 3 (02-06).
// PATTERNS.md §NotificationOrchestrator: AppDelegate component-wiring style.
// RESEARCH §"Architectural Responsibility Map": this class is the @MainActor handoff
// point between the SessionRegistry actor and the AppKit widget + AVAudioPlayer.
//
// Single-direction rule (RESEARCH Pattern 4): SettingsStore is touched at the MainActor
// notification boundary only; SessionRegistry never imports SettingsStore.
//
// AUD-02 — when SettingsStore.soundEnabled=false, present() does NOT play sound regardless
// of the playSoundOnce parameter forwarded by the registry's dedupe path.
// WIDG-05 — refreshQueueState(count:0) calls hideWidget(); count≥1 calls setQueue + updatePendingCount.
//
// D2-18 RETRACTED — no Focus/DnD detection. Sound is gated solely by SettingsStore.soundEnabled.
//
// Concrete WidgetControllerProtocol implementation lives in plan 02-07 (FloatingWidgetWindowController);
// AppDelegate (Wave 6 / 02-11) wires the concrete controller via `bind(widget:)` after construction
// to keep 02-06 and 02-07 buildable independently in the same wave.
import Foundation
import os

/// Sound abstraction — extracted so unit tests can substitute SpySoundPlayer without
/// touching CoreAudio. SoundPlayer is the production conformer.
@MainActor protocol SoundPlaying: AnyObject {
    func playOnce()
}

extension SoundPlayer: SoundPlaying {}

/// Widget abstraction — declared here so plan 02-07 can implement against it in parallel
/// (and Wave 4 02-08 popover + Wave 6 02-11 wiring consume the same shape).
@MainActor protocol WidgetControllerProtocol: AnyObject {
    func showWidget(pendingCount: Int, latest: CompletedSession?)
    func hideWidget()
    func updatePendingCount(_ n: Int, latest: CompletedSession?)
    func setQueue(_ queue: [CompletedSession])
}

@MainActor
final class NotificationOrchestrator: NotifierProtocol {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "notification")
    private weak var widget: (any WidgetControllerProtocol)?
    private let sound: any SoundPlaying
    private let settings: () -> SettingsStore   // closure so tests can swap

    /// Production constructors must inject `sound` (typically `SoundPlayer()`).
    /// Construction is @MainActor-isolated by the class annotation, so callers
    /// (AppDelegate / tests) are already in the right context to allocate AVAudioPlayer.
    init(widget: (any WidgetControllerProtocol)?,
         sound: any SoundPlaying,
         settings: @autoclosure @escaping () -> SettingsStore = SettingsStore.shared) {
        self.widget = widget
        self.sound = sound
        self.settings = settings
    }

    /// Convenience for production callers that want the default SoundPlayer.
    convenience init(widget: (any WidgetControllerProtocol)?) {
        self.init(widget: widget, sound: SoundPlayer())
    }

    /// Wave 6 wiring — AppDelegate calls this after constructing the concrete widget controller.
    func bind(widget: any WidgetControllerProtocol) {
        self.widget = widget
    }

    // MARK: - NotifierProtocol

    func present(session: CompletedSession, playSoundOnce: Bool) async {
        let store = settings()
        widget?.setQueue([session])
        store.everHadAlerts = true
        widget?.showWidget(pendingCount: 1, latest: session)
        if playSoundOnce && store.soundEnabled && !store.quietHoursEnabled {
            sound.playOnce()
            log.notice("present session=\(session.sessionID, privacy: .public) sound=on")
        } else {
            log.notice("present session=\(session.sessionID, privacy: .public) sound=off playSoundOnce=\(playSoundOnce, privacy: .public) enabled=\(store.soundEnabled, privacy: .public) quiet=\(store.quietHoursEnabled, privacy: .public)")
        }
    }

    func refreshQueueState(completed: [CompletedSession], count: Int) async {
        if count == 0 {
            widget?.hideWidget()
            log.notice("refreshQueueState: queue empty → hideWidget")
        } else {
            settings().everHadAlerts = true
            widget?.setQueue(completed)
            widget?.updatePendingCount(count, latest: completed.last)
            log.notice("refreshQueueState: count=\(count)")
        }
    }
}
