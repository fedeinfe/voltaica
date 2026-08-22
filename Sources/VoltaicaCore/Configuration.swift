import Foundation

/// The whole user-facing policy, in one Codable value.
///
/// The app sends this to the daemon; the daemon persists it and keeps enforcing it even when
/// the app is not running, so a charge limit survives a logout or a crash of the UI.
public struct ChargeConfiguration: Codable, Sendable, Equatable {
    public var enabled: Bool = true
    /// Where charging stops, as a percentage of the pack's real capacity.
    public var limit: Int = 80

    /// Sailing keeps the charger off while the pack drifts down, instead of nudging it back up
    /// every fraction of a percent. That is what actually saves cycles.
    public var sailingEnabled: Bool = true
    public var sailingDepth: Int = 5

    public var heatProtectionEnabled: Bool = true
    public var heatThreshold: Double = 38
    /// Heat protection never strands a nearly empty battery.
    public var heatProtectionFloor: Int = 25

    /// Cutting the adapter to walk the charge back down to the limit, instead of waiting.
    public var dischargeToLimitAutomatically: Bool = false
    public var dischargeFloor: Int = 20

    /// Firmware ceiling (`CHWA`): roughly 80%, enforced by the Mac itself even with no
    /// software running. Coarse, but it keeps working if Voltaica is ever removed.
    public var hardwareCeilingEnabled: Bool = false

    public var magSafeFeedbackEnabled: Bool = false

    public var scheduledTopUp = TopUpSchedule()
    public var calibrationReminderDays: Int = 60
    public var calibrationRemindersEnabled: Bool = true

    /// Transient requests. The daemon clears them once satisfied.
    public var topUp: TopUpRequest?
    public var discharge: DischargeRequest?
    public var pauseUntil: Date?
    public var calibration: CalibrationSession?

    /// Notifications the daemon-driven events raise through the app.
    public var notificationsEnabled: Bool = true

    public init() {}

    public var clampedLimit: Int { min(100, max(20, limit)) }

    public var isLimitActive: Bool { enabled && clampedLimit < 100 }

    /// Guards against a config that would let the pack run down to nothing on the desk.
    public func validated() -> ChargeConfiguration {
        var copy = self
        copy.limit = clampedLimit
        copy.sailingDepth = min(20, max(1, sailingDepth))
        copy.heatThreshold = min(50, max(30, heatThreshold))
        copy.dischargeFloor = min(90, max(15, dischargeFloor))
        copy.heatProtectionFloor = min(80, max(10, heatProtectionFloor))
        copy.calibrationReminderDays = min(180, max(14, calibrationReminderDays))
        if let topUp = copy.topUp { copy.topUp = topUp.validated() }
        if let discharge = copy.discharge {
            copy.discharge = discharge.validated(floor: copy.dischargeFloor)
        }
        return copy
    }
}

/// A one shot "charge to full now", with an optional deadline so a forgotten request expires.
public struct TopUpRequest: Codable, Sendable, Equatable {
    public var target: Int
    public var requestedAt: Date
    public var expiresAt: Date?

    public init(target: Int = 100, requestedAt: Date = Date(), expiresAt: Date? = nil) {
        self.target = target
        self.requestedAt = requestedAt
        self.expiresAt = expiresAt
    }

    public func validated() -> TopUpRequest {
        var copy = self
        copy.target = min(100, max(30, target))
        return copy
    }

    public func isExpired(now: Date) -> Bool {
        guard let expiresAt else { return false }
        return now >= expiresAt
    }
}

/// Run the pack down to a target while still plugged in, by cutting the adapter.
public struct DischargeRequest: Codable, Sendable, Equatable {
    public var target: Int
    public var requestedAt: Date

    public init(target: Int, requestedAt: Date = Date()) {
        self.target = target
        self.requestedAt = requestedAt
    }

    public func validated(floor: Int) -> DischargeRequest {
        var copy = self
        copy.target = min(99, max(floor, target))
        return copy
    }
}

/// "Have it full by 8:30 on weekdays" — charging starts early enough to reach 100% by then.
public struct TopUpSchedule: Codable, Sendable, Equatable {
    public var enabled: Bool = false
    public var hour: Int = 8
    public var minute: Int = 30
    /// 1 = Sunday, matching `Calendar.component(.weekday)`.
    public var weekdays: Set<Int> = [2, 3, 4, 5, 6]
    public var target: Int = 100
    /// How long before the deadline charging is allowed to start.
    public var leadMinutes: Int = 90

    public init() {}

    public func isWithinWindow(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = components.weekday,
              let hour = components.hour,
              let minute = components.minute else { return false }
        guard weekdays.contains(weekday) else { return false }
        let nowMinutes = hour * 60 + minute
        let deadline = self.hour * 60 + self.minute
        return nowMinutes >= deadline - leadMinutes && nowMinutes <= deadline
    }

    public var timeLabel: String {
        String(format: "%02d:%02d", hour, minute)
    }
}

/// A guided full charge, soak, deep discharge and recharge, to resync the gas gauge.
public struct CalibrationSession: Codable, Sendable, Equatable {
    public enum Phase: String, Codable, Sendable {
        case chargingToFull
        case soaking
        case discharging
        case recharging
        case finished

        public var label: String {
            switch self {
            case .chargingToFull: return "Charging to 100%"
            case .soaking: return "Holding at full"
            case .discharging: return "Running down"
            case .recharging: return "Charging back up"
            case .finished: return "Finished"
            }
        }
    }

    public var phase: Phase = .chargingToFull
    public var startedAt: Date = Date()
    public var phaseStartedAt: Date = Date()
    public var dischargeTarget: Int = 15
    public var soakMinutes: Int = 60

    public init() {}

    public var isActive: Bool { phase != .finished }
}

/// Recorded after a calibration completes, to drive the reminder.
public struct CalibrationHistory: Codable, Sendable, Equatable {
    public var lastCompleted: Date?
    public init(lastCompleted: Date? = nil) { self.lastCompleted = lastCompleted }

    public func isDue(now: Date, everyDays: Int) -> Bool {
        guard let lastCompleted else { return false }
        return now.timeIntervalSince(lastCompleted) > Double(everyDays) * 86_400
    }
}
