import Foundation
import VoltaicaCore
import os

/// Answers XPC requests from the app and the CLI. Every connection is checked against a code
/// signing requirement first: same team, and one of our two front ends.
final class HelperService: NSObject, NSXPCListenerDelegate, VoltaicaHelperProtocol {
    private let log = Logger(subsystem: VoltaicaIdentifiers.helper, category: "xpc")
    private let listener: NSXPCListener

    override init() {
        listener = NSXPCListener(machServiceName: VoltaicaIdentifiers.machService)
        super.init()
        listener.delegate = self
    }

    func run() {
        listener.resume()
        log.notice("listening on \(VoltaicaIdentifiers.machService, privacy: .public)")
    }

    // MARK: - NSXPCListenerDelegate

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if let team = CodeSigning.selfTeamIdentifier() {
            connection.setCodeSigningRequirement(CodeSigning.clientRequirement(teamIdentifier: team))
        } else {
            // Unsigned or ad-hoc: a local build. Accept, but say so loudly in the log.
            log.warning("helper is not team signed, accepting clients without a signing requirement")
        }
        connection.exportedInterface = NSXPCInterface(with: VoltaicaHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    // MARK: - VoltaicaHelperProtocol

    func helperVersion(reply: @escaping (String) -> Void) {
        reply(VoltaicaVersion.full)
    }

    func fetchState(reply: @escaping (Data?, String?) -> Void) {
        var state = PolicyRunner.shared.currentState()
        state.recentEvents = EventBridge.shared.recent()
        do {
            reply(try JSONEncoder().encode(state), nil)
        } catch {
            reply(nil, String(describing: error))
        }
    }

    func apply(configuration: Data, reply: @escaping (Data?, String?) -> Void) {
        do {
            let incoming = try JSONDecoder().decode(ChargeConfiguration.self, from: configuration)
            var state = PolicyRunner.shared.update(configuration: incoming)
            state.recentEvents = EventBridge.shared.recent()
            reply(try JSONEncoder().encode(state), nil)
        } catch {
            log.error("apply failed: \(String(describing: error), privacy: .public)")
            reply(nil, String(describing: error))
        }
    }

    func readSMC(keys: [String], reply: @escaping ([String: String]) -> Void) {
        reply(PolicyRunner.shared.readSMC(keys: Array(keys.prefix(64))))
    }

    func dumpSMC(prefix: String, reply: @escaping ([String: String]) -> Void) {
        reply(PolicyRunner.shared.dumpSMC(prefix: String(prefix.prefix(4))))
    }

    func relinquish(reply: @escaping (Bool) -> Void) {
        PolicyRunner.shared.relinquish()
        reply(true)
    }

    func activate(licenseKey: String, reply: @escaping (Data?, String?) -> Void) {
        guard var state = PolicyRunner.shared.activate(licenseKey: licenseKey) else {
            reply(nil, "That license key is not valid.")
            return
        }
        state.recentEvents = EventBridge.shared.recent()
        reply(try? JSONEncoder().encode(state), nil)
    }

    func deactivateLicense(reply: @escaping (Data?, String?) -> Void) {
        var state = PolicyRunner.shared.deactivateLicense()
        state.recentEvents = EventBridge.shared.recent()
        reply(try? JSONEncoder().encode(state), nil)
    }
}
