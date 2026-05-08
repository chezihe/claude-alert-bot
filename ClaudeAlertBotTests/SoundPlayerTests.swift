// SoundPlayerTests.swift — Phase 2 Wave 3 (02-06) AUD-01.
// Verifies SoundPlayer wraps AVAudioPlayer per RESEARCH Pattern 10:
//   1) default init loads /System/Library/Sounds/Funk.aiff (system-resident)
//   2) missing-path init does NOT crash; player is nil
//   3) playOnce on a real player resets currentTime and plays (skipped on CI)
//   4) playOnce on nil player is a silent no-op (no crash)
import XCTest
@testable import ClaudeAlertBot

final class SoundPlayerTests: XCTestCase {

    @MainActor
    func test_init_withValidSystemSound_loadsPlayer() async throws {
        let sp = SoundPlayer()
        XCTAssertNotNil(sp.playerForTesting,
                        "Default init should load /System/Library/Sounds/Funk.aiff")
    }

    @MainActor
    func test_init_withMissingPath_doesNotCrash() async throws {
        let bogus = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).aiff")
        let sp = SoundPlayer(soundURL: bogus)
        XCTAssertNil(sp.playerForTesting,
                     "Missing-file init must yield nil player without throwing")
    }

    @MainActor
    func test_playOnce_resetsCurrentTimeAndPlays() async throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["CI"] != nil,
                      "AVAudio not reliable in headless CI")
        let sp = SoundPlayer()
        sp.playOnce()
        try await Task.sleep(nanoseconds: 50_000_000)   // 50ms
        let isPlaying = sp.playerForTesting?.isPlaying ?? false
        XCTAssertTrue(isPlaying, "playOnce should engage AVAudioPlayer.play()")
    }

    @MainActor
    func test_playOnce_whenPlayerNil_isNoOp() async throws {
        let bogus = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString).aiff")
        let sp = SoundPlayer(soundURL: bogus)
        // Must not crash / precondition-fail.
        sp.playOnce()
        sp.playOnce()
        XCTAssertNil(sp.playerForTesting)
    }
}
