import XCTest

final class LocalSigningTests: XCTestCase {
    private let identityFingerprint = String(repeating: "A", count: 40)
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("cab-local-signing-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try writeFakeTools()
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
    }

    private func repoRootURL(_ thisFile: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(thisFile)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ path: String) throws -> String {
        try String(
            contentsOf: repoRootURL().appendingPathComponent(path),
            encoding: .utf8
        )
    }

    func test_signingConfigKeepsXcodeDrivenBuildsAdHoc() throws {
        let config = try source("Config/Signing.xcconfig")

        XCTAssertTrue(config.contains("CAB_CODE_SIGN_IDENTITY = -"))
        XCTAssertTrue(config.contains("CODE_SIGN_IDENTITY = $(CAB_CODE_SIGN_IDENTITY)"))
        XCTAssertTrue(config.contains("CODE_SIGN_STYLE = Manual"))
        XCTAssertFalse(
            config.contains("#include? \"LocalSigning.xcconfig\""),
            "Feeding the local identity to Xcode makes `xcodebuild test` fail with "
                + "\"Signing certificate is invalid\"; scripts/build.sh applies it after archiving instead"
        )
    }

    func test_projectUsesSigningConfigAndAutomationEntitlementsForAppOnly() throws {
        let project = try source("project.yml")

        XCTAssertTrue(project.contains("configFiles:"))
        XCTAssertTrue(project.contains("Debug: Config/Signing.xcconfig"))
        XCTAssertTrue(project.contains("Release: Config/Signing.xcconfig"))
        XCTAssertTrue(project.contains("CODE_SIGN_ENTITLEMENTS: App/ClaudeAlertBot.entitlements"))
        XCTAssertEqual(project.components(separatedBy: "CODE_SIGN_ENTITLEMENTS:").count - 1, 1)
    }

    func test_localSigningOverrideIsIgnored() throws {
        let gitignore = try source(".gitignore")
        XCTAssertTrue(gitignore.contains("/Config/LocalSigning.xcconfig"))
    }

    func test_setupReusesExistingExactIdentityByFingerprint() throws {
        try seedUsableIdentity()

        let result = try runSetup()

        XCTAssertEqual(result.status, 0, result.output)
        let config = try localConfigSource()
        XCTAssertTrue(config.contains("CAB_CODE_SIGN_IDENTITY = \(identityFingerprint)"))
        XCTAssertTrue(config.contains("CAB_CODE_SIGN_KEYCHAIN = \(keychainURL().path)"))
        XCTAssertFalse(try commandLog().contains("security import "))
    }

