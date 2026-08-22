import Foundation
import ServiceManagement
import os

/// App and CLI side of the XPC link to the privileged daemon.
public final class HelperClient {
    private let log = Logger(subsystem: VoltaicaIdentifiers.app, category: "helper-client")
    private var connection: NSXPCConnection?
    private let lock = NSLock()

    public init() {}

    // MARK: - Installation

    public enum InstallState: String, Sendable {
        case notRegistered
        case enabled
        case requiresApproval
        case notFound

        public var isUsable: Bool { self == .enabled }
    }

    public static var daemonService: SMAppService {
        SMAppService.daemon(plistName: VoltaicaIdentifiers.daemonPlist)
    }

    public static var installState: InstallState {
        switch daemonService.status {
        case .notRegistered: return .notRegistered
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    /// Registers the daemon. macOS shows the user a background-items notification and they can
    /// switch it off in System Settings at any time.
    public static func install() throws {
        try daemonService.register()
    }

    public static func uninstall() throws {
        try daemonService.unregister()
    }

    public static func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    // MARK: - Connection

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(machServiceName: VoltaicaIdentifiers.machService,
                                          options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: VoltaicaHelperProtocol.self)
        if let team = CodeSigning.selfTeamIdentifier() {
            connection.setCodeSigningRequirement(CodeSigning.helperRequirement(teamIdentifier: team))
        }
        connection.invalidationHandler = { [weak self] in self?.clear() }
        connection.interruptionHandler = { [weak self] in self?.clear() }
        connection.resume()
        return connection
    }

    private func clear() {
        lock.lock()
        connection = nil
        lock.unlock()
    }

    /// Every call gets its own error handler so a dead daemon fails the continuation instead of
    /// leaving it dangling, and its own deadline so nothing waits forever.
    private func call<Value>(timeout: Double = 8,
                             _ body: @escaping (VoltaicaHelperProtocol, ContinuationBox<Value>) -> Void) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let box = ContinuationBox(continuation)
            box.armTimeout(seconds: timeout)

            lock.lock()
            if connection == nil { connection = makeConnection() }
            let active = connection
            lock.unlock()

            guard let active else {
                box.resume(.failure(HelperError.notInstalled))
                return
            }
            let proxy = active.remoteObjectProxyWithErrorHandler { [weak self] error in
                self?.log.error("XPC error: \(error.localizedDescription, privacy: .public)")
                self?.clear()
                box.resume(.failure(HelperError.connectionFailed(error.localizedDescription)))
            }
            guard let remote = proxy as? VoltaicaHelperProtocol else {
                box.resume(.failure(HelperError.connectionFailed("interface mismatch")))
                return
            }
            body(remote, box)
        }
    }

    public func disconnect() {
        lock.lock()
        connection?.invalidate()
        connection = nil
        lock.unlock()
    }

    // MARK: - Calls

    public func version() async throws -> String {
        try await call { remote, box in
            remote.helperVersion { box.resume(.success($0)) }
        }
    }

    public func state() async throws -> HelperState {
        let data: Data = try await call { remote, box in
            remote.fetchState { payload, error in
                if let payload { box.resume(.success(payload)) }
                else { box.resume(.failure(HelperError.remote(error ?? "no state"))) }
            }
        }
        return try Self.decode(data)
    }

    @discardableResult
    public func apply(_ configuration: ChargeConfiguration) async throws -> HelperState {
        let payload = try JSONEncoder().encode(configuration)
        let data: Data = try await call { remote, box in
            remote.apply(configuration: payload) { response, error in
                if let response { box.resume(.success(response)) }
                else { box.resume(.failure(HelperError.remote(error ?? "apply failed"))) }
            }
        }
        return try Self.decode(data)
    }

    public func readSMC(keys: [String]) async throws -> [String: String] {
        try await call { remote, box in
            remote.readSMC(keys: keys) { box.resume(.success($0)) }
        }
    }

    public func dumpSMC(prefix: String) async throws -> [String: String] {
        try await call(timeout: 30) { remote, box in
            remote.dumpSMC(prefix: prefix) { box.resume(.success($0)) }
        }
    }

    @discardableResult
    public func activate(licenseKey: String) async throws -> HelperState {
        let data: Data = try await call { remote, box in
            remote.activate(licenseKey: licenseKey) { response, error in
                if let response { box.resume(.success(response)) }
                else { box.resume(.failure(HelperError.remote(error ?? "activation failed"))) }
            }
        }
        return try Self.decode(data)
    }

    @discardableResult
    public func deactivateLicense() async throws -> HelperState {
        let data: Data = try await call { remote, box in
            remote.deactivateLicense { response, error in
                if let response { box.resume(.success(response)) }
                else { box.resume(.failure(HelperError.remote(error ?? "deactivation failed"))) }
            }
        }
        return try Self.decode(data)
    }

    public func relinquish() async throws {
        let _: Bool = try await call { remote, box in
            remote.relinquish { box.resume(.success($0)) }
        }
    }

    private static func decode(_ data: Data) throws -> HelperState {
        do { return try JSONDecoder().decode(HelperState.self, from: data) }
        catch { throw HelperError.decodingFailed }
    }
}

/// XPC reply blocks can be dropped when the peer dies, so every call carries its own timeout
/// and resumes exactly once.
final class ContinuationBox<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    private let lock = NSLock()

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<Value, Error>) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        guard let pending else { return }
        switch result {
        case .success(let value): pending.resume(returning: value)
        case .failure(let error): pending.resume(throwing: error)
        }
    }

    /// Captured strongly on purpose: the box has to outlive the XPC reply block, which the
    /// system drops on the floor when the peer is not there at all.
    func armTimeout(seconds: Double) {
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            self.resume(.failure(HelperError.connectionFailed("timed out")))
        }
    }
}
