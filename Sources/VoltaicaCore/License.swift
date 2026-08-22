import CryptoKit
import Foundation

/// What a given license state is allowed to do. The free tier keeps every read-only feature and
/// the 80% ceiling, because a battery tool that stops protecting the battery when unpaid would be
/// worse than useless; everything that needs a decision from us is what you pay for.
public struct FeatureSet: Sendable, Equatable {
    public let customLimit: Bool
    public let sailingMode: Bool
    public let discharge: Bool
    public let calibration: Bool
    public let schedules: Bool
    public let heatProtection: Bool

    public static let full = FeatureSet(customLimit: true, sailingMode: true, discharge: true,
                                       calibration: true, schedules: true, heatProtection: true)
    public static let free = FeatureSet(customLimit: false, sailingMode: false, discharge: false,
                                       calibration: false, schedules: false, heatProtection: false)

    /// The single limit the free tier may hold, matching the value Apple's own firmware uses.
    public static let freeTierLimit = 80
}

public struct LicenseInfo: Codable, Sendable, Equatable {
    public var email: String
    public var order: String
    public var issued: Date
    public var seats: Int

    public init(email: String, order: String, issued: Date, seats: Int = 3) {
        self.email = email
        self.order = order
        self.issued = issued
        self.seats = seats
    }
}

public enum LicenseState: Sendable, Equatable {
    case trial(daysLeft: Int)
    case trialExpired
    case licensed(LicenseInfo)

    public var features: FeatureSet {
        switch self {
        case .licensed, .trial: return .full
        case .trialExpired: return .free
        }
    }

    public var isPaid: Bool { if case .licensed = self { return true }; return false }
}

public enum License {
    public static let trialDays = 14
    public static let price = "€9.99"
    public static let purchaseURL = URL(string: "https://voltaica.app/buy")!

    /// Ed25519 public half of the signing pair. The private half never leaves Federico's machine,
    /// so a key can only be minted by whoever sold the license.
    public static let publicKeyBase64 = "pKNmPGVE6RIMGq9gLa0268V4iXH/L/JvzWk/AYORr9Q="

    /// A key is `payload.signature`, both base64url: small enough to paste, offline to check,
    /// and it carries the buyer's email so a leaked key is traceable to whoever leaked it.
    public static func verify(_ raw: String) -> LicenseInfo? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let payload = decodeBase64URL(parts[0]),
              let signature = decodeBase64URL(parts[1]),
              let keyData = Data(base64Encoded: publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              key.isValidSignature(signature, for: payload) else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(LicenseInfo.self, from: payload)
    }

    public static func state(license: LicenseInfo?, firstRun: Date, now: Date = Date()) -> LicenseState {
        if let license { return .licensed(license) }
        let elapsed = now.timeIntervalSince(firstRun)
        let left = trialDays - Int(elapsed / 86_400)
        return left > 0 ? .trial(daysLeft: left) : .trialExpired
    }

    /// Forces a configuration back inside the free tier. Called by the daemon rather than the UI so
    /// the same rules apply however the configuration arrives.
    public static func clamp(_ config: inout ChargeConfiguration, to features: FeatureSet) {
        if !features.customLimit { config.limit = FeatureSet.freeTierLimit }
        if !features.sailingMode { config.sailingEnabled = false }
        if !features.discharge {
            config.discharge = nil
            config.dischargeToLimitAutomatically = false
        }
        if !features.calibration { config.calibration = nil }
        if !features.schedules {
            config.scheduledTopUp.enabled = false
            config.topUp = nil
        }
        if !features.heatProtection { config.heatProtectionEnabled = false }
    }

    static func decodeBase64URL(_ string: String) -> Data? {
        var s = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        return Data(base64Encoded: s)
    }

    public static func encodeBase64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
