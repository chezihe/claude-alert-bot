// Reporter/main.swift — cab-report: Claude Code / Codex hook reporter.
// Triggered as Stop, UserPromptSubmit, Notification and PostToolUse hooks; argv[1] is the event
// ("stop", "user_prompt_submit", "notification", "question_answered"; default "stop").
// Builds the D-08 envelope (schema_version=1, decoded by App/HookEvent.swift), appends it to
// hook.log and forwards it to the App socket.
// Hard contract: ALWAYS exit 0 (HOOK-03 / D-02). Never write to stdout/stderr (Pitfall #3).
// Compiled so hooks need no python3/nc — a missing CLT python3 stub silently dropped alerts.
import Foundation
import Darwin

signal(SIGPIPE, SIG_IGN)

let logMaxBytes = 1_048_576                // rotate to hook.log.1 past 1 MiB (one generation kept)
let lastOutputMaxBytes = 4096
let transcriptTailMaxBytes = 2 * 1024 * 1024

let environment = ProcessInfo.processInfo.environment
let home = environment["HOME"] ?? NSHomeDirectory()
let socketPath = "\(home)/Library/Application Support/ClaudeAlertBot/sock"
let logDir = "\(home)/Library/Logs/ClaudeAlertBot"
let logPath = "\(logDir)/hook.log"

let event = CommandLine.arguments.dropFirst().first ?? "stop"

// MARK: - JSON helpers

func nonEmpty(_ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return value
}

func isBool(_ value: Any?) -> Bool {
    guard let number = value as? NSNumber else { return false }
    return CFGetTypeID(number) == CFBooleanGetTypeID()
}

func isNumber(_ value: Any?) -> Bool {
    value is NSNumber && !isBool(value)
}

func isInteger(_ value: Any?) -> Bool {
    guard isNumber(value), let number = value as? NSNumber else { return false }
    return !CFNumberIsFloatType(number)
}

func jsonText(_ object: Any) -> String? {
    guard let data = try? JSONSerialization.data(withJSONObject: object,
                                                 options: [.fragmentsAllowed, .withoutEscapingSlashes]) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

// MARK: - Time

func utcTimestamp(fractional: Bool) -> String {
    var tv = timeval()
    gettimeofday(&tv, nil)
    var seconds = tv.tv_sec
    var parts = tm()
    gmtime_r(&seconds, &parts)
    let base = String(format: "%04d-%02d-%02dT%02d:%02d:%02d",
                      parts.tm_year + 1900, parts.tm_mon + 1, parts.tm_mday,
                      parts.tm_hour, parts.tm_min, parts.tm_sec)
    return fractional ? base + String(format: ".%06dZ", Int(tv.tv_usec)) : base + "Z"
}

func epoch(_ value: Any?) -> Any? {
    if isNumber(value) { return value }
    guard let text = value as? String else { return nil }
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = formatter.date(from: text) { return date.timeIntervalSince1970 }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: text)?.timeIntervalSince1970
}

// MARK: - Text extraction

func capUTF8(_ value: Any?) -> String? {
    guard let text = value as? String else { return nil }
    var bytes = Array(text.utf8.prefix(lastOutputMaxBytes))
    // Drop a trailing partial scalar so the cut never lands mid-character.
    while !bytes.isEmpty, String(bytes: bytes, encoding: .utf8) == nil {
        bytes.removeLast()
    }
    return String(decoding: bytes, as: UTF8.self)
}

func contentText(_ content: Any?) -> String? {
    if let text = content as? String { return text }
    guard let items = content as? [Any] else { return nil }
    let parts = items.compactMap { item -> String? in
        if let text = item as? String { return text }
        return (item as? [String: Any])?["text"] as? String
    }
    return parts.isEmpty ? nil : parts.joined(separator: "\n")
}

func payloadText(_ payload: [String: Any]) -> String? {
    for key in ["message", "output", "result", "summary", "text"] {
        if let text = payload[key] as? String { return text }
    }
    return contentText(payload["content"])
}

