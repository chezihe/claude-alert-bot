// ClaudeAlertBotTests.swift — Phase 2 Wave 0 test target sentinel.
// Proves the XCTest target builds, links, and `@testable import ClaudeAlertBot` works.
import XCTest
import Network
@testable import ClaudeAlertBot

final class ClaudeAlertBotTests: XCTestCase {
    func test_targetCompilesAndLinks() {
        XCTAssertTrue(true, "Sentinel — proves XCTest target builds and @testable import works.")
    }

    func test_socketProbeOutcome_treatsConnectionRefusedWaitingAsFailed() throws {
        let outcome = AppDelegate.socketProbeOutcome(
            for: .waiting(.posix(.ECONNREFUSED))
        )

        XCTAssertEqual(outcome, .failed)
    }

    func test_socketProbeOutcome_preservesNonTerminalStates() {
        XCTAssertNil(AppDelegate.socketProbeOutcome(for: .setup))
        XCTAssertNil(AppDelegate.socketProbeOutcome(for: .preparing))
    }

    func test_hookListenerReceiveDisposition_discardsErrorsWithoutHandlingPartialBuffer() {
        XCTAssertEqual(
            HookListener.receiveDisposition(isComplete: false, hasError: false),
            .continueReceiving
        )
        XCTAssertEqual(
            HookListener.receiveDisposition(isComplete: true, hasError: false),
            .handleBuffer
        )
        XCTAssertEqual(
            HookListener.receiveDisposition(isComplete: false, hasError: true),
            .discardBuffer
        )
        XCTAssertEqual(
            HookListener.receiveDisposition(isComplete: true, hasError: true),
            .discardBuffer
        )
    }

    func test_hookListenerSocketRemoval_removesMatchingOwnedSocket() throws {
        let path = "/private/tmp/cab-owned-\(UUID().uuidString).sock"
        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = .unix(path: path)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { $0.cancel() }
        let ready = expectation(description: "unix listener ready")
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.fulfill()
            case .failed(let error):
                XCTFail("unix listener failed: \(error)")
                ready.fulfill()
            default:
                break
            }
        }
        listener.start(queue: DispatchQueue(label: "com.claudealert.bot.tests.socket-owner"))
        defer {
            listener.cancel()
            try? FileManager.default.removeItem(atPath: path)
        }
        wait(for: [ready], timeout: 2)
        let identity = try XCTUnwrap(HookListener.socketIdentity(at: path))

        XCTAssertTrue(HookListener.removeSocketIfOwned(at: path, ownedIdentity: identity))
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func test_hookListenerSocketRemoval_preservesReplacementAtSamePath() throws {
        let path = "/private/tmp/cab-replaced-\(UUID().uuidString).sock"
        let url = URL(fileURLWithPath: path)
        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = .unix(path: path)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { $0.cancel() }
        let ready = expectation(description: "unix listener ready")
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                ready.fulfill()
            case .failed(let error):
                XCTFail("unix listener failed: \(error)")
                ready.fulfill()
            default:
                break
            }
        }
        listener.start(queue: DispatchQueue(label: "com.claudealert.bot.tests.socket-replacement"))
        defer {
            listener.cancel()
            try? FileManager.default.removeItem(atPath: path)
        }
        wait(for: [ready], timeout: 2)
        let identity = try XCTUnwrap(HookListener.socketIdentity(at: path))
        try FileManager.default.removeItem(atPath: path)
        let replacement = Data("replacement".utf8)
        try replacement.write(to: url)

        XCTAssertFalse(HookListener.removeSocketIfOwned(at: path, ownedIdentity: identity))
        XCTAssertEqual(try Data(contentsOf: url), replacement)
    }

    func test_appDelegateProvidesNormalTerminationCleanupCallback() {
        XCTAssertTrue(
            AppDelegate().responds(to: NSSelectorFromString("applicationWillTerminate:"))
        )
    }
}
