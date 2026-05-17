// App/SoundPlayer.swift — Phase 2 Wave 3 (02-06) AUD-01.
// RESEARCH Pattern 10 (lines 801-832). NSSound rejected per macOS 26 CoreAudio crash report
// (project guidance: AVAudioPlayer is the durable choice).
// D2-19: AVAudioPlayer direct. UNNotificationSound channel deliberately not used (auto-dismiss risk).
// Default sound = /System/Library/Sounds/Funk.aiff — system-resident, no asset shipping per
// CONTEXT D2 "Claude's Discretion" (사운드 파일).
//
// Threat note (T-AUDIO-01): AVAudioPlayer init throws on missing/corrupt files; we catch and log,
// leaving `player` nil so playOnce() becomes a silent no-op.
import Foundation
import AVFoundation
import os

enum SoundCue: Hashable {
    case defaultAlert
    case zeldaHeal
    case zeldaHit

    var bundledURL: URL? {
        switch self {
        case .defaultAlert:
            return nil
        case .zeldaHeal:
            return Bundle.main.url(forResource: "heal", withExtension: "mp3", subdirectory: "zelda/sound")
        case .zeldaHit:
            return Bundle.main.url(forResource: "hit", withExtension: "mp3", subdirectory: "zelda/sound")
        }
    }
}

@MainActor
final class SoundPlayer {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "notification")
    private var player: AVAudioPlayer?
    private var cuePlayers: [SoundCue: AVAudioPlayer] = [:]

    /// Default = system Funk.aiff. Test/dev can pass a custom URL.
    init(soundURL: URL = URL(fileURLWithPath: "/System/Library/Sounds/Funk.aiff")) {
        self.player = Self.loadPlayer(soundURL: soundURL, log: log)
    }

    /// Plays once. If a previous play is still in progress, restart from 0 (matches RESEARCH Pattern 10).
    /// Idempotent if player is nil (load failed) — silent no-op.
    func playOnce() {
        playOnce(cue: .defaultAlert)
    }

    func playOnce(cue: SoundCue) {
        guard let p = player(for: cue) else { return }
        p.currentTime = 0
        p.play()
    }

    private func player(for cue: SoundCue) -> AVAudioPlayer? {
        switch cue {
        case .defaultAlert:
            return player
        case .zeldaHeal, .zeldaHit:
            if let cached = cuePlayers[cue] {
                return cached
            }
            guard let url = cue.bundledURL else {
                log.error("Sound cue missing: \(String(describing: cue), privacy: .public)")
                return nil
            }
            let loaded = Self.loadPlayer(soundURL: url, log: log)
            cuePlayers[cue] = loaded
            return loaded
        }
    }

    private static func loadPlayer(soundURL: URL, log: Logger) -> AVAudioPlayer? {
        do {
            let p = try AVAudioPlayer(contentsOf: soundURL)
            p.prepareToPlay()
            return p
        } catch {
            log.error("SoundPlayer load failed at \(soundURL.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    #if DEBUG
    var playerForTesting: AVAudioPlayer? { player }
    #endif
}
