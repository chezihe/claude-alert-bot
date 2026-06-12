// App/HookInstaller.swift — installs the bundled cab-report.sh and the Claude/Codex hook
// entries that invoke it. Extracted from AppDelegate.swift (lifecycle file): everything in
// here is pure file/JSON/TOML manipulation with no AppKit dependency.
// Tested by ReporterScriptTests (install idempotency, comment/CRLF tolerance, codex paths).
import Foundation
import os

enum HookInstaller {
    private static let log = Logger(subsystem: "com.claudealert.bot.hook", category: "lifecycle")
    private static let cabMarker = "ClaudeAlertBot/cab-report.sh"
    private static let reporterRelativePath = "Library/Application Support/ClaudeAlertBot/cab-report.sh"
    private static let codexDirRelativePath = ".codex"
    private static let codexHooksRelativePath = ".codex/hooks.json"
    private static let codexConfigRelativePath = ".codex/config.toml"

    static func installBundledReporterIfNeeded(bundle: Bundle = .main,
                                                homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        guard let reporter = bundle.url(forResource: "cab-report", withExtension: "sh") else {
            log.error("bundled cab-report.sh missing; hook install skipped")
            return
        }
        do {
            try install(reporterSourceURL: reporter, homeDirectory: homeDirectory)
            log.notice("Claude Alert Bot hooks installed")
        } catch {
            log.error("Claude Alert Bot hook install failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func install(reporterSourceURL: URL,
                        homeDirectory: URL,
                        fileManager: FileManager = .default) throws {
        let reporterDest = homeDirectory.appendingPathComponent(reporterRelativePath)
        let appSupportDir = reporterDest.deletingLastPathComponent()
        try fileManager.createDirectory(at: appSupportDir,
                                        withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        if fileManager.fileExists(atPath: reporterDest.path) {
            try fileManager.removeItem(at: reporterDest)
        }
        try fileManager.copyItem(at: reporterSourceURL, to: reporterDest)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: reporterDest.path)

        let claudeDir = homeDirectory.appendingPathComponent(".claude")
        try fileManager.createDirectory(at: claudeDir,
                                        withIntermediateDirectories: true,
                                        attributes: [.posixPermissions: 0o700])
        let settingsURL = claudeDir.appendingPathComponent("settings.json")
        var settings = try loadSettings(at: settingsURL, fileManager: fileManager)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        hooks["Stop"] = mergedEntries(existing: hooks["Stop"], event: "stop")
        hooks["UserPromptSubmit"] = mergedEntries(existing: hooks["UserPromptSubmit"], event: "user_prompt_submit")
        hooks["Notification"] = mergedEntries(existing: hooks["Notification"],
                                              event: "notification",
                                              matcher: "permission_prompt|elicitation_dialog")
        settings["hooks"] = hooks

        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        // Skip the write when the merged result is byte-identical — otherwise every launch
        // churns the file (and re-serializing permanently strips comments from JSONC settings).
        if (try? Data(contentsOf: settingsURL)) != data {
            try data.write(to: settingsURL, options: [.atomic])
        }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: settingsURL.path)

        do {
            try installCodexHooksIfNeeded(homeDirectory: homeDirectory, fileManager: fileManager)
        } catch {
            log.warning("Codex hook install skipped: \(String(describing: error), privacy: .public)")
        }
    }

    private static func installCodexHooksIfNeeded(homeDirectory: URL,
                                                  fileManager: FileManager) throws {
        let codexDir = homeDirectory.appendingPathComponent(codexDirRelativePath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: codexDir.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return }

        let hooksURL = homeDirectory.appendingPathComponent(codexHooksRelativePath)
        let configURL = homeDirectory.appendingPathComponent(codexConfigRelativePath)
        let existingConfig = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""

        if !fileManager.fileExists(atPath: hooksURL.path),
           codexConfigHasInlineHooks(existingConfig) {
            let updatedConfig = codexConfigEnablingHooks(existingConfig, appendInlineHooks: true)
            guard updatedConfig != existingConfig else { return }
            try updatedConfig.write(to: configURL, atomically: true, encoding: .utf8)
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
            return
        }

        var settings = try loadSettings(at: hooksURL, fileManager: fileManager)
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        hooks["Stop"] = mergedEntries(existing: hooks["Stop"], event: "stop")
        hooks["UserPromptSubmit"] = mergedEntries(existing: hooks["UserPromptSubmit"], event: "user_prompt_submit")
        settings["hooks"] = hooks

        let hooksData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        if (try? Data(contentsOf: hooksURL)) != hooksData {
            try hooksData.write(to: hooksURL, options: [.atomic])
        }
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: hooksURL.path)

        let updatedConfig = codexConfigEnablingHooks(existingConfig)
        guard updatedConfig != existingConfig else { return }
        try updatedConfig.write(to: configURL, atomically: true, encoding: .utf8)
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    private static func loadSettings(at url: URL, fileManager: FileManager) throws -> [String: Any] {
        guard fileManager.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [:] }
        if let settings = try? parseSettingsData(data) {
            return settings
        }
        guard let raw = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let cleaned = try stripJSONComments(from: raw)
        guard !cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        return try parseSettingsData(Data(cleaned.utf8))
    }