func transcriptTailLines(_ path: String) -> [Substring] {
    // Long sessions grow the transcript to tens of MB and the stop hook re-reads it on a
    // retry loop — cap IO to the tail. The consumer wants the LATEST matching line,
    // which lives at the end of the JSONL file.
    guard let handle = FileHandle(forReadingAtPath: path) else { return [] }
    defer { try? handle.close() }
    guard let size = try? handle.seekToEnd() else { return [] }
    let start = size > UInt64(transcriptTailMaxBytes) ? size - UInt64(transcriptTailMaxBytes) : 0
    guard (try? handle.seek(toOffset: start)) != nil,
          var data = try? handle.readToEnd() else { return [] }
    if start > 0 {
        guard let cut = data.firstIndex(of: UInt8(ascii: "\n")) else { return [] }
        data = data[data.index(after: cut)...]
    }
    return String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline)
}

func transcriptLastOutput(_ path: String) -> String? {
    var latest: String?
    for line in transcriptTailLines(path) {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else {
            continue
        }
        let payload = object["payload"] as? [String: Any] ?? [:]
        let message = object["message"] as? [String: Any] ?? [:]
        var candidate: String?
        if message["role"] as? String == "assistant" {
            candidate = contentText(message["content"])
        } else if object["type"] as? String == "assistant" {
            candidate = payloadText(payload) ?? contentText(object["content"])
        } else if payload["type"] as? String == "message" {
            candidate = payloadText(payload)
        } else if object["type"] as? String == "event_msg", payload["type"] as? String == "agent_message" {
            candidate = payload["message"] as? String
        }
        if let candidate, !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            latest = candidate
        }
    }
    return latest
}

/// Logged to hook.log to measure how often the Stop hook actually waits for the transcript.
var transcriptWait: (attempts: Int, found: Bool)?

func waitTranscriptLastOutput(_ path: String) -> String? {
    // Claude may write the final assistant line just after Stop fires — retry briefly.
    for attempt in 0..<8 {
        if let output = transcriptLastOutput(path) {
            transcriptWait = (attempt + 1, true)
            return output
        }
        if attempt < 7 { usleep(100_000) }
    }
    transcriptWait = (8, false)
    return nil
}

// MARK: - Envelope

func isCodexMemoryEvent(_ envelope: [String: Any]) -> Bool {
    guard let cwd = envelope["cwd"] as? String, !home.isEmpty else { return false }
    let memories = URL(fileURLWithPath: "\(home)/.codex/memories").standardizedFileURL.path
    let resolved = URL(fileURLWithPath: (cwd as NSString).expandingTildeInPath).standardizedFileURL.path
    let hasTranscript = envelope["transcript_path"].map { !($0 is NSNull) } ?? false
    return !hasTranscript && (resolved == memories || resolved.hasPrefix(memories + "/"))
}

func ttyPath() -> String? {
    guard let name = ttyname(STDIN_FILENO) else { return nil }
    let path = String(cString: name)
    return path.hasPrefix("/dev/") ? path : nil
}

func buildEnvelope(stdin raw: String, cwdFallback: String, ppid: pid_t) -> [String: Any]? {
    var parsed: [String: Any] = [:]
    if !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if let object = try? JSONSerialization.jsonObject(with: Data(raw.utf8)) {
            guard let dictionary = object as? [String: Any] else { return nil }
            parsed = dictionary
        } else {
            parsed = ["raw": raw]
        }
    }

    let cwd = nonEmpty(parsed["cwd"] as? String) ?? nonEmpty(cwdFallback)
    var envelope: [String: Any] = [
        "schema_version": 1,
        "event": event,
        "session_id": parsed["session_id"] ?? NSNull(),
        "transcript_path": parsed["transcript_path"] ?? NSNull(),
        "cwd": cwd ?? NSNull(),
        "iterm_session_id": nonEmpty(environment["ITERM_SESSION_ID"]) ?? NSNull(),
        "term_program": nonEmpty(environment["TERM_PROGRAM"]) ?? NSNull(),
        "tty": ttyPath() ?? NSNull(),
        "ppid": ppid > 0 ? Int(ppid) : NSNull(),
        "claude_project_dir": nonEmpty(environment["CLAUDE_PROJECT_DIR"]) ?? NSNull(),
        "ts": utcTimestamp(fractional: true),
    ]

    let toolUse = parsed["tool_use"] as? [String: Any] ?? [:]
    let topLevelExitCode = parsed["exit_code"].flatMap { $0 is NSNull ? nil : $0 }
    let exitCode = topLevelExitCode ?? toolUse["exit_code"]
    if isInteger(exitCode), let exitCode { envelope["exit_code"] = exitCode }

    if let startedAt = epoch(parsed["started_at"]) ?? epoch(parsed["prompt_started_at"]) {
        envelope["started_at"] = startedAt
    }

    var kind = parsed["kind"] as? String
    if kind == nil && event == "notification" { kind = "waiting" }
    if let kind { envelope["kind"] = kind }

    var lastOutput: Any?
    switch event {
    case "stop":
        if let path = nonEmpty(parsed["transcript_path"] as? String) {
            lastOutput = waitTranscriptLastOutput(path)
        }
        if !(lastOutput is String) { lastOutput = parsed["last_output"] }
    case "notification":
        lastOutput = parsed["message"]
        if !(lastOutput is String) { lastOutput = parsed["last_output"] }
    default:
        lastOutput = parsed["last_output"]
    }
    if let capped = capUTF8(lastOutput) { envelope["last_output"] = capped }

    return isCodexMemoryEvent(envelope) ? nil : envelope
}

