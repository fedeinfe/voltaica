import Foundation
import Security

public enum VoltaicaIdentifiers {
    public static let app = "com.federicoinfelici.Voltaica"
    public static let helper = "com.federicoinfelici.Voltaica.Helper"
    public static let cli = "com.federicoinfelici.Voltaica.cli"
    public static let machService = "com.federicoinfelici.Voltaica.Helper"
    public static let daemonPlist = "com.federicoinfelici.Voltaica.Helper.plist"
    public static let teamIdentifier = "68438RG5HP"
    public static let supportDirectory = "/Library/Application Support/Voltaica"
    public static let appGroupDefaults = "com.federicoinfelici.Voltaica"
    public static let website = "https://github.com/fedeinfe/voltaica"
}

/// The full picture the daemon reports back to any client.
public struct HelperState: Codable, Sendable {
    public var helperVersion: String = ""
    public var configuration = ChargeConfiguration()
    public var snapshot = BatterySnapshot()
    public var decision = PolicyDecision()
    public var hardware = HardwarePowerState(chargingAllowed: true, adapterEnabled: true)
    public var capabilities = HardwareCapabilities.unknown
    public var calibrationHistory = CalibrationHistory()
    public var lastError: String?
    public var startedAt = Date()
    /// Recent transitions, newest last. The app turns the ones it has not seen into notifications.
    public var recentEvents: [TimestampedEvent] = []
    public var license: LicenseInfo?
    /// When this Mac first ran the daemon, which is what the trial counts from.
    public var firstRun = Date()

    public var licenseState: LicenseState { License.state(license: license, firstRun: firstRun) }

    public init() {}
}

/// The daemon's XPC surface. Payloads are JSON so the two sides only share this file.
@objc public protocol VoltaicaHelperProtocol {
    func helperVersion(reply: @escaping (String) -> Void)
    func fetchState(reply: @escaping (Data?, String?) -> Void)
    func apply(configuration: Data, reply: @escaping (Data?, String?) -> Void)
    func readSMC(keys: [String], reply: @escaping ([String: String]) -> Void)
    /// Every key whose name starts with `prefix`, for the diagnostics screen. Root sees keys an
    /// unprivileged process cannot even enumerate, which is why this lives on the daemon.
    func dumpSMC(prefix: String, reply: @escaping ([String: String]) -> Void)
    /// Hands the charger back to macOS and stops enforcing anything. Used before uninstalling.
    func relinquish(reply: @escaping (Bool) -> Void)
    /// Stores a license key after checking its signature. The daemon owns this so the same
    /// entitlement applies to the app, the CLI and anything written straight to the policy file.
    func activate(licenseKey: String, reply: @escaping (Data?, String?) -> Void)
    func deactivateLicense(reply: @escaping (Data?, String?) -> Void)
}

public enum HelperError: Error, LocalizedError {
    case notInstalled
    case connectionFailed(String)
    case decodingFailed
    case remote(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled: return "The Voltaica background service is not installed yet."
        case .connectionFailed(let reason): return "Could not reach the background service: \(reason)"
        case .decodingFailed: return "The background service sent something unreadable."
        case .remote(let message): return message
        }
    }
}

public enum CodeSigning {
    /// The team that signed the running binary, or nil when it is unsigned or ad-hoc signed.
    public static func selfTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf(SecCSFlags(), &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode else { return nil }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &information) == errSecSuccess,
              let dictionary = information as? [String: Any] else { return nil }
        return dictionary["teamid"] as? String
    }

    /// Requirement the daemon puts on its clients: same team, one of our two front ends.
    public static func clientRequirement(teamIdentifier: String) -> String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and "
            + "(identifier \"\(VoltaicaIdentifiers.app)\" or identifier \"\(VoltaicaIdentifiers.cli)\")"
    }

    /// Requirement a client puts on the daemon, so nothing can impersonate it.
    public static func helperRequirement(teamIdentifier: String) -> String {
        "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and "
            + "identifier \"\(VoltaicaIdentifiers.helper)\""
    }
}
