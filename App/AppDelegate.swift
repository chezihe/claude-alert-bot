// App/AppDelegate.swift — Phase 1 application lifecycle.
// Steps in applicationDidFinishLaunching match RESEARCH "System Architecture Diagram → App lifecycle":
//   1. validate sun_path length (Pitfall #6)
//   2. ensure ~/Library/Application Support/ClaudeAlertBot/ + ~/Library/Logs/ClaudeAlertBot/ exist (Pitfall #7)
//   3. reclaim stale socket (Pattern 6 — probe-connect; only remove if no live listener)
//   4. start NWListener (D-09: bind exclusivity = single-instance lock; .failed → terminate)
//   5. install SIGTERM/SIGINT handlers for clean shutdown (must retain DispatchSource refs)
import AppKit
import Foundation
import Network
import Combine
import ServiceManagement
import os

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "lifecycle")
    private var listener: HookListener?
    private var signalSources: [DispatchSourceSignal] = []

    // Phase 2 — retained components (Wave 6 wiring per Pitfall #11)
    private var notificationOrchestrator: NotificationOrchestrator?
    private var widgetController: FloatingWidgetWindowController?
    private var popoverController: WidgetPopoverController?
    private var wakeObserver: WakeObserver?
    private var frontmostObserver: WorkspaceFrontmostObserver?
    private var gcTimer: SessionGCTimer?
    private var themeCancellable: AnyCancellable?

    // D2-29: previously set in main.swift; relocated here so it lands BEFORE SwiftUI
    // realizes any scene. willFinishLaunching is the canonical Apple-blessed slot for
    // this when using SwiftUI App lifecycle. Belt-and-suspenders alongside LSUIElement=true.
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        MainActor.assumeIsolated {
            installThemeObservation()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningUnitTests else {
            log.notice("unit tests detected; skipping app runtime wiring")
            return
        }

        // === Phase 1 steps (preserved verbatim) ===
        // 1. Validate socket path length (Pitfall #6)
        guard SocketPaths.validateSocketPathLength() else {
            log.error("socket path > 103 bytes — refusing to bind")
            NSApp.terminate(nil)
            return
        }

        // 2. Ensure directories exist with mode 0700 (Pitfall #7 + T-IPC-01 mitigation)
        ensureDirectories()

        // 3. Stale-socket reclaim (Pattern 6)
        reclaimSocketIfStale(at: SocketPaths.socketPath)

        // === Phase 2 wiring (Wave 6 — Pitfall #11 ordering) ===
        // listener.start() (Phase 1 step 4) is DEFERRED into this Task so it runs
        // strictly AFTER SessionRegistry.restore() completes — otherwise in-flight
        // events arriving in the boot window can be dropped.
        Task { @MainActor in
            // Re-apply only the opt-in path on launch. The off path is handled
            // immediately when the user turns the Settings toggle off.
            if SettingsStore.shared.launchAtLoginEnabled {
                LoginItemController.apply(enabled: true)
            }
            HookInstaller.installBundledReporterIfNeeded()

            // 6. Restore session state from disk BEFORE listener accepts events.
            await SessionRegistry.shared.restore()

            // 7. Construct widget + popover + notification orchestrator.
            let widget = FloatingWidgetWindowController()
            let popover = WidgetPopoverController(widgetController: widget, jumper: ITerm2Jumper())
            widget.hoverDelegate = popover
            let orchestrator = NotificationOrchestrator(widget: widget)
            self.widgetController = widget
            self.popoverController = popover
            self.notificationOrchestrator = orchestrator

            // 8. Bind orchestrator to registry — registry can now broadcast UI updates.
            await SessionRegistry.shared.bind(notifier: orchestrator)

            // 9. Restore-broadcast — registry already replayed any restored queue,
            //    but the orchestrator was nil at that time. Re-emit current state.
            let pending = await SessionRegistry.shared.peekPending()
            await orchestrator.refreshQueueState(completed: pending, count: pending.count)

            // 10. Lifecycle observers + GC timer (SESS-04 Pattern 6 triple-trigger).
            self.wakeObserver = WakeObserver { Task { await SessionRegistry.shared.runGC() } }
            self.frontmostObserver = WorkspaceFrontmostObserver()
            let timer = SessionGCTimer { Task { await SessionRegistry.shared.runGC() } }
            timer.start()
            self.gcTimer = timer

            // 11. AppleScriptHelper eager compile — keeps first cheap-query latency low.
            //     No permission trigger here: D2-35 Path A lives in SettingsView.onAppear,
            //     Path B lives in HookListener.handle on the first Stop with .unknown perm.
            _ = AppleScriptHelper.shared

            self.log.notice("Phase 2 components wired (orchestrator, widget, popover, observers, GC timer)")

            // === Phase 1 step 4 (DEFERRED to here per Pitfall #11) ===
            // 4. Start listener AFTER all Phase 2 wiring completes.
            do {
                let l = HookListener(socketPath: SocketPaths.socketPath)
                try l.start()
                self.listener = l
                self.log.notice("listener bound (Phase 2 wiring complete)")
            } catch {
                self.log.error("listener.start failed: \(String(describing: error), privacy: .public)")
                NSApp.terminate(nil)
            }
        }

        // === Phase 1 step 5 (preserved — outside Task; signal handlers don't depend on Phase 2 wiring) ===
        installSignalHandler(SIGTERM)
        installSignalHandler(SIGINT)
        // NOTE: D2-29 — no NSMenu / settingsWindow / NSApp.activate. Settings are
        // now exposed from `MenuBarExtra` directly.
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    private func ensureDirectories() {
        let fm = FileManager.default
        for dir in [SocketPaths.appSupportDir, SocketPaths.logsDir] {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
            // Re-apply 0700 in case the directory pre-existed with different perms.
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir)
        }
    }

    private func reclaimSocketIfStale(at path: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return }

        let probe = NWConnection(to: .unix(path: path), using: NWParameters.tcp)
        let group = DispatchGroup()
        group.enter()
        var alive = false
        // NWConnection states are not single-shot — `.failed`/`.cancelled`/`.waiting`
        // can fire repeatedly (e.g. after our own probe.cancel()). Multiple group.leave()
        // calls crash libdispatch ("Unbalanced call to dispatch_group_leave()"), which
        // surfaced as test-runner crashes when the TEST_HOST app boots.
        var leftOnce = false
        probe.stateUpdateHandler = { state in
            guard !leftOnce else { return }
            switch state {
            case .ready:
                alive = true
                leftOnce = true
                group.leave()
            case .failed, .cancelled, .waiting:
                leftOnce = true
                group.leave()
            default: break
            }
        }
        probe.start(queue: DispatchQueue.global())
        _ = group.wait(timeout: .now() + .milliseconds(200))
        probe.cancel()

        if !alive {
            try? fm.removeItem(atPath: path)
            log.info("removed stale socket at \(path, privacy: .public)")
        }
        // If alive, leave the file — listener.start() will report .failed and we exit cleanly.
    }

    private func installSignalHandler(_ sig: Int32) {
        signal(sig, SIG_IGN)
        let src = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        src.setEventHandler { [weak self] in
            self?.log.info("received signal \(sig) — shutting down")
            self?.listener?.cancel()
            NSApp.terminate(nil)
        }
        src.resume()
        // CRITICAL: retain the source — otherwise it's deallocated and signals are silently ignored.
        signalSources.append(src)
    }

    @MainActor
    private func installThemeObservation() {
        applyThemeMode(SettingsStore.shared.themeMode)
        themeCancellable = SettingsStore.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.applyThemeMode(SettingsStore.shared.themeMode)
            }
        }
    }

    @MainActor
    private func applyThemeMode(_ mode: ThemeMode) {
        NSApp.appearance = mode.nsAppearance
    }
}

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
        try data.write(to: settingsURL, options: [.atomic])
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
        try hooksData.write(to: hooksURL, options: [.atomic])
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

