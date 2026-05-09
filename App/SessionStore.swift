// App/SessionStore.swift — Phase 2 SESS-03 atomic persistence.
// D2-23: atomic rename pattern (Foundation .atomic = temp + rename(2) on APFS).
// D2-24: ignore stale .tmp residue (Foundation handles internally).
// D2-25: file at SocketPaths.sessionsJSONPath, 0600 perms (parent dir 0700 from Phase 1).
// UI-SPEC line 190: corrupt file → OSLog .error + rename + boot empty.
import Foundation
import os

actor SessionStore {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "registry")
    private let url: URL

    init(url: URL) {
        self.url = url
    }

    /// Convenience constructor using the locked SocketPaths constant.
    static func atDefaultLocation() -> SessionStore {
        SessionStore(url: URL(fileURLWithPath: SocketPaths.sessionsJSONPath))
    }

    func save(_ snapshot: SessionsSnapshot) async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]   // determinism for diff/test
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: [.atomic])
            // Apply 0600 — parent dir is 0700 from Phase 1 ensureDirectories
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            log.error("sessions.json save failed: \(String(describing: error), privacy: .public)")
            // NOTE (Phase 5 review): privacy: .public during dev verification window.
        }
    }

    func load() async -> SessionsSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else {
            log.error("sessions.json read failed at \(self.url.path, privacy: .public)")
            renameCorrupted()
            return nil
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let snap = try decoder.decode(SessionsSnapshot.self, from: data)
            guard snap.schema == SessionsSnapshot.currentSchema else {
                log.error("sessions.json schema=\(snap.schema) — expected \(SessionsSnapshot.currentSchema). Renaming.")
                renameCorrupted()
                return nil
            }
            let (migrated, migratedCount) = Self.migrateItermIDs(in: snap)
            if migratedCount > 0 {
                log.notice("D3-03: migrated \(migratedCount, privacy: .public) sessions to UUID-only iterm_session_id")
            }
            return migrated
        } catch {
            log.error("sessions.json decode failed: \(String(describing: error), privacy: .public). Renaming.")
            renameCorrupted()
            return nil
        }
    }

    /// D3-03 — strip envelope-format `wXtYpZ:UUID` → `UUID-only`.
    /// Idempotent: legacy UUID-only entries pass through unchanged (iTermSessionID.uuid).
    /// In-memory only; the next save() cycle writes back normalized form.
    /// CONTEXT D3-03: no schema bump (SessionsSnapshot.currentSchema stays at 1).
    private static func migrateItermIDs(in snap: SessionsSnapshot) -> (SessionsSnapshot, migrated: Int) {
        var migrationCount = 0
        let newCompleted = snap.completed.map { c -> CompletedSession in
            guard let raw = c.itermSessionID, raw.contains(":") else { return c }
            guard let stripped = iTermSessionID.uuid(fromRaw: raw), stripped != raw else { return c }
            migrationCount += 1
            return CompletedSession(
                sessionID: c.sessionID,
                projectName: c.projectName,
                stoppedAt: c.stoppedAt,
                durationSec: c.durationSec,
                itermSessionID: stripped,
                tty: c.tty,
                cwd: c.cwd,
                kind: c.kind,
                exitCode: c.exitCode,
                startedAt: c.startedAt,
                lastOutput: c.lastOutput,
                available: c.available,
                pinned: c.pinned
            )
        }
        var result = snap
        result.completed = newCompleted
        return (result, migrationCount)
    }

    /// UI-SPEC: rename `sessions.json` → `sessions.json.corrupt-{ts}` and boot empty.
    private func renameCorrupted() {
        let ts = Int(Date().timeIntervalSince1970)
        let dest = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(ts)")
        do {
            try FileManager.default.moveItem(at: url, to: dest)
            log.notice("sessions.json renamed → \(dest.lastPathComponent, privacy: .public)")
        } catch {
            log.error("sessions.json corrupt-rename failed: \(String(describing: error), privacy: .public)")
        }
    }
}
