// App/SoundPlayer.swift — Phase 2 Wave 3 (02-06) AUD-01.
// RESEARCH Pattern 10 (lines 801-832). NSSound rejected per macOS 26 CoreAudio crash report
// (CLAUDE.md TL;DR row "Sound" — AVAudioPlayer is the durable choice).
// D2-19: AVAudioPlayer direct. UNNotificationSound channel deliberately not used (auto-dismiss risk).
// Default sound = /System/Library/Sounds/Funk.aiff — system-resident, no asset shipping per
// CONTEXT D2 "Claude's Discretion" (사운드 파일).
//
// Threat note (T-AUDIO-01): AVAudioPlayer init throws on missing/corrupt files; we catch and log,
// leaving `player` nil so playOnce() becomes a silent no-op.
import Foundation
import AVFoundation
import os

@MainActor
final class SoundPlayer {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "notification")
    private var player: AVAudioPlayer?

    /// Default = system Funk.aiff. Test/dev can pass a custom URL.
    init(soundURL: URL = URL(fileURLWithPath: "/System/Library/Sounds/Funk.aiff")) {
        do {
            let p = try AVAudioPlayer(contentsOf: soundURL)
            p.prepareToPlay()
            self.player = p
        } catch {
            self.player = nil
            log.error("SoundPlayer load failed at \(soundURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }

    /// Plays once. If a previous play is still in progress, restart from 0 (matches RESEARCH Pattern 10).
    /// Idempotent if player is nil (load failed) — silent no-op.
    func playOnce() {
        guard let p = player else { return }
        p.currentTime = 0
        p.play()
    }

    #if DEBUG
    var playerForTesting: AVAudioPlayer? { player }
    #endif
}
