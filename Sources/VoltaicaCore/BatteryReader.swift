import Foundation
import IOKit
import IOKit.ps

/// Samples `AppleSmartBattery` from the IO registry. No privileges required.
public final class BatteryReader {
    public init() {}

    private static let unknownTime = 65535

    public func read() -> BatterySnapshot {
        var snapshot = BatterySnapshot()
        guard let properties = Self.registryProperties() else { return snapshot }

        snapshot.isPresent = properties["BatteryInstalled"] as? Bool ?? false
        snapshot.percentage = properties["CurrentCapacity"] as? Int ?? 0
        snapshot.isCharging = properties["IsCharging"] as? Bool ?? false
        snapshot.isPluggedIn = properties["ExternalConnected"] as? Bool ?? false
        snapshot.isFullyCharged = properties["FullyCharged"] as? Bool ?? false

        snapshot.rawCurrentCapacity = properties["AppleRawCurrentCapacity"] as? Int ?? 0
        snapshot.rawMaxCapacity = properties["AppleRawMaxCapacity"] as? Int ?? 0
        snapshot.nominalCapacity = properties["NominalChargeCapacity"] as? Int ?? 0
        snapshot.designCapacity = properties["DesignCapacity"] as? Int ?? 0
        snapshot.designCycleCount = properties["DesignCycleCount9C"] as? Int ?? 0
        snapshot.cycleCount = properties["CycleCount"] as? Int ?? 0
        snapshot.cellDisconnectCount = properties["BatteryCellDisconnectCount"] as? Int ?? 0

        if snapshot.rawMaxCapacity > 0 {
            snapshot.rawPercentage = min(100, Double(snapshot.rawCurrentCapacity) / Double(snapshot.rawMaxCapacity) * 100)
        } else {
            snapshot.rawPercentage = Double(snapshot.percentage)
        }

        if let centi = properties["Temperature"] as? Int, centi > 0 {
            snapshot.temperature = Double(centi) / 100
        } else if let virtual = properties["VirtualTemperature"] as? Int, virtual > 0 {
            snapshot.temperature = Double(virtual) / 100
        }

        snapshot.voltage = Double(properties["AppleRawBatteryVoltage"] as? Int ?? properties["Voltage"] as? Int ?? 0) / 1000
        snapshot.amperage = Double(properties["Amperage"] as? Int ?? 0)
        if snapshot.amperage == 0, let instant = properties["InstantAmperage"] as? Int {
            snapshot.amperage = Double(instant)
        }

        snapshot.serial = properties["Serial"] as? String ?? ""
        snapshot.gasGauge = properties["DeviceName"] as? String ?? ""

        if let failure = properties["PermanentFailureStatus"] as? Int, failure != 0 {
            snapshot.permanentFailure = "Status \(failure)"
        }

        snapshot.minutesToFull = Self.minutes(properties["AvgTimeToFull"] as? Int)
        snapshot.minutesToEmpty = Self.minutes(properties["AvgTimeToEmpty"] as? Int)
        if snapshot.minutesToEmpty == nil, let remaining = properties["TimeRemaining"] as? Int, !snapshot.isCharging {
            snapshot.minutesToEmpty = Self.minutes(remaining)
        }

        if snapshot.isPluggedIn, let details = properties["AdapterDetails"] as? [String: Any] {
            var adapter = AdapterInfo()
            adapter.watts = details["Watts"] as? Int ?? 0
            adapter.voltage = Double(details["AdapterVoltage"] as? Int ?? 0) / 1000
            adapter.current = Double(details["Current"] as? Int ?? 0) / 1000
            adapter.name = (details["Name"] as? String) ?? (details["Description"] as? String) ?? ""
            adapter.isWireless = details["IsWireless"] as? Bool ?? false
            snapshot.adapter = adapter
        }

        if let charger = properties["ChargerData"] as? [String: Any] {
            snapshot.notChargingReason = UInt32(truncatingIfNeeded: charger["NotChargingReason"] as? Int ?? 0)
            snapshot.chargerInhibitReason = UInt32(truncatingIfNeeded: charger["ChargerInhibitReason"] as? Int ?? 0)
            snapshot.chargingCurrent = Double(charger["ChargingCurrent"] as? Int ?? 0)
            snapshot.chargingVoltage = Double(charger["ChargingVoltage"] as? Int ?? 0) / 1000
        }

        if let telemetry = properties["PowerTelemetryData"] as? [String: Any] {
            snapshot.systemPowerIn = Double(telemetry["SystemPowerIn"] as? Int ?? 0) / 1000
            snapshot.adapterEfficiencyLoss = Double(telemetry["AdapterEfficiencyLoss"] as? Int ?? 0) / 1000
        }

        if let data = properties["BatteryData"] as? [String: Any] {
            if let cells = data["CellVoltage"] as? [Int] {
                snapshot.cellVoltages = cells.map { Double($0) / 1000 }
            }
            snapshot.dailyMinSoc = data["DailyMinSoc"] as? Int ?? 0
            snapshot.dailyMaxSoc = data["DailyMaxSoc"] as? Int ?? 0
            if snapshot.cycleCount == 0 { snapshot.cycleCount = data["CycleCount"] as? Int ?? 0 }
            if snapshot.designCapacity == 0 { snapshot.designCapacity = data["DesignCapacity"] as? Int ?? 0 }
            if let lifetime = data["LifetimeData"] as? [String: Any] {
                snapshot.lifetimeMaxTemperature = Double(lifetime["MaximumTemperature"] as? Int ?? 0)
                snapshot.lifetimeAvgTemperature = Double(lifetime["AverageTemperature"] as? Int ?? 0) / 10
                snapshot.totalOperatingHours = lifetime["TotalOperatingTime"] as? Int ?? 0
            }
        }

        return snapshot
    }

    /// True when the Mac has no internal battery at all (a Mac mini, or a desktop).
    public var hasBattery: Bool {
        guard let properties = Self.registryProperties() else { return false }
        return properties["BatteryInstalled"] as? Bool ?? false
    }

    private static func minutes(_ raw: Int?) -> Int? {
        guard let raw, raw > 0, raw != unknownTime else { return nil }
        return raw
    }

    private static func registryProperties() -> [String: Any]? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }

        var unmanaged: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &unmanaged, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dictionary = unmanaged?.takeRetainedValue() as? [String: Any] else { return nil }
        return dictionary
    }
}
