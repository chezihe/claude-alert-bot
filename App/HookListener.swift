// App/HookListener.swift — NWListener AF_UNIX (RESEARCH Pattern 4 verbatim + 3 security additions).
// Security additions per plan threat model:
//   - T-IPC-01 mitigation: chmod 0600 on socket file once .ready
//   - T-IPC-02 mitigation: reject envelopes whose schema_version != 1
//   - T-IPC-03 mitigation: 64KB cap per connection (V5 input validation)
// D-09: bind exclusivity = single-instance lock; .failed → NSApp.terminate(nil).
// D-07: OSLog subsystem "com.claudealert.bot.hook"; "listener bound" line is what
//       verify-phase-1.sh row 1-02-02 greps for.
import Network
import Foundation
import AppKit
import os

final class HookListener {
    struct SocketIdentity: Equatable {
        let device: UInt64
        let inode: UInt64
    }

    enum ReceiveDisposition: Equatable {
        case continueReceiving
        case handleBuffer
        case discardBuffer
    }

    private let log = Logger(subsystem: "com.claudealert.bot.hook", category: "listener")
    private let ingressLog = Logger(subsystem: "com.claudealert.bot.hook", category: "ingress")
    private let socketPath: String
    private let queue = DispatchQueue(label: "com.claudealert.bot.hook.listener")
    private let ownershipLock = NSLock()
    private var listener: NWListener?
    private var ownedSocketIdentity: SocketIdentity?
    private var isCancelled = false

    init(socketPath: String) { self.socketPath = socketPath }

    func start() throws {
        ownershipLock.withLock {
            isCancelled = false
            ownedSocketIdentity = nil
        }
        let params = NWParameters()
        params.defaultProtocolStack.transportProtocol = NWProtocolTCP.Options()
        params.requiredLocalEndpoint = NWEndpoint.unix(path: socketPath)
        params.allowLocalEndpointReuse = true

        let listener = try NWListener(using: params)
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.log.notice("listener bound on \(self.socketPath, privacy: .public)")
                // T-IPC-01 mitigation: chmod 0600 socket file after bind succeeds.
                chmod(self.socketPath, 0o600)
                self.recordSocketOwnership()
            case .failed(let err):
                self.log.error("listener failed: \(String(describing: err), privacy: .public) — assuming another instance owns the socket; terminating (D-09)")
                DispatchQueue.main.async { NSApp.terminate(nil) }
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] conn in
            self?.accept(conn)
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func cancel() {
        let ownedIdentity = ownershipLock.withLock {
            isCancelled = true
            defer { ownedSocketIdentity = nil }
            return ownedSocketIdentity
        }
        listener?.cancel()
        listener = nil
        guard let ownedIdentity else { return }
        if Self.removeSocketIfOwned(at: socketPath, ownedIdentity: ownedIdentity) {
            log.notice("removed owned socket at \(self.socketPath, privacy: .public)")
        } else {
            log.notice("preserved socket at \(self.socketPath, privacy: .public) because ownership changed")
        }
    }

    private func recordSocketOwnership() {
        guard let identity = Self.socketIdentity(at: socketPath) else {
            log.error("listener ready but socket identity is unavailable at \(self.socketPath, privacy: .public)")
            return
        }
        let cancelled = ownershipLock.withLock {
            guard !isCancelled else { return true }
            ownedSocketIdentity = identity
            return false
        }
        if cancelled {
            _ = Self.removeSocketIfOwned(at: socketPath, ownedIdentity: identity)
        }
    }

    static func socketIdentity(at path: String) -> SocketIdentity? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeSocket,
              let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber
        else { return nil }
        return SocketIdentity(device: device.uint64Value, inode: inode.uint64Value)
    }

    @discardableResult
    static func removeSocketIfOwned(at path: String, ownedIdentity: SocketIdentity) -> Bool {
        guard socketIdentity(at: path) == ownedIdentity else { return false }
        do {
            try FileManager.default.removeItem(atPath: path)
            return true
        } catch {
            return false
        }
    }

    private func accept(_ conn: NWConnection) {
        var buffer = Data()
        conn.stateUpdateHandler = { state in
            if case .failed = state { conn.cancel() }
        }
        // V5 input validation: cap at 64KB across the whole connection.
        let maxBytes = 65_536
        func loop() {
            conn.receive(minimumIncompleteLength: 1, maximumLength: maxBytes) { [weak self] data, _, isComplete, error in
                let disposition = Self.receiveDisposition(isComplete: isComplete, hasError: error != nil)
                if disposition == .discardBuffer {
                    self?.log.warning("dropping connection: receive failed: \(String(describing: error), privacy: .public)")
                    conn.cancel()
                    return
                }
                if let data { buffer.append(data) }
                if buffer.count > maxBytes {
                    self?.log.warning("dropping connection: envelope > 64KB")
                    conn.cancel()
                    return
                }
                if disposition == .handleBuffer {
                    self?.handle(buffer: buffer)
                    conn.cancel()
                } else {
                    loop()
                }
            }
        }
        conn.start(queue: queue)
        loop()
    }

    static func receiveDisposition(isComplete: Bool, hasError: Bool) -> ReceiveDisposition {
        if hasError { return .discardBuffer }
        return isComplete ? .handleBuffer : .continueReceiving
    }

    private func handle(buffer: Data) {
        do {
            let event = try JSONDecoder().decode(HookEvent.self, from: buffer)
            // T-IPC-02 mitigation: reject envelopes with unknown schema_version.
            guard event.schema_version == 1 else {
                log.warning("rejecting event with unknown schema_version=\(event.schema_version)")
                return
            }
            // NOTE (Phase 5 review): cwd/session_id logged at .public for dev visibility (D-07).
            //   Reclassify to .private once OSLog is no longer the primary verification surface.
            ingressLog.notice("ingress event=\(event.event, privacy: .public) session=\(event.session_id ?? "nil", privacy: .public) cwd=\(event.cwd ?? "nil", privacy: .public)")

            // === Phase 2 dispatch (Wave 6 — 02-11 addition) ===
            // D2-35 Path B: trigger TCC dialog on first Stop when permission == .unknown.
            // The first Stop alert fires normally (Path B trade-off — see CONTEXT D2-35).
            Task { @MainActor in
                let store = SettingsStore.shared
                let threshold = store.thresholdSeconds
                let soundOn = store.soundEnabled
                let perm = store.applescriptPermission

                if Self.shouldTriggerPermissionPrompt(permission: perm, event: event) {
                    Task { await AppleScriptHelper.shared.triggerPermissionPrompt() }
                }

                let permGranted = (perm == .granted)
                await SessionRegistry.shared.ingest(
                    event,
                    thresholdSeconds: threshold,
                    soundEnabled: soundOn,
                    suppressIfFrontmost: { iTermID in
                        guard permGranted, let normalized = iTermSessionID.uuid(fromRaw: iTermID) else { return false }
                        return await AppleScriptHelper.shared.frontmostMatches(itermSessionID: normalized)
                    }
                )
            }
        } catch {
            log.error("decode failed: \(String(describing: error), privacy: .public)")
        }
    }

    static func shouldTriggerPermissionPrompt(permission: PermissionStatus, event: HookEvent) -> Bool {
        permission == .unknown &&
        event.event == "stop" &&
        SessionRegistry.isSupportedTerminal(event.term_program)
    }
}