@MainActor
enum LoginItemController {
    private static let log = Logger(subsystem: "com.claudealert.bot.hook", category: "lifecycle")

    static func applyFromSettings(enabled: Bool) {
        apply(enabled: enabled, openSettingsWhenApprovalRequired: true)
    }

    static func apply(enabled: Bool) {
        apply(enabled: enabled, openSettingsWhenApprovalRequired: false)
    }

    private static func apply(enabled: Bool, openSettingsWhenApprovalRequired: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                switch service.status {
                case .enabled:
                    return
                case .notRegistered, .notFound:
                    try service.register()
                case .requiresApproval:
                    if openSettingsWhenApprovalRequired {
                        SMAppService.openSystemSettingsLoginItems()
                        log.notice("login item requires user approval; opened Login Items settings")
                        return
                    }
                    try service.unregister()
                    SettingsStore.shared.launchAtLoginEnabled = false
                    log.notice("login item requires user approval; unregistered pending item and disabled stored preference")
                    return
                @unknown default:
                    try service.register()
                }
            } else {
                switch service.status {
                case .enabled, .requiresApproval:
                    try service.unregister()
                case .notRegistered, .notFound:
                    return
                @unknown default:
                    return
                }
            }
            log.notice("login item preference applied enabled=\(enabled, privacy: .public)")
        } catch {
            log.error("login item preference failed enabled=\(enabled, privacy: .public): \(String(describing: error), privacy: .public)")
        }
    }
}
