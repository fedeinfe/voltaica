import Foundation

public enum PolicyMode: String, Codable, Sendable {
    case noBattery
    case disabled
    case onBattery
    case charging
    case holding
    case topUp
    case discharging
    case heatPaused
    case paused
    case calibrating

    public var label: String {
        switch self {
        case .noBattery: return "No battery"
        case .disabled: return "Limit off"
        case .onBattery: return "On battery"
        case .charging: return "Charging"
        case .holding: return "Holding"
        case .topUp: return "Topping up"
        case .discharging: return "Discharging"
        case .heatPaused: return "Cooling down"
        case .paused: return "Paused"
        case .calibrating: return "Calibrating"
        }
    }
}

/// Something worth telling the user about, emitted once on transition.
public enum PolicyEvent: String, Codable, Sendable {
    case limitReached
    case chargingResumed
    case topUpFinished
    case dischargeFinished
    case heatPauseStarted
    case heatPauseEnded
    case calibrationAdvanced
    case calibrationFinished
}

public struct PolicyDecision: Codable, Sendable, Equatable {
    public var chargingAllowed: Bool = true
    public var adapterEnabled: Bool = true
    public var mode: PolicyMode = .disabled
    public var detail: String = ""
    public var magSafeLED: MagSafeLED = .system
    public var events: [PolicyEvent] = []

    public init() {}
}

/// Decides what the charger should be doing. Pure, deterministic and fully unit tested: the
/// daemon feeds it a snapshot and applies whatever comes back.
public struct PolicyEngine: Sendable {
    /// Below this the Mac charges no matter what the policy says.
    public static let emergencyFloor: Double = 5
    /// Never cut the adapter below this, whatever the user asked for.
    public static let absoluteDischargeFloor: Double = 15

    public var isHolding = false
    public var isHeatPaused = false
    public var isDischarging = false
    private var lastMode: PolicyMode = .disabled

    public init() {}

    public mutating func evaluate(config: inout ChargeConfiguration,
                                  snapshot: BatterySnapshot,
                                  now: Date = Date()) -> PolicyDecision {
        var decision = PolicyDecision()
        let charge = snapshot.rawPercentage
        let limit = Double(config.clampedLimit)

        // Hysteresis is tracked regardless of what else is going on, so unplugging and
        // plugging back in does not restart a charge cycle the user did not ask for.
        if charge >= limit {
            isHolding = true
        } else if !config.sailingEnabled || charge <= limit - Double(config.sailingDepth) {
            isHolding = false
        }

        guard snapshot.isPresent else {
            decision.mode = .noBattery
            decision.detail = "No internal battery"
            return finish(decision, config: &config)
        }

        if config.enabled, config.clampedLimit < 100, snapshot.isPluggedIn, charge >= limit,
           lastMode == .charging || lastMode == .topUp {
            decision.events.append(.limitReached)
        }

        guard snapshot.isPluggedIn else {
            isDischarging = false
            config.discharge = nil
            decision.mode = .onBattery
            decision.detail = "Running on battery"
            return finish(decision, config: &config)
        }

        if charge <= Self.emergencyFloor {
            decision.mode = .charging
            decision.detail = "Battery critically low, charging"
            decision.magSafeLED = .amber
            return finish(decision, config: &config)
        }

        if var session = config.calibration, session.isActive {
            let result = advanceCalibration(&session, snapshot: snapshot, now: now)
            config.calibration = session.isActive ? session : nil
            if !session.isActive {
                decision.events.append(.calibrationFinished)
            }
            return finish(result, config: &config)
        }

        if let until = config.pauseUntil, now < until {
            decision.chargingAllowed = false
            decision.mode = .paused
            decision.detail = "Charging paused"
            decision.magSafeLED = .green
            return finish(decision, config: &config)
        }
        if let until = config.pauseUntil, now >= until { config.pauseUntil = nil }

        guard config.enabled else {
            decision.mode = .charging
            decision.detail = "Charge limit off"
            return finish(decision, config: &config)
        }

        if config.heatProtectionEnabled,
           snapshot.temperature > 0,
           charge > Double(config.heatProtectionFloor) {
            let threshold = config.heatThreshold
            // A degree of hysteresis, otherwise the charger stutters around the threshold.
            let resume = threshold - 1.5
            if snapshot.temperature >= threshold { isHeatPaused = true }
            else if snapshot.temperature <= resume { isHeatPaused = false }

            if isHeatPaused {
                decision.chargingAllowed = false
                decision.mode = .heatPaused
                decision.detail = String(format: "Battery at %.1f°C, waiting to cool", snapshot.temperature)
                decision.magSafeLED = .green
                if lastMode != .heatPaused { decision.events.append(.heatPauseStarted) }
                return finish(decision, config: &config)
            }
        } else {
            isHeatPaused = false
        }
        if lastMode == .heatPaused, !isHeatPaused { decision.events.append(.heatPauseEnded) }

        if let request = config.topUp {
            if request.isExpired(now: now) {
                config.topUp = nil
            } else if charge >= Double(request.target) - 0.5 {
                config.topUp = nil
                decision.events.append(.topUpFinished)
                isHolding = true
            } else {
                decision.mode = .topUp
                decision.detail = "Charging to \(request.target)%"
                decision.magSafeLED = .amber
                return finish(decision, config: &config)
            }
        }

        if config.scheduledTopUp.isWithinWindow(now), charge < Double(config.scheduledTopUp.target) {
            decision.mode = .topUp
            decision.detail = "Scheduled top-up before \(config.scheduledTopUp.timeLabel)"
            decision.magSafeLED = .amber
            return finish(decision, config: &config)
        }

        let dischargeTarget = dischargeTarget(config: config, limit: limit)
        if let target = dischargeTarget {
            let floor = max(Self.absoluteDischargeFloor, Double(config.dischargeFloor))
            if charge > max(target, floor) + 0.5 {
                isDischarging = true
                decision.adapterEnabled = false
                decision.mode = .discharging
                decision.detail = String(format: "Running down to %.0f%%", max(target, floor))
                decision.magSafeLED = .off
                return finish(decision, config: &config)
            } else if isDischarging {
                isDischarging = false
                if config.discharge != nil {
                    config.discharge = nil
                    decision.events.append(.dischargeFinished)
                }
            }
        } else {
            isDischarging = false
        }

        if config.clampedLimit >= 100 {
            decision.mode = snapshot.isFullyCharged ? .holding : .charging
            decision.detail = snapshot.isFullyCharged ? "Fully charged" : "Charging to 100%"
            decision.magSafeLED = snapshot.isFullyCharged ? .green : .amber
            return finish(decision, config: &config)
        }

        if isHolding {
            decision.chargingAllowed = false
            decision.mode = .holding
            decision.detail = "Held at \(config.clampedLimit)%"
            decision.magSafeLED = .green
        } else {
            decision.mode = .charging
            decision.detail = "Charging to \(config.clampedLimit)%"
            decision.magSafeLED = .amber
            if lastMode == .holding { decision.events.append(.chargingResumed) }
        }
        return finish(decision, config: &config)
    }

