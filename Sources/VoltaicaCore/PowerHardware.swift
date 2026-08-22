import Foundation

/// The SMC keys Voltaica touches, and what they mean.
///
/// Everything here is public knowledge from the SMC key space that ships on every Mac; the
/// values are the ones the community has documented for the charger endpoint. Keys that a
/// given Mac does not expose simply fail with `keyNotFound` and the feature is hidden.
public enum SMCKeys {
    /// Charging inhibit, primary. `0x00` lets the charger run, `0x02` stops it.
    public static let chargeInhibitA: SMCKey = "CH0B"
    /// Charging inhibit, secondary. Both have to be set on Apple Silicon.
    public static let chargeInhibitB: SMCKey = "CH0C"
    /// Power adapter cut-off. `0x01` makes the Mac ignore wall power and run off the battery.
    public static let adapterInhibit: SMCKey = "CH0I"
    /// Firmware level 80% ceiling. Survives reboots and works with no software running.
    public static let hardwareCeiling: SMCKey = "CHWA"
    /// MagSafe status light. 0 system, 1 off, 3 amber, 4 green.
    public static let magSafeLED: SMCKey = "ACLC"
    /// Intel only percentage ceiling enforced by the SMC itself (20...100).
    public static let intelCeiling: SMCKey = "BCLM"
    /// Intel adapter enable, inverse of `CH0I`.
    public static let intelAdapterEnable: SMCKey = "ACEN"
    /// Battery pack temperature, in °C.
    public static let batteryTemperature: SMCKey = "TB0T"
    /// Charger current, in mA.
    public static let chargerCurrent: SMCKey = "CHBI"
    /// Charger voltage, in mV.
    public static let chargerVoltage: SMCKey = "CHBV"
}

public enum MagSafeLED: Int, Codable, Sendable, CaseIterable {
    case system = 0
    case off = 1
    case amber = 3
    case green = 4

    public var label: String {
        switch self {
        case .system: return "System"
        case .off: return "Off"
        case .amber: return "Amber"
        case .green: return "Green"
        }
    }
}

/// What the charger hardware is doing right now.
public struct HardwarePowerState: Codable, Sendable, Equatable {
    public var chargingAllowed: Bool
    public var adapterEnabled: Bool
    public var hardwareCeilingEnabled: Bool?
    public var intelCeiling: Int?

    public init(chargingAllowed: Bool,
                adapterEnabled: Bool,
                hardwareCeilingEnabled: Bool? = nil,
                intelCeiling: Int? = nil) {
        self.chargingAllowed = chargingAllowed
        self.adapterEnabled = adapterEnabled
        self.hardwareCeilingEnabled = hardwareCeilingEnabled
        self.intelCeiling = intelCeiling
    }
}

/// Which SMC dialect this Mac speaks.
public enum Platform: String, Codable, Sendable {
    case appleSilicon
    case intel

    public static let current: Platform = {
        #if arch(arm64)
        return .appleSilicon
        #else
        return .intel
        #endif
    }()
}

/// Capabilities probed once at start-up, so the UI only offers what the Mac can do.
public struct HardwareCapabilities: Codable, Sendable, Equatable {
    public init(platform: Platform,
                canInhibitCharging: Bool,
                canCutAdapter: Bool,
                hasHardwareCeiling: Bool,
                hasMagSafeLED: Bool,
                hasIntelCeiling: Bool) {
        self.platform = platform
        self.canInhibitCharging = canInhibitCharging
        self.canCutAdapter = canCutAdapter
        self.hasHardwareCeiling = hasHardwareCeiling
        self.hasMagSafeLED = hasMagSafeLED
        self.hasIntelCeiling = hasIntelCeiling
    }

    public var platform: Platform
    public var canInhibitCharging: Bool
    public var canCutAdapter: Bool
    public var hasHardwareCeiling: Bool
    public var hasMagSafeLED: Bool
    public var hasIntelCeiling: Bool

    public static let unknown = HardwareCapabilities(platform: .current,
                                                     canInhibitCharging: false,
                                                     canCutAdapter: false,
                                                     hasHardwareCeiling: false,
                                                     hasMagSafeLED: false,
                                                     hasIntelCeiling: false)
}

/// Semantic wrapper over the charger keys. Root only, single threaded.
public final class PowerHardware {
    private let smc: SMCConnection
    public let capabilities: HardwareCapabilities

    private static let inhibitValue: UInt8 = 0x02
    private static let allowValue: UInt8 = 0x00

    public init(smc: SMCConnection) {
        self.smc = smc
        var caps = HardwareCapabilities.unknown
        caps.platform = .current
        caps.canInhibitCharging = smc.exists(SMCKeys.chargeInhibitA) || smc.exists(SMCKeys.chargeInhibitB)
        caps.canCutAdapter = smc.exists(SMCKeys.adapterInhibit) || smc.exists(SMCKeys.intelAdapterEnable)
        caps.hasHardwareCeiling = smc.exists(SMCKeys.hardwareCeiling)
        caps.hasMagSafeLED = smc.exists(SMCKeys.magSafeLED)
        caps.hasIntelCeiling = smc.exists(SMCKeys.intelCeiling)
        self.capabilities = caps
    }

    // MARK: - Charging

