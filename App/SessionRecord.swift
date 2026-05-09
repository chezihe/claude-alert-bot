// App/SessionRecord.swift — Phase 2 domain models (D-08 ↔ App-internal bridge).
// SESS-01..03, THR-01, AUD-01 (DedupeKey), WIDG-06 (WidgetCorner).
// D2-20 dedupe key shape: (session_id, ts_round_to_2s).
// D2-23/D2-25 sessions.json schema_version=1 (separate from D-08's schema_version=1; namespaces are independent).
import Foundation

enum LastOutputLimiter {
    static let maxBytes = 4_096

    static func capped(_ value: String?) -> String? {
        guard let value else { return nil }
        guard value.utf8.count > maxBytes else { return value }

        var result = ""
        var used = 0
        for scalar in value.unicodeScalars {
            let count = scalar.utf8.count
            guard used + count <= maxBytes else { break }
            result.unicodeScalars.append(scalar)
            used += count
        }
        return result
    }
}

enum AlertKind: String, Codable {
    case success, error, waiting

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try? container.decode(String.self)
        self = raw.flatMap(AlertKind.init(rawValue:)) ?? .success
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// In-flight start — created by user_prompt_submit, removed by matching stop or 6h GC.
struct InFlightStart: Codable, Equatable {
    let startedAt: Date
    let cwd: String?
}

/// Completed-but-unclicked alert. Stored in SessionRegistry.completed FIFO + sessions.json.
struct CompletedSession: Codable, Equatable, Identifiable {
    let sessionID: String          // matches HookEvent.session_id
    let projectName: String         // ProjectName.derive(...) result — D2-06
    let stoppedAt: Date
    let durationSec: Int?           // nil iff THR-02 fallback (start missing) — D2-16/D2-17
    let itermSessionID: String?
    let tty: String?
    let cwd: String?
    let kind: AlertKind
    let exitCode: Int?
    let startedAt: Date?
    let lastOutput: String?
    var available: Bool             // false = iTerm session gone
    var pinned: Bool

    var id: String { sessionID }    // for SwiftUI ForEach in popover

    init(sessionID: String,
         projectName: String,
         stoppedAt: Date,
         durationSec: Int?,
         itermSessionID: String?,
         tty: String?,
         cwd: String?,
         kind: AlertKind = .success,
         exitCode: Int? = nil,
         startedAt: Date? = nil,
         lastOutput: String? = nil,
         available: Bool = true,
         pinned: Bool = false) {
        self.sessionID = sessionID
        self.projectName = projectName
        self.stoppedAt = stoppedAt
        self.durationSec = durationSec
        self.itermSessionID = itermSessionID
        self.tty = tty
        self.cwd = cwd
        self.kind = kind
        self.exitCode = exitCode
        self.startedAt = startedAt
        self.lastOutput = LastOutputLimiter.capped(lastOutput)
        self.available = available
        self.pinned = pinned
    }

    enum CodingKeys: String, CodingKey {
        case sessionID
        case projectName
        case stoppedAt
        case durationSec
        case itermSessionID
        case tty
        case cwd
        case kind
        case exitCode
        case startedAt
        case lastOutput
        case available
        case pinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.sessionID = try container.decode(String.self, forKey: .sessionID)
        self.projectName = try container.decode(String.self, forKey: .projectName)
        self.stoppedAt = try container.decode(Date.self, forKey: .stoppedAt)
        self.durationSec = try container.decodeIfPresent(Int.self, forKey: .durationSec)
        self.itermSessionID = try container.decodeIfPresent(String.self, forKey: .itermSessionID)
        self.tty = try container.decodeIfPresent(String.self, forKey: .tty)
        self.cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        self.kind = try container.decodeIfPresent(AlertKind.self, forKey: .kind) ?? .success
        self.exitCode = try container.decodeIfPresent(Int.self, forKey: .exitCode)
        self.startedAt = try container.decodeIfPresent(Date.self, forKey: .startedAt)
        self.lastOutput = LastOutputLimiter.capped(try container.decodeIfPresent(String.self, forKey: .lastOutput))
        self.available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? true
        self.pinned = try container.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sessionID, forKey: .sessionID)
        try container.encode(projectName, forKey: .projectName)
        try container.encode(stoppedAt, forKey: .stoppedAt)
        try container.encodeIfPresent(durationSec, forKey: .durationSec)
        try container.encodeIfPresent(itermSessionID, forKey: .itermSessionID)
        try container.encodeIfPresent(tty, forKey: .tty)
        try container.encodeIfPresent(cwd, forKey: .cwd)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(exitCode, forKey: .exitCode)
        try container.encodeIfPresent(startedAt, forKey: .startedAt)
        try container.encodeIfPresent(lastOutput, forKey: .lastOutput)
        try container.encode(available, forKey: .available)
        try container.encode(pinned, forKey: .pinned)
    }

    /// D2-21 — SET-04 Test notification fixture. NOT persisted (D2-22) per SessionRegistry.injectTest.
    static func testFixture() -> CompletedSession {
        CompletedSession(
            sessionID: "test-\(UUID().uuidString)",
            projectName: "Test",
            stoppedAt: Date(),
            durationSec: 31,
            itermSessionID: nil,
            tty: nil,
            cwd: nil
        )
    }
}

/// AUD-01 dedupe key — (session_id, ts/2s bucket).
/// Phase 4 may extend with transcript_path; Phase 2 ships these two fields per D2-20.
struct DedupeKey: Hashable, Codable {
    let sessionID: String
    let bucketedTS: Int             // Int(ts.timeIntervalSince1970) / 2

    init(sessionID: String, bucketedTS: Int) {
        self.sessionID = sessionID
        self.bucketedTS = bucketedTS
    }

    static func from(sessionID: String, at date: Date) -> DedupeKey {
        DedupeKey(sessionID: sessionID, bucketedTS: Int(date.timeIntervalSince1970) / 2)
    }
}

/// WIDG-06 four-corner enum. RawValue String for @AppStorage compatibility (Pitfall #7).
enum WidgetCorner: String, CaseIterable, Codable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: String { rawValue }
    /// UI-SPEC: "왼쪽 위 / 오른쪽 위 / 왼쪽 아래 / 오른쪽 아래"
    var localizedLabel: String {
        switch self {
        case .topLeft: return "왼쪽 위"
        case .topRight: return "오른쪽 위"
        case .bottomLeft: return "왼쪽 아래"
        case .bottomRight: return "오른쪽 아래"
        }
    }
}

/// D2-35/D2-36 — Apple Events permission state machine.
enum PermissionStatus: String, Codable {
    case unknown, granted, denied
}

/// SESS-03 sessions.json on-disk shape. schema=1 locked; future migrations add cases here.
struct SessionsSnapshot: Codable {
    /// Bumped only when schema breaks. Phase 2 ships v1.
    var schema: Int = 1
    var inFlight: [String: InFlightStart]
    var completed: [CompletedSession]

    static let currentSchema = 1
}