    private static func parseSettingsData(_ data: Data) throws -> [String: Any] {
        guard let settings = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return settings
    }

    private static func stripJSONComments(from text: String) throws -> String {
        let characters = Array(text)
        var cleaned = ""
        var index = 0
        var inString = false
        var isEscaping = false

        func append(_ character: Character) {
            cleaned.append(character)
        }

        while index < characters.count {
            let character = characters[index]
            let next = index + 1 < characters.count ? characters[index + 1] : nil

            if inString {
                append(character)
                if isEscaping {
                    isEscaping = false
                } else if character == "\\" {
                    isEscaping = true
                } else if character == "\"" {
                    inString = false
                }
                index += 1
                continue
            }

            if character == "\"" {
                inString = true
                append(character)
                index += 1
            } else if character == "/" && next == "/" {
                index += 2
                while index < characters.count,
                      characters[index] != "\n",
                      characters[index] != "\r" {
                    index += 1
                }
            } else if character == "/" && next == "*" {
                index += 2
                var foundTerminator = false
                while index < characters.count {
                    if characters[index] == "*" &&
                        index + 1 < characters.count &&
                        characters[index + 1] == "/" {
                        index += 2
                        foundTerminator = true
                        break
                    }
                    index += 1
                }
                guard foundTerminator else { throw CocoaError(.propertyListReadCorrupt) }
                append(" ")
            } else {
                append(character)
                index += 1
            }
        }

        return cleaned
    }

    private static func mergedEntries(existing: Any?, event: String, matcher: String = "") -> [[String: Any]] {
        let existingEntries = existing as? [[String: Any]] ?? []
        let preserved = existingEntries.compactMap(removingCabCommands)
        return preserved + [entry(event: event, matcher: matcher)]
    }

    private static func removingCabCommands(from entry: [String: Any]) -> [String: Any]? {
        guard let hooks = entry["hooks"] as? [[String: Any]] else { return entry }
        let filteredHooks = hooks.filter { !isCabCommand($0) }
        guard filteredHooks.count != hooks.count else { return entry }
        guard !filteredHooks.isEmpty else { return nil }
        var filteredEntry = entry
        filteredEntry["hooks"] = filteredHooks
        return filteredEntry
    }