// MARK: - Log + forward

func parentDescription(_ pid: pid_t) -> String {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return "" }
    var pathBuffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let command: String
    if proc_pidpath(pid, &pathBuffer, UInt32(pathBuffer.count)) > 0 {
        command = String(cString: pathBuffer)
    } else {
        command = withUnsafeBytes(of: info.pbi_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    }
    return "\(pid) \(info.pbi_ppid) \(command)"
}

func appendLog(envelopeJSON: String?, ppid: pid_t, cwd: String) {
    let fileManager = FileManager.default
    try? fileManager.createDirectory(atPath: logDir, withIntermediateDirectories: true)
    if let size = (try? fileManager.attributesOfItem(atPath: logPath))?[.size] as? Int, size > logMaxBytes {
        _ = rename(logPath, logPath + ".1")
    }
    let line = "{\"ts\":\(jsonText(utcTimestamp(fractional: false)) ?? "null")"
        + ",\"entry\":\"hook_fire\""
        + ",\"envelope\":\(envelopeJSON ?? "null")"
        + ",\"ppid_chain\":\(jsonText(parentDescription(ppid)) ?? "\"\"")"
        + ",\"cwd\":\(jsonText(cwd) ?? "\"\"")"
        + (transcriptWait.map { ",\"transcript_attempts\":\($0.attempts),\"transcript_found\":\($0.found)" } ?? "")
        + "}\n"
    let fd = open(logPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
    guard fd >= 0 else { return }
    defer { close(fd) }
    _ = line.withCString { write(fd, $0, strlen($0)) }
}

func forward(_ line: String) {
    var status = stat()
    guard stat(socketPath, &status) == 0, (status.st_mode & S_IFMT) == S_IFSOCK else { return }
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { return }
    defer { close(fd) }

    var yes: Int32 = 1
    setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
    var timeout = timeval(tv_sec: 1, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = Array(socketPath.utf8)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count < capacity else { return }   // Pitfall #6 — 104-byte sun_path
    withUnsafeMutableBytes(of: &address.sun_path) { buffer in
        buffer.copyBytes(from: pathBytes)
    }
    let connected = withUnsafePointer(to: &address) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else { return }

    let bytes = Array((line + "\n").utf8)
    var offset = 0
    while offset < bytes.count {
        let sent = bytes[offset...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        guard sent > 0 else { return }
        offset += sent
    }

    // Half-close and wait for the App to hang up (like `nc -w 1`): an abrupt close() lands
    // as a receive error in HookListener, which then drops the buffered envelope.
    shutdown(fd, SHUT_WR)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    var scratch = [UInt8](repeating: 0, count: 256)
    while read(fd, &scratch, scratch.count) > 0 {}
}

// MARK: - Main

let ppid = getppid()
let cwdFallback = FileManager.default.currentDirectoryPath
let stdinData = FileHandle.standardInput.readDataToEndOfFile()
let stdinText = String(decoding: stdinData, as: UTF8.self)

let envelopeJSON = buildEnvelope(stdin: stdinText, cwdFallback: cwdFallback, ppid: ppid).flatMap(jsonText)

// Debug log FIRST (HOOK-06): record envelope + ppid chain BEFORE network.
appendLog(envelopeJSON: envelopeJSON, ppid: ppid, cwd: cwdFallback)

// Forward to App (HOOK-01). Silently no-op if socket missing (HOOK-05).
if let envelopeJSON { forward(envelopeJSON) }

exit(0)
