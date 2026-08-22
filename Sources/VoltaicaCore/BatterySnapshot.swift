import Foundation

/// Everything Voltaica knows about the battery at one instant.
///
/// Sampled from `AppleSmartBattery` in the IO registry, which needs no privileges at all —
/// only the charger *writes* require root.
public struct BatterySnapshot: Codable, Sendable, Equatable {
    public var timestamp: Date = Date()

    // Charge
    /// What macOS shows in the menu bar: rounded, and pinned to 100% while trickle charging.
    public var percentage: Int = 0
    /// The unrounded figure straight off the gas gauge. This is the one a charge limit acts on.
    public var rawPercentage: Double = 0
    public var isCharging: Bool = false
    public var isPluggedIn: Bool = false
    public var isFullyCharged: Bool = false
    public var isPresent: Bool = false

    // Health
    public var cycleCount: Int = 0
    public var designCycleCount: Int = 0
    public var designCapacity: Int = 0
    public var nominalCapacity: Int = 0
    public var rawMaxCapacity: Int = 0
    public var rawCurrentCapacity: Int = 0
    public var cellDisconnectCount: Int = 0
    public var permanentFailure: String?

    // Electrical
    public var temperature: Double = 0
    public var voltage: Double = 0
    public var amperage: Double = 0
    public var cellVoltages: [Double] = []
    public var systemPowerIn: Double = 0
    public var adapterEfficiencyLoss: Double = 0

    // Timing
    public var minutesToFull: Int?
    public var minutesToEmpty: Int?

    // Adapter
    public var adapter: AdapterInfo?

    // Identity
    public var serial: String = ""
    public var gasGauge: String = ""

    // Charger diagnostics
    public var notChargingReason: UInt32 = 0
    public var chargerInhibitReason: UInt32 = 0
    public var chargingCurrent: Double = 0
    public var chargingVoltage: Double = 0

    // Long term counters the gauge keeps by itself
    public var dailyMinSoc: Int = 0
    public var dailyMaxSoc: Int = 0
    public var lifetimeMaxTemperature: Double = 0
    public var lifetimeAvgTemperature: Double = 0
    public var totalOperatingHours: Int = 0

    public init() {}

    /// Apple's own health figure: how much charge the pack still nominally holds.
    public var healthPercent: Double {
        guard designCapacity > 0 else { return 0 }
        let capacity = nominalCapacity > 0 ? nominalCapacity : rawMaxCapacity
        return min(100, Double(capacity) / Double(designCapacity) * 100)
    }

    /// The stricter figure, measured rather than nominal. Usually a few points lower.
    public var measuredHealthPercent: Double {
        guard designCapacity > 0, rawMaxCapacity > 0 else { return 0 }
        return min(100, Double(rawMaxCapacity) / Double(designCapacity) * 100)
    }

    /// Positive while charging, negative while running off the battery, in watts.
    public var watts: Double { voltage * amperage / 1000 }

    public var isDischargingOnAdapter: Bool { isPluggedIn && amperage < -50 }

    public var temperatureIsElevated: Bool { temperature >= 35 }

    public var adapterDescription: String {
        guard let adapter, isPluggedIn else { return "Not connected" }
        return adapter.summary
    }
}

public struct AdapterInfo: Codable, Sendable, Equatable {
    public init() {}

    public var watts: Int = 0
    public var voltage: Double = 0
    public var current: Double = 0
    public var name: String = ""
    public var isWireless: Bool = false

    public var summary: String {
        var parts: [String] = []
        if watts > 0 { parts.append("\(watts)W") }
        if voltage > 0 && current > 0 {
            parts.append(String(format: "%.0fV / %.1fA", voltage, current))
        }
        if !name.isEmpty { parts.append(name) }
        return parts.isEmpty ? "Connected" : parts.joined(separator: " · ")
    }
}

/// Why the SMC says it is not charging. The bit meanings are not documented by Apple, so the
/// UI shows the ones the community agrees on and falls back to the raw value.
public enum NotChargingReason {
    public static func describe(_ mask: UInt32) -> [String] {
        guard mask != 0 else { return [] }
        var reasons: [String] = []
        let known: [(UInt32, String)] = [
            (1 << 0, "Battery full"),
            (1 << 1, "Waiting for charger"),
            (1 << 2, "Charger not capable"),
            (1 << 3, "Cell voltage limit"),
            (1 << 4, "Temperature out of range"),
            (1 << 5, "Charger fault"),
            (1 << 6, "Battery fault"),
            (1 << 7, "Charge inhibited"),
            (1 << 8, "Voltage out of range"),
            (1 << 14, "Optimised charging"),
            (1 << 22, "Software charge limit"),
        ]
        for (bit, label) in known where mask & bit != 0 { reasons.append(label) }
        if reasons.isEmpty { reasons.append("Reason 0x" + String(mask, radix: 16)) }
        return reasons
    }
}
