import XCTest
@testable import ClaudeAlertBot

final class ReporterScriptTests: XCTestCase {
    private var tempHome: URL!

    override func setUpWithError() throws {
        tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("cab-reporter-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempHome, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempHome {
            try? FileManager.default.removeItem(at: tempHome)
        }
        tempHome = nil
    }

    func test_reporterPassesThroughOptionalExtendedFields() throws {
        let envelope = try runReporter(stdin: """
        {
          "session_id": "sid-reporter",
          "cwd": "/tmp/project",
          "exit_code": 2,
          "started_at": 1730000000.5,
          "kind": "waiting",
          "last_output": "tail output"
        }
        """)

        XCTAssertEqual(envelope["exit_code"] as? Int, 2)
        XCTAssertEqual(envelope["started_at"] as? Double, 1_730_000_000.5)
        XCTAssertEqual(envelope["kind"] as? String, "waiting")
        XCTAssertEqual(envelope["last_output"] as? String, "tail output")
    }

    func test_reporterOmitsMissingOptionalExtendedFields() throws {
        let envelope = try runReporter(stdin: #"{"session_id":"sid-reporter","cwd":"/tmp/project"}"#)

        XCTAssertNil(envelope["exit_code"])
        XCTAssertNil(envelope["started_at"])
        XCTAssertNil(envelope["kind"])
        XCTAssertNil(envelope["last_output"])
    }

    func test_reporterMapsNotificationToWaitingKind() throws {
        let envelope = try runReporter(event: "notification", stdin: """
        {
          "session_id": "sid-reporter",
          "cwd": "/tmp/project",
          "message": "Claude needs your permission to use Bash",
          "notification_type": "permission_prompt"
        }
        """)

        XCTAssertEqual(envelope["event"] as? String, "notification")
        XCTAssertEqual(envelope["kind"] as? String, "waiting")
        XCTAssertEqual(envelope["last_output"] as? String, "Claude needs your permission to use Bash")
    }

    func test_reporterCapsLastOutputTo4KB() throws {
        let output = String(repeating: "x", count: 5_000)
        let payloadData = try JSONSerialization.data(withJSONObject: [
            "session_id": "sid-reporter",
            "cwd": "/tmp/project",
            "last_output": output
        ], options: [])
        let envelope = try runReporter(stdin: String(data: payloadData, encoding: .utf8)!)

        XCTAssertEqual((envelope["last_output"] as? String)?.utf8.count, 4_096)
    }

    func test_hookInstallerCopiesReporterAndCreatesClaudeHooks() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)

        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)

        let installedReporter = tempHome
            .appendingPathComponent("Library/Application Support/ClaudeAlertBot/cab-report.sh")
        XCTAssertTrue(FileManager.default.fileExists(atPath: installedReporter.path))
        let installedMode = try FileManager.default.attributesOfItem(atPath: installedReporter.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(installedMode?.intValue, 0o700)

        let hooks = try loadInstalledHooks()
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop"), [
            "\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" stop"
        ])
        XCTAssertEqual(cabCommands(in: hooks, event: "UserPromptSubmit"), [
            "\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" user_prompt_submit"
        ])
        XCTAssertEqual(cabCommands(in: hooks, event: "Notification"), [
            "\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" notification"
        ])
        XCTAssertEqual(matchers(in: hooks, event: "Notification"), [
            "permission_prompt|elicitation_dialog"
        ])
    }

    func test_hookInstallerCreatesCodexHooksWhenCodexConfigExists() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)
        let codexDir = tempHome.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try """
        model = "gpt-5.5"
        """.write(to: codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)

        let hooks = try loadInstalledCodexHooks()
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop"), [
            "\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" stop"
        ])
        XCTAssertEqual(cabCommands(in: hooks, event: "UserPromptSubmit"), [
            "\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" user_prompt_submit"
        ])

        let config = try String(contentsOf: codexDir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(config.contains("[features]"))
        XCTAssertTrue(config.contains("codex_hooks = true"))
    }

    func test_hookInstallerIsIdempotentAndPreservesOtherCodexHooks() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)
        let codexDir = tempHome.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  { "type": "command", "command": "echo keep", "timeout": 1 },
                  { "type": "command", "command": "old/ClaudeAlertBot/cab-report.sh stop", "timeout": 5 }
                ]
              }
            ]
          }
        }
        """.write(to: codexDir.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        try """
        model = "gpt-5.5"

        [features]
        codex_hooks = false
        other_feature = true
        """.write(to: codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)
        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)

        let hooks = try loadInstalledCodexHooks()
        XCTAssertEqual(otherCommands(in: hooks, event: "Stop"), ["echo keep"])
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop").count, 1)
        XCTAssertEqual(cabCommands(in: hooks, event: "UserPromptSubmit").count, 1)

        let config = try String(contentsOf: codexDir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(config.contains("codex_hooks = true"))
        XCTAssertFalse(config.contains("codex_hooks = false"))
        XCTAssertTrue(config.contains("other_feature = true"))
    }

    func test_hookInstallerRemovesExistingCodexInlineCabHooks() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)
        let codexDir = tempHome.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try """
        [features]
        codex_hooks = true

        [[hooks.Stop]]
        [[hooks.Stop.hooks]]
        type = "command"
        command = "old/ClaudeAlertBot/cab-report.sh stop"
        timeout = 5

        [[hooks.Stop]]
        [[hooks.Stop.hooks]]
        type = "command"
        command = "echo keep"
        timeout = 1

        [[hooks.UserPromptSubmit]]
        [[hooks.UserPromptSubmit.hooks]]
        type = "command"
        command = "old/ClaudeAlertBot/cab-report.sh user_prompt_submit"
        timeout = 5
        """.write(to: codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)
        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)

        XCTAssertFalse(FileManager.default.fileExists(atPath: codexDir.appendingPathComponent("hooks.json").path))

        let config = try String(contentsOf: codexDir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertEqual(config.components(separatedBy: "ClaudeAlertBot/cab-report.sh").count - 1, 2)
        XCTAssertEqual(config.components(separatedBy: "\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" stop").count - 1, 1)
        XCTAssertEqual(config.components(separatedBy: "\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" user_prompt_submit").count - 1, 1)
        XCTAssertFalse(config.contains("old/ClaudeAlertBot/cab-report.sh"))
        XCTAssertTrue(config.contains(#"command = "echo keep""#))
    }

    func test_hookInstallerUpdatesCodexFeatureInCRLFConfig() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)
        let codexDir = tempHome.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let crlfConfig = "model = \"gpt-5.5\"\r\n\r\n[features]\r\ncodex_hooks = false\r\nother_feature = true\r\n"
        try crlfConfig.write(to: codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)

        let config = try String(contentsOf: codexDir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertEqual(config.components(separatedBy: "[features]").count - 1, 1)
        XCTAssertTrue(config.contains("codex_hooks = true"))
        XCTAssertFalse(config.contains("codex_hooks = false"))
        XCTAssertTrue(config.contains("other_feature = true"))
    }

    func test_hookInstallerDoesNotFailClaudeInstallWhenCodexHooksAreInvalid() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)
        let codexDir = tempHome.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try "{broken".write(to: codexDir.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)

        XCTAssertNoThrow(try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome))

        let hooks = try loadInstalledHooks()
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop").count, 1)
        XCTAssertEqual(cabCommands(in: hooks, event: "UserPromptSubmit").count, 1)
    }

    func test_devInstallHookApplyCreatesCodexHooksWhenCodexConfigExists() throws {
        let codexDir = tempHome.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try """
        model = "gpt-5.5"
        """.write(to: codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        try runDevInstallHook("--apply")

        let hooks = try loadInstalledCodexHooks()
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop"), [
            "\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" stop"
        ])
        XCTAssertEqual(cabCommands(in: hooks, event: "UserPromptSubmit"), [
            "\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" user_prompt_submit"
        ])

        let config = try String(contentsOf: codexDir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(config.contains("[features]"))
        XCTAssertTrue(config.contains("codex_hooks = true"))
    }

    func test_devInstallHookApplyCreatesClaudeNotificationHook() throws {
        try runDevInstallHook("--apply")

        let hooks = try loadInstalledHooks()
        XCTAssertEqual(cabCommands(in: hooks, event: "Notification"), [
            "\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" notification"
        ])
        XCTAssertEqual(matchers(in: hooks, event: "Notification"), [
            "permission_prompt|elicitation_dialog"
        ])
    }

    func test_devInstallHookApplyIsIdempotentAndPreservesOtherCodexHooks() throws {
        let codexDir = tempHome.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  { "type": "command", "command": "echo keep", "timeout": 1 },
                  { "type": "command", "command": "old/ClaudeAlertBot/cab-report.sh stop", "timeout": 5 }
                ]
              }
            ]
          }
        }
        """.write(to: codexDir.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)
        try """
        [features]
        codex_hooks = false
        other_feature = true
        """.write(to: codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        try runDevInstallHook("--apply")
        try runDevInstallHook("--apply")

        let hooks = try loadInstalledCodexHooks()
        XCTAssertEqual(otherCommands(in: hooks, event: "Stop"), ["echo keep"])
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop").count, 1)
        XCTAssertEqual(cabCommands(in: hooks, event: "UserPromptSubmit").count, 1)

        let config = try String(contentsOf: codexDir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertTrue(config.contains("codex_hooks = true"))
        XCTAssertFalse(config.contains("codex_hooks = false"))
        XCTAssertTrue(config.contains("other_feature = true"))
    }

    func test_devInstallHookApplyPreservesCodexCommandsContainingCommentMarkers() throws {
        let codexDir = tempHome.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  { "type": "command", "command": "echo /* keep me */", "timeout": 1 },
                  { "type": "command", "command": "echo // keep me", "timeout": 1 }
                ]
              }
            ]
          }
        }
        """.write(to: codexDir.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)

        try runDevInstallHook("--apply")

        let hooks = try loadInstalledCodexHooks()
        let commands = otherCommands(in: hooks, event: "Stop")
        XCTAssertTrue(commands.contains("echo /* keep me */"))
        XCTAssertTrue(commands.contains("echo // keep me"))
    }

    func test_devInstallHookApplyRejectsCodexBlockCommentBetweenNumberTokensWithoutRewritingHooks() throws {
        let codexDir = tempHome.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        let hooksURL = codexDir.appendingPathComponent("hooks.json")
        let original = """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  { "type": "command", "command": "echo keep", "timeout": 1/*x*/2 }
                ]
              }
            ]
          }
        }
        """
        try original.write(to: hooksURL, atomically: true, encoding: .utf8)

        let output = try runDevInstallHook("--apply")

        let rewritten = try String(contentsOf: hooksURL, encoding: .utf8)
        XCTAssertEqual(rewritten, original)
        XCTAssertTrue(output.contains("warning: could not parse"))
    }

    func test_devInstallHookApplyIgnoresInvalidCodexHooksAfterClaudeInstall() throws {
        let codexDir = tempHome.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try "{broken".write(to: codexDir.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)

        let output = try runDevInstallHook("--apply")

        let hooks = try loadInstalledHooks()
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop").count, 1)
        XCTAssertEqual(cabCommands(in: hooks, event: "UserPromptSubmit").count, 1)
        XCTAssertTrue(output.contains("warning: could not parse"))
    }

    func test_devInstallHookCheckShowsCodexHooksWithoutClaudeSettings() throws {
        let codexDir = tempHome.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try """
        {
          "hooks": {
            "Stop": [
              {
                "hooks": [
                  { "type": "command", "command": "echo codex", "timeout": 1 }
                ]
              }
            ]
          }
        }
        """.write(to: codexDir.appendingPathComponent("hooks.json"), atomically: true, encoding: .utf8)

        let output = try runDevInstallHook("--check")

        XCTAssertTrue(output.contains("--- Codex hooks from"))
        XCTAssertTrue(output.contains("echo codex"))
    }

    func test_devInstallHookApplyIsIdempotentWithInlineCodexHooks() throws {
        let codexDir = tempHome.appendingPathComponent(".codex")
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        try """
        [features]
        codex_hooks = true

        [[hooks.Stop]]
        matcher = ""
        [[hooks.Stop.hooks]]
        type = "command"
        command = "echo keep"
        timeout = 1
        [[hooks.Stop.hooks]]
        type = "command"
        command = "old/ClaudeAlertBot/cab-report.sh stop"
        timeout = 5
        """.write(to: codexDir.appendingPathComponent("config.toml"), atomically: true, encoding: .utf8)

        try runDevInstallHook("--apply")
        try runDevInstallHook("--apply")

        XCTAssertFalse(FileManager.default.fileExists(atPath: codexDir.appendingPathComponent("hooks.json").path))
        let config = try String(contentsOf: codexDir.appendingPathComponent("config.toml"), encoding: .utf8)
        XCTAssertEqual(config.components(separatedBy: "\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" stop").count - 1, 1)
        XCTAssertEqual(config.components(separatedBy: "\"$HOME/Library/Application Support/ClaudeAlertBot/cab-report.sh\" user_prompt_submit").count - 1, 1)
        XCTAssertFalse(config.contains("old/ClaudeAlertBot/cab-report.sh"))
        XCTAssertTrue(config.contains(#"command = "echo keep""#))
    }

    func test_hookInstallerIsIdempotentAndPreservesOtherHooks() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)
        let settings = tempHome.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "theme": "dark",
          "hooks": {
            "Stop": [
              {
                "matcher": "keep",
                "hooks": [
                  { "type": "command", "command": "echo keep", "timeout": 1 }
                ]
              },
              {
                "matcher": "",
                "hooks": [
                  { "type": "command", "command": "old/ClaudeAlertBot/cab-report.sh stop", "timeout": 5 }
                ]
              }
            ]
          }
        }
        """.write(to: settings, atomically: true, encoding: .utf8)

        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)
        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)

        let installed = try loadInstalledSettings()
        XCTAssertEqual(installed["theme"] as? String, "dark")
        let hooks = try XCTUnwrap(installed["hooks"] as? [String: Any])
        XCTAssertEqual(otherCommands(in: hooks, event: "Stop"), ["echo keep"])
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop").count, 1)
        XCTAssertEqual(cabCommands(in: hooks, event: "UserPromptSubmit").count, 1)
    }

    func test_hookInstallerPreservesOtherHooksInSameMatcherEntry() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)
        let settings = tempHome.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "hooks": {
            "Stop": [
              {
                "matcher": "",
                "hooks": [
                  { "type": "command", "command": "echo keep", "timeout": 1 },
                  { "type": "command", "command": "old/ClaudeAlertBot/cab-report.sh stop", "timeout": 5 }
                ]
              }
            ]
          }
        }
        """.write(to: settings, atomically: true, encoding: .utf8)

        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)

        let hooks = try loadInstalledHooks()
        XCTAssertEqual(otherCommands(in: hooks, event: "Stop"), ["echo keep"])
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop").count, 1)
    }

    func test_hookInstallerAcceptsCommentedClaudeSettings() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)
        let settings = tempHome.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          // User note that dev-install-hook.sh already tolerates.
          "theme": "dark",
          /*
             Existing block comment.
          */
          "hooks": {}
        }
        """.write(to: settings, atomically: true, encoding: .utf8)

        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)

        let installed = try loadInstalledSettings()
        XCTAssertEqual(installed["theme"] as? String, "dark")
        let hooks = try XCTUnwrap(installed["hooks"] as? [String: Any])
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop").count, 1)
        XCTAssertEqual(cabCommands(in: hooks, event: "UserPromptSubmit").count, 1)
    }

    func test_hookInstallerAcceptsInlineLineComments() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)
        let settings = tempHome.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "theme": "dark", // User note after a normal JSON value.
          "hooks": {}
        }
        """.write(to: settings, atomically: true, encoding: .utf8)

        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)

        let installed = try loadInstalledSettings()
        XCTAssertEqual(installed["theme"] as? String, "dark")
        let hooks = try XCTUnwrap(installed["hooks"] as? [String: Any])
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop").count, 1)
        XCTAssertEqual(cabCommands(in: hooks, event: "UserPromptSubmit").count, 1)
    }

    func test_hookInstallerAcceptsUTF16ClaudeSettings() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)
        let settings = tempHome.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rawSettings = #"{"theme":"dark","hooks":{}}"#
        var data = Data([0xFF, 0xFE])
        data.append(try XCTUnwrap(rawSettings.data(using: .utf16LittleEndian)))
        try data.write(to: settings)

        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)

        let installed = try loadInstalledSettings()
        XCTAssertEqual(installed["theme"] as? String, "dark")
        let hooks = try XCTUnwrap(installed["hooks"] as? [String: Any])
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop").count, 1)
        XCTAssertEqual(cabCommands(in: hooks, event: "UserPromptSubmit").count, 1)
    }

    func test_hookInstallerTreatsCommentOnlyClaudeSettingsAsEmpty() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)
        let settings = tempHome.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        // User note.
        /*
           Existing block comment.
        */
        """.write(to: settings, atomically: true, encoding: .utf8)

        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)

        let hooks = try loadInstalledHooks()
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop").count, 1)
        XCTAssertEqual(cabCommands(in: hooks, event: "UserPromptSubmit").count, 1)
    }

    func test_hookInstallerPreservesCommentMarkersInsideStrings() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)
        let settings = tempHome.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        {
          "hooks": {
            "Stop": [
              {
                "matcher": "keep",
                "hooks": [
                  { "type": "command", "command": "echo /* keep me */", "timeout": 1 }
                ]
              }
            ]
          }
        }
        """.write(to: settings, atomically: true, encoding: .utf8)

        try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome)

        let hooks = try loadInstalledHooks()
        XCTAssertEqual(otherCommands(in: hooks, event: "Stop"), ["echo /* keep me */"])
        XCTAssertEqual(cabCommands(in: hooks, event: "Stop").count, 1)
    }

    func test_hookInstallerRejectsUnterminatedBlockCommentWithoutRewritingSettings() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)
        let settings = tempHome.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let originalSettings = """
        {"theme":"dark"} /* broken comment
        "hooks": {"Stop": []}}
        """
        try originalSettings.write(to: settings, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome))
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), originalSettings)
    }

    func test_hookInstallerRejectsBlockCommentBetweenNumberTokensWithoutRewritingSettings() throws {
        let reporter = tempHome.appendingPathComponent("source-cab-report.sh")
        try "#!/bin/sh\nexit 0\n".write(to: reporter, atomically: true, encoding: .utf8)
        let settings = tempHome.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settings.deletingLastPathComponent(), withIntermediateDirectories: true)
        let originalSettings = #"{"theme":1/*x*/2}"#
        try originalSettings.write(to: settings, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try HookInstaller.install(reporterSourceURL: reporter, homeDirectory: tempHome))
        XCTAssertEqual(try String(contentsOf: settings, encoding: .utf8), originalSettings)
    }

    func test_appDelegateWiresHookInstallerOutsideUnitTests() throws {
        let source = try readAppDelegateSource()

        XCTAssertTrue(source.contains("HookInstaller.installBundledReporterIfNeeded()"))
        XCTAssertTrue(source.contains("!Self.isRunningUnitTests"))
    }

    func test_appDelegateSkipsRuntimeWiringDuringUnitTestsBeforeSocketSetup() throws {
        let source = try readAppDelegateSource()
        let launchRange = try XCTUnwrap(source.range(of: "func applicationDidFinishLaunching"))
        let phaseRange = try XCTUnwrap(source.range(
            of: "// === Phase 1 steps",
            range: launchRange.upperBound..<source.endIndex
        ))
        let launchPreamble = String(source[launchRange.lowerBound..<phaseRange.lowerBound])

        XCTAssertTrue(launchPreamble.contains("guard !Self.isRunningUnitTests else"))
        XCTAssertTrue(launchPreamble.contains("skipping app runtime wiring"))
    }

    private func runReporter(event: String = "stop", stdin: String) throws -> [String: Any] {
        let repoRoot = repoRootURL()
        let reporter = repoRoot.appendingPathComponent("Reporter/cab-report.sh")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [reporter.path, event]
        process.currentDirectoryURL = repoRoot
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = tempHome.path
        environment["ITERM_SESSION_ID"] = ""
        environment["TERM_PROGRAM"] = ""
        environment["CLAUDE_PROJECT_DIR"] = ""
        process.environment = environment

        let input = Pipe()
        process.standardInput = input
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        try process.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        XCTAssertEqual(process.terminationStatus, 0)

        let logURL = tempHome
            .appendingPathComponent("Library/Logs/ClaudeAlertBot/hook.log")
        let log = try String(contentsOf: logURL, encoding: .utf8)
        let line = try XCTUnwrap(log.split(separator: "\n").last)
        let data = Data(line.utf8)
        let outer = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(outer["envelope"] as? [String: Any])
    }

    @discardableResult
    private func runDevInstallHook(_ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repoRootURL().appendingPathComponent("scripts/dev-install-hook.sh").path] + arguments
        process.currentDirectoryURL = repoRootURL()
        var environment = ProcessInfo.processInfo.environment
        environment["HOME"] = tempHome.path
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        XCTAssertEqual(process.terminationStatus, 0, output + error)
        return output + error
    }

    private func loadInstalledSettings() throws -> [String: Any] {
        let settings = tempHome.appendingPathComponent(".claude/settings.json")
        let data = try Data(contentsOf: settings)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func loadInstalledHooks() throws -> [String: Any] {
        let settings = try loadInstalledSettings()
        return try XCTUnwrap(settings["hooks"] as? [String: Any])
    }

    private func loadInstalledCodexHooks() throws -> [String: Any] {
        let hooksURL = tempHome.appendingPathComponent(".codex/hooks.json")
        let data = try Data(contentsOf: hooksURL)
        let settings = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap(settings["hooks"] as? [String: Any])
    }

    private func cabCommands(in hooks: [String: Any], event: String) -> [String] {
        commands(in: hooks, event: event).filter { $0.contains("ClaudeAlertBot/cab-report.sh") }
    }

    private func otherCommands(in hooks: [String: Any], event: String) -> [String] {
        commands(in: hooks, event: event).filter { !$0.contains("ClaudeAlertBot/cab-report.sh") }
    }

    private func matchers(in hooks: [String: Any], event: String) -> [String] {
        guard let entries = hooks[event] as? [[String: Any]] else { return [] }
        return entries.compactMap { $0["matcher"] as? String }
    }

    private func commands(in hooks: [String: Any], event: String) -> [String] {
        guard let entries = hooks[event] as? [[String: Any]] else { return [] }
        return entries.flatMap { entry -> [String] in
            guard let commands = entry["hooks"] as? [[String: Any]] else { return [] }
            return commands.compactMap { $0["command"] as? String }
        }
    }

    private func readAppDelegateSource(_ thisFile: StaticString = #filePath) throws -> String {
        let repoRoot = URL(fileURLWithPath: "\(thisFile)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let target = repoRoot.appendingPathComponent("App/AppDelegate.swift")
        return try String(contentsOf: target, encoding: .utf8)
    }

    private func repoRootURL(_ thisFile: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(thisFile)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