    private func dischargeTarget(config: ChargeConfiguration, limit: Double) -> Double? {
        if let request = config.discharge { return Double(request.target) }
        if config.dischargeToLimitAutomatically, config.clampedLimit < 100 { return limit }
        return nil
    }

    // MARK: - Calibration

    private mutating func advanceCalibration(_ session: inout CalibrationSession,
                                             snapshot: BatterySnapshot,
                                             now: Date) -> PolicyDecision {
        var decision = PolicyDecision()
        decision.mode = .calibrating
        let charge = snapshot.rawPercentage

        switch session.phase {
        case .chargingToFull:
            decision.detail = "Calibration: charging to 100%"
            decision.magSafeLED = .amber
            if snapshot.isFullyCharged || charge >= 99.5 {
                session.phase = .soaking
                session.phaseStartedAt = now
                decision.events.append(.calibrationAdvanced)
            }
        case .soaking:
            decision.detail = "Calibration: holding at full"
            decision.magSafeLED = .green
            if now.timeIntervalSince(session.phaseStartedAt) >= Double(session.soakMinutes) * 60 {
                session.phase = .discharging
                session.phaseStartedAt = now
                decision.events.append(.calibrationAdvanced)
            }
        case .discharging:
            let floor = max(Self.absoluteDischargeFloor, Double(session.dischargeTarget))
            decision.detail = String(format: "Calibration: running down to %.0f%%", floor)
            decision.magSafeLED = .off
            if charge > floor + 0.5 {
                decision.adapterEnabled = false
            } else {
                session.phase = .recharging
                session.phaseStartedAt = now
                decision.events.append(.calibrationAdvanced)
            }
        case .recharging:
            decision.detail = "Calibration: charging back to 100%"
            decision.magSafeLED = .amber
            if snapshot.isFullyCharged || charge >= 99.5 {
                session.phase = .finished
                session.phaseStartedAt = now
            }
        case .finished:
            decision.mode = .charging
        }
        return decision
    }

    private mutating func finish(_ decision: PolicyDecision, config: inout ChargeConfiguration) -> PolicyDecision {
        var decision = decision
        if !config.magSafeFeedbackEnabled { decision.magSafeLED = .system }
        lastMode = decision.mode
        return decision
    }
}
