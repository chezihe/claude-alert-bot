// NotificationOrchestratorTests.swift — Phase 2 Wave 3 (02-06).
// Verifies the @MainActor orchestrator routes NotifierProtocol calls to:
//   • WidgetControllerProtocol (showWidget / hideWidget / updatePendingCount / setQueue)
//   • SoundPlaying (gated by SettingsStore.soundEnabled AND playSoundOnce flag)
//
// AUD-02 invariant: when SettingsStore.soundEnabled=false, sound NEVER plays even if
// SessionRegistry passes playSoundOnce=true.
// WIDG-05 invariant: refreshQueueState(count: 0) calls hideWidget().
import XCTest
@testable import ClaudeAlertBot

@MainActor
final class SpyWidget: WidgetControllerProtocol {
    struct ShowCall: Equatable { let pendingCount: Int; let latestID: String? }
    struct UpdateCall: Equatable { let n: Int; let latestID: String? }

    private(set) var showCalls: [ShowCall] = []
    private(set) var hideCount = 0
    private(set) var updateCalls: [UpdateCall] = []
    private(set) var queueCalls: [[String]] = []

    func showWidget(pendingCount: Int, latest: CompletedSession?) {
        showCalls.append(.init(pendingCount: pendingCount, latestID: latest?.sessionID))
    }
    func hideWidget() { hideCount += 1 }
    func updatePendingCount(_ n: Int, latest: CompletedSession?) {
        updateCalls.append(.init(n: n, latestID: latest?.sessionID))
    }
    func setQueue(_ queue: [CompletedSession]) {
        queueCalls.append(queue.map(\.sessionID))
    }
}

@MainActor
final class SpySoundPlayer: SoundPlaying {
    private(set) var playOnceCount = 0
    func playOnce() { playOnceCount += 1 }
}

final class NotificationOrchestratorTests: XCTestCase {

    private func makeSession(_ id: String = "sess-A") -> CompletedSession {
        CompletedSession(
            sessionID: id,
            projectName: "demo",
            stoppedAt: Date(),
            durationSec: 31,
            itermSessionID: nil,
            tty: nil,
            cwd: nil
        )
    }

    @MainActor
    override func setUp() async throws {
        // Reset SettingsStore.soundEnabled to its default `true` between tests
        // (UserDefaults persists across XCTest invocations; explicit reset prevents
        // cross-test leakage).
        SettingsStore.shared.soundEnabled = true
        SettingsStore.shared.quietHoursEnabled = false
        SettingsStore.shared.everHadAlerts = false
    }

    @MainActor
    override func tearDown() async throws {
        SettingsStore.shared.soundEnabled = true
        SettingsStore.shared.quietHoursEnabled = false
        SettingsStore.shared.everHadAlerts = false
    }

    @MainActor
    func test_present_callsWidgetShow_andPlaysSound_whenEnabled() async {
        SettingsStore.shared.soundEnabled = true
        let widget = SpyWidget()
        let sound = SpySoundPlayer()
        let orch = NotificationOrchestrator(widget: widget, sound: sound)
        let s = makeSession("sess-A")

        await orch.present(session: s, playSoundOnce: true)

        XCTAssertEqual(widget.showCalls.count, 1)
        XCTAssertEqual(widget.showCalls.first?.latestID, "sess-A")
        XCTAssertEqual(sound.playOnceCount, 1)
    }

    @MainActor
    func test_present_marksEverHadAlerts() async {
        let widget = SpyWidget()
        let sound = SpySoundPlayer()
        let orch = NotificationOrchestrator(widget: widget, sound: sound)

        await orch.present(session: makeSession(), playSoundOnce: false)

        XCTAssertTrue(SettingsStore.shared.everHadAlerts)
    }

    @MainActor
    func test_present_skipsSound_whenSoundDisabled_AUD_02() async {
        SettingsStore.shared.soundEnabled = false
        let widget = SpyWidget()
        let sound = SpySoundPlayer()
        let orch = NotificationOrchestrator(widget: widget, sound: sound)

        await orch.present(session: makeSession(), playSoundOnce: true)

        XCTAssertEqual(widget.showCalls.count, 1, "Widget must still show")
        XCTAssertEqual(sound.playOnceCount, 0, "AUD-02: sound MUST NOT play when toggle off")
    }

    @MainActor
    func test_present_skipsSound_whenQuietHoursEnabled() async {
        SettingsStore.shared.soundEnabled = true
        SettingsStore.shared.quietHoursEnabled = true
        let widget = SpyWidget()
        let sound = SpySoundPlayer()
        let orch = NotificationOrchestrator(widget: widget, sound: sound)

        await orch.present(session: makeSession(), playSoundOnce: true)

        XCTAssertEqual(widget.showCalls.count, 1, "Quiet Hours must still queue/show the widget")
        XCTAssertEqual(sound.playOnceCount, 0, "Quiet Hours must suppress sound")
    }

    @MainActor
    func test_present_skipsSound_whenPlaySoundOnceFalse() async {
        SettingsStore.shared.soundEnabled = true
        let widget = SpyWidget()
        let sound = SpySoundPlayer()
        let orch = NotificationOrchestrator(widget: widget, sound: sound)

        await orch.present(session: makeSession(), playSoundOnce: false)

        XCTAssertEqual(widget.showCalls.count, 1)
        XCTAssertEqual(sound.playOnceCount, 0,
                       "Registry-side dedupe path: playSoundOnce=false suppresses sound")
    }

    @MainActor
    func test_refreshQueueState_emptyCount_hidesWidget_WIDG_05() async {
        let widget = SpyWidget()
        let sound = SpySoundPlayer()
        let orch = NotificationOrchestrator(widget: widget, sound: sound)

        await orch.refreshQueueState(completed: [], count: 0)

        XCTAssertEqual(widget.hideCount, 1, "WIDG-05: count==0 → hideWidget")
        XCTAssertTrue(widget.updateCalls.isEmpty)
        XCTAssertTrue(widget.queueCalls.isEmpty)
    }

    @MainActor
    func test_refreshQueueState_nonEmptyCount_updatesPendingCount() async {
        let widget = SpyWidget()
        let sound = SpySoundPlayer()
        let orch = NotificationOrchestrator(widget: widget, sound: sound)
        let s1 = makeSession("sess-1")
        let s2 = makeSession("sess-2")

        await orch.refreshQueueState(completed: [s1, s2], count: 2)

        XCTAssertEqual(widget.queueCalls, [["sess-1", "sess-2"]])
        XCTAssertEqual(widget.updateCalls.count, 1)
        XCTAssertEqual(widget.updateCalls.first?.n, 2)
        XCTAssertEqual(widget.updateCalls.first?.latestID, "sess-2",
                       "latest = last element of completed array")
        XCTAssertEqual(widget.hideCount, 0)
    }

    @MainActor
    func test_refreshQueueState_nonEmpty_marksEverHadAlerts() async {
        let widget = SpyWidget()
        let sound = SpySoundPlayer()
        let orch = NotificationOrchestrator(widget: widget, sound: sound)

        await orch.refreshQueueState(completed: [makeSession("sess-restored")], count: 1)

        XCTAssertTrue(SettingsStore.shared.everHadAlerts)
    }

    @MainActor
    func test_orchestrator_conformsToNotifierProtocol() {
        let widget = SpyWidget()
        let orch = NotificationOrchestrator(widget: widget, sound: SpySoundPlayer())
        let n: any NotifierProtocol = orch
        XCTAssertNotNil(n, "Compile-time check: NotificationOrchestrator must satisfy NotifierProtocol")
    }
}