    public func setChargingAllowed(_ allowed: Bool) throws {
        let value = allowed ? Self.allowValue : Self.inhibitValue
        var firstError: Error?
        for key in [SMCKeys.chargeInhibitA, SMCKeys.chargeInhibitB] where smc.exists(key) {
            do { try smc.writeUInt8(key, value) } catch { firstError = firstError ?? error }
        }
        if let firstError { throw firstError }
    }

    public func chargingAllowed() throws -> Bool {
        for key in [SMCKeys.chargeInhibitA, SMCKeys.chargeInhibitB] where smc.exists(key) {
            if try smc.readUInt8(key) != Self.allowValue { return false }
        }
        return true
    }

    // MARK: - Adapter

    /// Cutting the adapter is how the Mac discharges while still plugged in.
    public func setAdapterEnabled(_ enabled: Bool) throws {
        if smc.exists(SMCKeys.adapterInhibit) {
            try smc.writeUInt8(SMCKeys.adapterInhibit, enabled ? 0x00 : 0x01)
        } else if smc.exists(SMCKeys.intelAdapterEnable) {
            try smc.writeUInt8(SMCKeys.intelAdapterEnable, enabled ? 0x01 : 0x00)
        } else {
            throw SMCError.keyNotFound(SMCKeys.adapterInhibit.name)
        }
    }

    public func adapterEnabled() throws -> Bool {
        if smc.exists(SMCKeys.adapterInhibit) {
            return try smc.readUInt8(SMCKeys.adapterInhibit) == 0x00
        }
        if smc.exists(SMCKeys.intelAdapterEnable) {
            return try smc.readUInt8(SMCKeys.intelAdapterEnable) == 0x01
        }
        return true
    }

    // MARK: - Firmware ceiling

    public func setHardwareCeiling(_ enabled: Bool) throws {
        guard capabilities.hasHardwareCeiling else { throw SMCError.keyNotFound(SMCKeys.hardwareCeiling.name) }
        try smc.writeUInt8(SMCKeys.hardwareCeiling, enabled ? 0x01 : 0x00)
    }

    public func hardwareCeilingEnabled() throws -> Bool {
        guard capabilities.hasHardwareCeiling else { return false }
        return try smc.readUInt8(SMCKeys.hardwareCeiling) != 0
    }

    /// Intel Macs can clamp the charge percentage in firmware. Apple Silicon cannot.
    public func setIntelCeiling(_ percent: Int) throws {
        guard capabilities.hasIntelCeiling else { throw SMCError.keyNotFound(SMCKeys.intelCeiling.name) }
        try smc.writeUInt8(SMCKeys.intelCeiling, UInt8(clamping: percent))
    }

    public func intelCeiling() throws -> Int? {
        guard capabilities.hasIntelCeiling else { return nil }
        return Int(try smc.readUInt8(SMCKeys.intelCeiling))
    }

    // MARK: - MagSafe light

    public func setMagSafeLED(_ led: MagSafeLED) throws {
        guard capabilities.hasMagSafeLED else { throw SMCError.keyNotFound(SMCKeys.magSafeLED.name) }
        try smc.writeUInt8(SMCKeys.magSafeLED, UInt8(led.rawValue))
    }

    // MARK: - Telemetry

    public func batteryTemperature() -> Double? {
        try? smc.readNumber(SMCKeys.batteryTemperature)
    }

    public func chargerWatts() -> Double? {
        guard let mA = try? smc.readNumber(SMCKeys.chargerCurrent),
              let mV = try? smc.readNumber(SMCKeys.chargerVoltage) else { return nil }
        return mA * mV / 1_000_000
    }

    // MARK: - Composite

    public func readState() -> HardwarePowerState {
        HardwarePowerState(chargingAllowed: (try? chargingAllowed()) ?? true,
                           adapterEnabled: (try? adapterEnabled()) ?? true,
                           hardwareCeilingEnabled: capabilities.hasHardwareCeiling ? try? hardwareCeilingEnabled() : nil,
                           intelCeiling: try? intelCeiling() ?? nil)
    }

    /// Hands the charger back to macOS. Called on uninstall, on daemon shutdown and any time
    /// the policy is turned off, so a stopped daemon can never leave a Mac that will not charge.
    public func releaseControl() {
        try? setChargingAllowed(true)
        if capabilities.canCutAdapter { try? setAdapterEnabled(true) }
        if capabilities.hasMagSafeLED { try? setMagSafeLED(.system) }
    }

    public func dumpRaw(prefix: String) -> [String: String] {
        guard let keys = try? smc.allKeys() else { return [:] }
        let names = keys.map(\.name).filter { prefix.isEmpty || $0.hasPrefix(prefix) }
        return readRaw(keys: names)
    }

    public func readRaw(keys: [String]) -> [String: String] {
        var out: [String: String] = [:]
        for name in keys where name.utf8.count == 4 {
            let key = SMCKey(name)
            guard let meta = try? smc.info(for: key), let bytes = try? smc.readBytes(key) else { continue }
            let hex = bytes.map { String(format: "%02x", $0) }.joined()
            let big = SMCConnection.decodeNumber(bytes: bytes, type: meta.type, order: .big)
            let little = SMCConnection.decodeNumber(bytes: bytes, type: meta.type, order: .little)
            var line = "\(meta.type) \(hex)"
            if let big { line += " = \(big)" }
            if let little, let big, little != big { line += " | LE \(little)" }
            out[name] = line
        }
        return out
    }
}