    func test_setupRejectsDuplicateExactIdentityNames() throws {
        try Data().write(to: tempRoot.appendingPathComponent("duplicate-identities"))

        let result = try runSetup()

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("multiple exact signing identities"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localConfigURL().path))
    }

    func test_setupRejectsNamedCertificateWithoutUsablePrivateKey() throws {
        try Data().write(to: tempRoot.appendingPathComponent("certificate-present"))

        let result = try runSetup()

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("certificate exists but is not a usable signing identity"), result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localConfigURL().path))
    }

    func test_setupCreatesIdentityOnlyOnceWithCodesignOnlyKeyAccess() throws {
        let first = try runSetup()
        let second = try runSetup()

        XCTAssertEqual(first.status, 0, first.output)
        XCTAssertEqual(second.status, 0, second.output)
        let log = try commandLog()
        XCTAssertEqual(log.components(separatedBy: "security import ").count - 1, 2)
        XCTAssertTrue(log.contains("-T /usr/bin/codesign"))
        XCTAssertFalse(log.contains(" -A"))
        XCTAssertFalse(log.contains(" -P"))
        XCTAssertFalse(log.contains("-T /usr/bin/security"))
    }

    func test_setupStatusSucceedsForConfiguredUsableFingerprint() throws {
        try seedUsableIdentity()
        try writeLocalConfig(fingerprint: identityFingerprint)

        let result = try runSetup(arguments: ["--status"])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("configured and usable"), result.output)
    }

    func test_setupStatusFailsWhenConfigurationIsMissing() throws {
        let result = try runSetup(arguments: ["--status"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("not configured"), result.output)
    }

    func test_setupStatusFailsWhenConfiguredIdentityIsMissing() throws {
        try writeLocalConfig(fingerprint: identityFingerprint)

        let result = try runSetup(arguments: ["--status"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("configured identity is unavailable"), result.output)
    }

    func test_setupGeneratesRealRootAndIssuedCodeSigningLeaf() throws {
        let result = try runSetup(useRealOpenSSL: true)

        XCTAssertEqual(result.status, 0, result.output)
        let rootText = try runProcess(
            executable: "/usr/bin/openssl",
            arguments: ["x509", "-in", capturedRootCertificateURL().path, "-noout", "-text"]
        )
        XCTAssertEqual(rootText.status, 0, rootText.output)
        XCTAssertTrue(rootText.output.contains("CA:TRUE, pathlen:0"))
        XCTAssertTrue(rootText.output.contains("Certificate Sign"))

        let leafText = try runProcess(
            executable: "/usr/bin/openssl",
            arguments: ["x509", "-in", capturedLeafCertificateURL().path, "-noout", "-text"]
        )
        XCTAssertEqual(leafText.status, 0, leafText.output)
        XCTAssertTrue(leafText.output.contains("CA:FALSE"))
        XCTAssertTrue(leafText.output.contains("Digital Signature"))
        XCTAssertTrue(leafText.output.contains("Code Signing"))
    }

    func test_setupUsesDistinctRootAndCodeSigningLeafCertificates() throws {
        let script = try source("scripts/setup-local-signing.sh")

        XCTAssertTrue(script.contains(#"ROOT_IDENTITY_NAME="ClaudeAlertBot Local Root CA v2""#))
        XCTAssertTrue(script.contains(#"IDENTITY_NAME="ClaudeAlertBot Local Development v2""#))
        XCTAssertTrue(script.contains("basicConstraints = critical,CA:TRUE,pathlen:0"))
        XCTAssertTrue(script.contains("basicConstraints = critical,CA:FALSE"))
        XCTAssertTrue(script.contains("-CA \"$ROOT_CERT_PATH\""))
        XCTAssertTrue(script.contains("-CAkey \"$ROOT_KEY_PATH\""))
    }

    func test_setupVerifiesSignedProbeBeforeWritingLocalConfig() throws {
        let script = try source("scripts/setup-local-signing.sh")
        let verifyRange = try XCTUnwrap(script.range(of: #""$CODESIGN_BIN" --verify"#))
        let configRange = try XCTUnwrap(script.range(of: #"write_local_config "$fingerprint""#))

        XCTAssertLessThan(verifyRange.lowerBound, configRange.lowerBound)
    }

    func test_setupDoesNotWriteLocalConfigWhenProbeVerificationFails() throws {
        try Data().write(to: tempRoot.appendingPathComponent("probe-verification-fail"))

        let result = try runSetup()

        XCTAssertNotEqual(result.status, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: localConfigURL().path))
    }

    func test_buildSigningStatusDefaultsToAdHoc() throws {
        let result = try runBuildSigningStatus()

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("mode=ad-hoc identity=-"), result.output)
    }

    func test_buildSigningStatusUsesConfiguredFingerprint() throws {
        let result = try runBuildSigningStatus(
            configuredFingerprint: identityFingerprint,
            identityReady: true
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(
            result.output.contains("mode=local identity=\(identityFingerprint)"),
            result.output
        )
    }

    func test_buildSigningStatusFailsWhenConfiguredIdentityIsMissing() throws {
        let result = try runBuildSigningStatus(configuredFingerprint: identityFingerprint)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(
            result.output.contains("local signing is configured but the identity is unavailable"),
            result.output
        )
    }

    func test_buildSigningStatusRejectsMalformedFingerprint() throws {
        let result = try runBuildSigningStatus(configuredFingerprint: "not-a-fingerprint")

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("invalid certificate fingerprint"), result.output)
    }

    func test_buildScriptAvoidsEmptyArrayExpansionUnderSystemBashStrictMode() throws {
        let script = try source("scripts/build.sh")

        XCTAssertFalse(script.contains("${SIGN_KEYCHAIN_ARGS[@]}"))
    }

    func test_buildArchiveUsesAdHocBeforeFinalLocalResign() throws {
        let script = try source("scripts/build.sh")

        XCTAssertTrue(script.contains("CAB_CODE_SIGN_IDENTITY=-"))
        XCTAssertTrue(script.contains("CODE_SIGN_IDENTITY=-"))
        XCTAssertTrue(script.contains(#"sign_code --options=runtime --entitlements "$ENTITLEMENTS" "$APP""#))
    }

    func test_buildExtractsSigningCertificateWithOptionValueSyntax() throws {
        let script = try source("scripts/build.sh")

        XCTAssertTrue(script.contains(#"--extract-certificates="$certificate_prefix""#))
        XCTAssertFalse(script.contains(#"--extract-certificates "$certificate_prefix""#))
    }

    func test_buildDoesNotExitNonzeroWhenOptionalSignatureSummaryIsEmpty() throws {
        let script = try source("scripts/build.sh")

        XCTAssertFalse(script.contains(#"[ -n "${CABTEST_SIG:-}" ] && echo"#))
        XCTAssertTrue(script.contains(#"if [[ -n "${CABTEST_SIG:-}" ]]; then"#))
    }

    func test_buildReportsVerifiedLocalSignatureAuthority() throws {
        let script = try source("scripts/build.sh")

        XCTAssertTrue(script.contains(#"BUNDLE_SIG="Authority=$IDENTITY_NAME""#))
        XCTAssertTrue(script.contains(#"MAIN_SIG="Authority=$IDENTITY_NAME""#))
        XCTAssertTrue(script.contains(#"CABTEST_SIG="Authority=$IDENTITY_NAME""#))
    }

    func test_runProcessHandlesOutputLargerThanPipeBuffer() throws {
        let result = try runProcess(
            executable: "/usr/bin/awk",
            arguments: [#"BEGIN { for (i = 0; i < 100000; i++) print "0123456789" }"#]
        )

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output.utf8.count, 1_100_000)
    }

    private func runSetup(
        arguments: [String] = [],
        useRealOpenSSL: Bool = false
    ) throws -> (status: Int32, output: String) {
        var environment = ProcessInfo.processInfo.environment
        environment["CAB_SECURITY_BIN"] = tempRoot.appendingPathComponent("fake-security").path
        environment["CAB_OPENSSL_BIN"] = useRealOpenSSL
            ? "/usr/bin/openssl"
            : tempRoot.appendingPathComponent("fake-openssl").path
        environment["CAB_CODESIGN_BIN"] = tempRoot.appendingPathComponent("fake-codesign").path
        environment["CAB_KEYCHAIN_PATH"] = keychainURL().path
        environment["CAB_LOCAL_SIGNING_CONFIG_PATH"] = localConfigURL().path
        environment["CAB_FAKE_STATE_DIR"] = tempRoot.path
        environment["CAB_FAKE_LOG"] = tempRoot.appendingPathComponent("commands.log").path
        return try runProcess(
            executable: "/bin/bash",
            arguments: [repoRootURL().appendingPathComponent("scripts/setup-local-signing.sh").path] + arguments,
            environment: environment
        )
    }

    private func runBuildSigningStatus(
        configuredFingerprint: String? = nil,
        identityReady: Bool = false
    ) throws -> (status: Int32, output: String) {
        if let configuredFingerprint {
            try writeLocalConfig(fingerprint: configuredFingerprint)
        }
        if identityReady {
            try seedUsableIdentity()
        }

        let fakeBin = tempRoot.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        try writeExecutable(
            """
            #!/bin/bash
            echo "unexpected xcodebuild invocation" >&2
            exit 99
            """,
            at: fakeBin.appendingPathComponent("xcodebuild")
        )

        var environment = ProcessInfo.processInfo.environment
        environment["CAB_SECURITY_BIN"] = tempRoot.appendingPathComponent("fake-security").path
        environment["CAB_KEYCHAIN_PATH"] = keychainURL().path
        environment["CAB_LOCAL_SIGNING_CONFIG_PATH"] = localConfigURL().path
        environment["CAB_FAKE_STATE_DIR"] = tempRoot.path
        environment["CAB_FAKE_LOG"] = tempRoot.appendingPathComponent("commands.log").path
        environment["PATH"] = "\(fakeBin.path):/usr/bin:/bin:/usr/sbin:/sbin"
        return try runProcess(
            executable: "/bin/bash",
            arguments: [
                repoRootURL().appendingPathComponent("scripts/build.sh").path,
                "--signing-status"
            ],
            environment: environment
        )
    }

    private func runProcess(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = repoRootURL()
        process.environment = environment
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe
        try process.run()
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(
            data: outputData,
            encoding: .utf8
        ) ?? ""
        return (process.terminationStatus, output)
    }

    private func seedUsableIdentity() throws {
        try Data().write(to: tempRoot.appendingPathComponent("identity-ready"))
        try identityFingerprint.write(
            to: tempRoot.appendingPathComponent("identity-fingerprint"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeLocalConfig(fingerprint: String) throws {
        try """
        CAB_CODE_SIGN_IDENTITY = \(fingerprint)
        CAB_CODE_SIGN_KEYCHAIN = \(keychainURL().path)
        OTHER_CODE_SIGN_FLAGS = --keychain "$(CAB_CODE_SIGN_KEYCHAIN)"
        """.write(to: localConfigURL(), atomically: true, encoding: .utf8)
    }

    private func localConfigSource() throws -> String {
        try String(contentsOf: localConfigURL(), encoding: .utf8)
    }

    private func commandLog() throws -> String {
        try String(
            contentsOf: tempRoot.appendingPathComponent("commands.log"),
            encoding: .utf8
        )
    }

    private func localConfigURL() -> URL {
        tempRoot.appendingPathComponent("LocalSigning.xcconfig")
    }

    private func keychainURL() -> URL {
        tempRoot.appendingPathComponent("login.keychain-db")
    }

    private func capturedRootCertificateURL() -> URL {
        tempRoot.appendingPathComponent("captured-root-certificate.pem")
    }

    private func capturedLeafCertificateURL() -> URL {
        tempRoot.appendingPathComponent("captured-leaf-certificate.pem")
    }

    private func writeFakeTools() throws {
        try writeExecutable(
            """
            #!/bin/bash
            set -eu
            printf 'security %s\n' "$*" >> "$CAB_FAKE_LOG"
            default_fingerprint="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

            case "$1" in
              find-identity)
                if [[ -f "$CAB_FAKE_STATE_DIR/duplicate-identities" ]]; then
                  printf '  1) %s "ClaudeAlertBot Local Development v2"\n' "$default_fingerprint"
                  printf '  2) BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB "ClaudeAlertBot Local Development v2"\n'
                elif [[ -f "$CAB_FAKE_STATE_DIR/identity-ready" ]]; then
                  fingerprint=$(cat "$CAB_FAKE_STATE_DIR/identity-fingerprint" 2>/dev/null || printf '%s' "$default_fingerprint")
                  printf '  1) %s "ClaudeAlertBot Local Development v2"\n' "$fingerprint"
                else
                  printf '     0 valid identities found\n'
                fi
                ;;
              find-certificate)
                if [[ "$*" == *"ClaudeAlertBot Local Root CA v2"* ]]; then
                  [[ -f "$CAB_FAKE_STATE_DIR/root-certificate-present" ]] || exit 44
                else
                  [[ -f "$CAB_FAKE_STATE_DIR/certificate-present" || -f "$CAB_FAKE_STATE_DIR/leaf-certificate-present" ]] || exit 44
                fi
                ;;
              add-trusted-cert)
                certificate="${@: -1}"
                touch "$CAB_FAKE_STATE_DIR/root-certificate-present"
                cp "$certificate" "$CAB_FAKE_STATE_DIR/captured-root-certificate.pem"
                ;;
              import)
                imported="$2"
                if [[ "$*" == *" -t cert"* ]]; then
                  touch "$CAB_FAKE_STATE_DIR/leaf-certificate-present"
                  cp "$imported" "$CAB_FAKE_STATE_DIR/captured-leaf-certificate.pem"
                  if fingerprint=$(/usr/bin/openssl x509 -in "$imported" -noout -fingerprint -sha1 2>/dev/null); then
                    fingerprint=${fingerprint#*=}
                    fingerprint=${fingerprint//:/}
                  else
                    fingerprint="$default_fingerprint"
                  fi
                  printf '%s' "$fingerprint" > "$CAB_FAKE_STATE_DIR/identity-fingerprint"
                else
                  touch "$CAB_FAKE_STATE_DIR/identity-ready"
                fi
                ;;
              *)
                exit 64
                ;;
            esac
            """,
            at: tempRoot.appendingPathComponent("fake-security")
        )

        try writeExecutable(
            """
            #!/bin/bash
            set -eu
            printf 'openssl %s\n' "$*" >> "$CAB_FAKE_LOG"
            default_fingerprint="AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA"

            if [[ "$1" == "x509" && "$*" == *" -text"* ]]; then
              if [[ "$*" == *"local-root.crt"* ]]; then
                printf 'CA:TRUE, pathlen:0\nCertificate Sign\n'
              else
                printf 'CA:FALSE\nDigital Signature\nCode Signing\n'
              fi
              exit 0
            fi
            if [[ "$1" == "x509" && "$*" == *" -fingerprint"* ]]; then
              printf 'sha1 Fingerprint=%s\n' "$default_fingerprint"
              exit 0
            fi

            previous=""
            for argument in "$@"; do
              if [[ "$previous" == "-out" ]]; then
                : > "$argument"
              fi
              previous="$argument"
            done

            case "$1" in
              genrsa|req|x509) exit 0 ;;
              *) exit 64 ;;
            esac
            """,
            at: tempRoot.appendingPathComponent("fake-openssl")
        )

        try writeExecutable(
            """
            #!/bin/bash
            set -eu
            printf 'codesign %s\n' "$*" >> "$CAB_FAKE_LOG"
            if [[ "$*" == *"--verify"* && -f "$CAB_FAKE_STATE_DIR/probe-verification-fail" ]]; then
              exit 70
            fi
            exit 0
            """,
            at: tempRoot.appendingPathComponent("fake-codesign")
        )
    }

    private func writeExecutable(_ contents: String, at url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o700))],
            ofItemAtPath: url.path
        )
    }
}