    private static func isCabCommand(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String)?.contains(cabMarker) == true
    }

    private static func entry(event: String, matcher: String) -> [String: Any] {
        [
            "matcher": matcher,
            "hooks": [[
                "type": "command",
                "command": "\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" \(event)",
                "timeout": 5
            ]]
        ]
    }

    private static func codexConfigEnablingHooks(_ text: String,
                                                 appendInlineHooks: Bool = false) -> String {
        var lines = normalizedConfigLines(text)
        lines = removingCabInlineHooks(from: lines, event: "Stop")
        lines = removingCabInlineHooks(from: lines, event: "UserPromptSubmit")

        var inFeatures = false
        var featuresIndex: Int?
        var didSetCodexHooks = false

        for index in lines.indices {
            let trimmed = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if let header = tomlHeaderName(in: lines[index]) {
                inFeatures = header == "features"
                if inFeatures { featuresIndex = index }
                continue
            }
            let key = trimmed.split(separator: "=", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespaces)
            guard inFeatures, key == "codex_hooks" else { continue }
            let indent = lines[index].prefix { $0 == " " || $0 == "\t" }
            lines[index] = "\(indent)codex_hooks = true"
            didSetCodexHooks = true
            break
        }

        if !didSetCodexHooks {
            if let featuresIndex {
                lines.insert("codex_hooks = true", at: featuresIndex + 1)
            } else {
                if !lines.isEmpty && lines.last != "" {
                    lines.append("")
                }
                lines.append("[features]")
                lines.append("codex_hooks = true")
            }
        }

        if appendInlineHooks {
            appendCodexInlineHookEntries(to: &lines)
        }

        return didSetCodexHooks && !appendInlineHooks
            ? joinedConfigLines(lines, preservingTrailingNewlineFrom: text)
            : ensuringTrailingNewline(lines.joined(separator: "\n"))
    }

    private static func codexConfigHasInlineHooks(_ text: String) -> Bool {
        normalizedConfigLines(text).contains { line in
            guard let header = tomlHeaderName(in: line) else { return false }
            return header == "hooks" || header.hasPrefix("hooks.")
        }
    }

    private static func appendCodexInlineHookEntries(to lines: inout [String]) {
        if !lines.isEmpty && lines.last != "" {
            lines.append("")
        }
        lines.append(contentsOf: [
            "[[hooks.Stop]]",
            #"matcher = """#,
            "[[hooks.Stop.hooks]]",
            #"type = "command""#,
            #"command = '"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh" stop'"#,
            "timeout = 5",
            "",
            "[[hooks.UserPromptSubmit]]",
            #"matcher = """#,
            "[[hooks.UserPromptSubmit.hooks]]",
            #"type = "command""#,
            #"command = '"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh" user_prompt_submit'"#,
            "timeout = 5"
        ])
    }

    private static func normalizedConfigLines(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private static func removingCabInlineHooks(from lines: [String], event: String) -> [String] {
        let commandHeader = "hooks.\(event).hooks"
        let withoutCabCommands = removingCabInlineHookCommands(from: lines, commandHeader: commandHeader)
        return removingEmptyInlineHookEntries(from: withoutCabCommands, event: event)
    }

    private static func removingCabInlineHookCommands(from lines: [String],
                                                      commandHeader: String) -> [String] {
        var result: [String] = []
        var index = 0

        while index < lines.count {
            if tomlHeaderName(in: lines[index]) == commandHeader {
                let end = nextTomlHeaderIndex(in: lines, after: index)
                let block = Array(lines[index..<end])
                if blockContainsCabCommand(block) {
                    index = end
                    continue
                }
            }

            result.append(lines[index])
            index += 1
        }

        return result
    }

    private static func removingEmptyInlineHookEntries(from lines: [String], event: String) -> [String] {
        let entryHeader = "hooks.\(event)"
        let commandHeader = "hooks.\(event).hooks"
        var result: [String] = []
        var index = 0

        while index < lines.count {
            guard tomlHeaderName(in: lines[index]) == entryHeader else {
                result.append(lines[index])
                index += 1
                continue
            }

            let end = inlineHookEntryEndIndex(in: lines,
                                              after: index,
                                              commandHeader: commandHeader)
            let block = Array(lines[index..<end])
            if block.dropFirst().contains(where: { tomlHeaderName(in: $0) == commandHeader }) {
                result.append(contentsOf: block)
            }
            index = end
        }

        return result
    }

    private static func inlineHookEntryEndIndex(in lines: [String],
                                                after index: Int,
                                                commandHeader: String) -> Int {
        var end = index + 1
        while end < lines.count {
            guard let header = tomlHeaderName(in: lines[end]) else {
                end += 1
                continue
            }
            if header == commandHeader {
                end += 1
                continue
            }
            break
        }
        return end
    }

    private static func nextTomlHeaderIndex(in lines: [String], after index: Int) -> Int {
        var next = index + 1
        while next < lines.count {
            if tomlHeaderName(in: lines[next]) != nil {
                return next
            }
            next += 1
        }
        return lines.count
    }

    private static func tomlHeaderName(in line: String) -> String? {
        let withoutComment = line.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let trimmed = withoutComment.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[[") && trimmed.hasSuffix("]]") {
            return trimmed
                .dropFirst(2)
                .dropLast(2)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            return trimmed
                .dropFirst()
                .dropLast()
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func blockContainsCabCommand(_ lines: [String]) -> Bool {
        lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.split(separator: "=", maxSplits: 1).first?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return key == "command" && line.contains(cabMarker)
        }
    }

    private static func joinedConfigLines(_ lines: [String],
                                          preservingTrailingNewlineFrom original: String) -> String {
        var result = lines.joined(separator: "\n")
        if original.hasSuffix("\n") && !result.hasSuffix("\n") {
            result += "\n"
        }
        return result
    }

    private static func ensuringTrailingNewline(_ text: String) -> String {
        text.hasSuffix("\n") ? text : text + "\n"
    }
}
