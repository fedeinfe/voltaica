import Foundation
import IOKit
import IOKit.pwr_mgt
import VoltaicaCore
import os

/// The daemon's brain: samples the battery, asks the engine what should happen and pushes the
/// answer into the SMC. Everything runs on one serial queue, which is also the only thread
/// that ever touches the SMC connection.
final class PolicyRunner {
    static let shared = PolicyRunner()

    private let log = Logger(subsystem: VoltaicaIdentifiers.helper, category: "policy")
    private let queue = DispatchQueue(label: "\(VoltaicaIdentifiers.helper).policy")
    private let reader = BatteryReader()
    private let store = PolicyStore()

    private var smc: SMCConnection?
    private var hardware: PowerHardware?
    private var engine = PolicyEngine()

    private var configuration = ChargeConfiguration()
    private var license: LicenseInfo?
    private var licenseFirstRun = Date()
    private var history = CalibrationHistory()
    private var lastSnapshot = BatterySnapshot()
    private var lastDecision = PolicyDecision()
    private var lastAppliedState: HardwarePowerState?
    private var lastReassert = Date.distantPast
    private var adapterCutSince: Date?
    private var adapterCutFailedAt: Double?
    private var wasPluggedIn = false
    private var adapterCutVerdict: ControlVerdict = .untested
    private var chargeInhibitVerdict: ControlVerdict = .untested
    private var inhibitIgnoredSince: Date?
    private var lastRealChargeAt: Date?
    private var lastTrim = Date.distantPast
    private var lastError: String?
    private var timer: DispatchSourceTimer?
    private let startedAt = Date()

    /// Even when nothing changes, the charger keys are rewritten this often: other software or
    /// a firmware quirk can reset them behind our back.
    private let reassertInterval: TimeInterval = 60

    /// How long the Mac gets to actually move onto battery power after the adapter is cut.
    private let adapterCutGrace: TimeInterval = 15

    private init() {}

    // MARK: - Lifecycle

    func start() {
        queue.async { [self] in
            store.prepare()
            licenseFirstRun = store.firstRun()
            license = store.loadLicenseKey().flatMap(License.verify)
            configuration = store.loadConfiguration()
            License.clamp(&configuration, to: entitlement)
            history = store.loadHistory()
            openHardware()
            applyHardwareCeiling()
            tick()
            scheduleTimer(interval: 3)
            log.notice("policy runner started, limit \(self.configuration.limit, privacy: .public)%")
        }
    }

    /// Called from the signal handlers. Runs synchronously so the process does not exit first.
    func shutdown(releaseCharger: Bool) {
        queue.sync { [self] in
            timer?.cancel()
            timer = nil
            if releaseCharger { hardware?.releaseControl() }
            smc?.close()
            smc = nil
            hardware = nil
        }
    }

    private func openHardware() {
        do {
            let connection = try SMCConnection()
            smc = connection
            hardware = PowerHardware(smc: connection)
            lastError = nil
            let caps = hardware?.capabilities
            log.notice("""
            SMC ready: inhibit=\(caps?.canInhibitCharging ?? false, privacy: .public) \
            adapter=\(caps?.canCutAdapter ?? false, privacy: .public) \
            ceiling=\(caps?.hasHardwareCeiling ?? false, privacy: .public)
            """)
        } catch {
            lastError = String(describing: error)
            log.error("SMC unavailable: \(String(describing: error), privacy: .public)")
        }
    }

    private func scheduleTimer(interval: TimeInterval) {
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: queue)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(500))
        source.setEventHandler { [weak self] in self?.tick() }
        source.resume()
        timer = source
    }

    // MARK: - Main loop

    /// What the current license or trial allows. Re-derived on every use so a trial expiring
    /// while the daemon runs takes effect without a restart.
    private var entitlement: FeatureSet {
        License.state(license: license, firstRun: licenseFirstRun).features
    }

    private func tick() {
        if smc == nil { openHardware() }
        let snapshot = reader.read()
        lastSnapshot = snapshot

        var config = configuration
        License.clamp(&config, to: entitlement)
        let decision = engine.evaluate(config: &config, snapshot: snapshot)
        let configChanged = config != configuration
        configuration = config
        if configChanged { store.save(configuration) }

        if decision.events.contains(.calibrationFinished) {
            history.lastCompleted = Date()
            store.save(history)
        }

        apply(decision)
        verifyChargeInhibit(decision, snapshot: snapshot)
        verifyAdapterCut(decision, snapshot: snapshot)
        lastDecision = decision

        if !decision.events.isEmpty {
            EventBridge.shared.publish(decision.events, snapshot: snapshot, decision: decision)
        }
        EventBridge.shared.record(snapshot: snapshot, decision: decision)

        if Date().timeIntervalSince(lastTrim) > 3_600 {
            lastTrim = Date()
            EventBridge.shared.trimHistory()
        }
    }

    private func apply(_ decision: PolicyDecision) {
        guard let hardware else { return }
        let desired = HardwarePowerState(chargingAllowed: decision.chargingAllowed,
                                          adapterEnabled: decision.adapterEnabled)
        let expired = Date().timeIntervalSince(lastReassert) > reassertInterval
        guard expired || desired != lastAppliedState else { return }

        do {
            if hardware.capabilities.canInhibitCharging {
                try hardware.setChargingAllowed(decision.chargingAllowed)
            }
            if hardware.capabilities.canCutAdapter {
                // The adapter is only ever cut while a decision explicitly asks for it.
                try hardware.setAdapterEnabled(decision.adapterEnabled)
            }
            if configuration.magSafeFeedbackEnabled, hardware.capabilities.hasMagSafeLED {
                try? hardware.setMagSafeLED(decision.magSafeLED)
            }
            lastAppliedState = desired
            lastReassert = Date()
            lastError = nil
        } catch {
            lastError = String(describing: error)
            log.error("could not apply decision: \(String(describing: error), privacy: .public)")
            smc?.close()
            smc = nil
            self.hardware = nil
        }
    }

    /// Whether the charge inhibit is doing anything can only be settled while the charger would
    /// otherwise be pushing current, so the verdict comes from normal use rather than a synthetic
    /// test: current was flowing, Voltaica said stop, and either it stopped or it did not.
    private func verifyChargeInhibit(_ decision: PolicyDecision, snapshot: BatterySnapshot) {
        let charging = snapshot.isPluggedIn && snapshot.amperage > 100
        if charging { lastRealChargeAt = Date() }
        guard snapshot.isPluggedIn, !decision.chargingAllowed else {
            inhibitIgnoredSince = nil
            return
        }
        if charging {
            let since = inhibitIgnoredSince ?? Date()
            inhibitIgnoredSince = since
            if Date().timeIntervalSince(since) >= adapterCutGrace {
                chargeInhibitVerdict = .ignored
                log.error("charge inhibit accepted but the charger kept pushing current")
            }
            return
        }
        inhibitIgnoredSince = nil
        // Only a charge that was actually running and then stopped proves anything; a battery
        // sitting full draws nothing either way.
        if let last = lastRealChargeAt, Date().timeIntervalSince(last) < 90 {
            chargeInhibitVerdict = .confirmed
        }
    }

    /// Cutting the adapter is a request, not a guarantee: an M1 Pro accepts it, reports the new
    /// charger mode and keeps drawing from the wall regardless. Watching for that beats promising
    /// a discharge that never happens, so the feature switches itself off when the Mac ignores it.
    private func verifyAdapterCut(_ decision: PolicyDecision, snapshot: BatterySnapshot) {
        defer { wasPluggedIn = snapshot.isPluggedIn }
        // Re-arm on a new power source, and again once the pack has come down a few points: the
        // failure seen at 100% may well be the charger refusing to let go of a full battery.
        let rearm = (snapshot.isPluggedIn && !wasPluggedIn)
            || (adapterCutFailedAt.map { snapshot.controlPercentage <= $0 - 5 } ?? false)
        if rearm {
            engine.adapterCutWorks = true
            adapterCutSince = nil
            adapterCutFailedAt = nil
        }
        guard engine.adapterCutWorks, hardware?.capabilities.canCutAdapter == true else { return }
        guard !decision.adapterEnabled, snapshot.isPluggedIn else {
            adapterCutSince = nil
            return
        }
        if snapshot.isDischargingOnAdapter {
            adapterCutSince = nil
            adapterCutVerdict = .confirmed
            return
        }
        let since = adapterCutSince ?? Date()
        adapterCutSince = since
        guard Date().timeIntervalSince(since) >= adapterCutGrace else { return }
        engine.adapterCutWorks = false
        adapterCutVerdict = .ignored
        adapterCutSince = nil
        adapterCutFailedAt = snapshot.controlPercentage
        try? hardware?.setAdapterEnabled(true)
        log.notice("adapter cut accepted but the Mac stayed on wall power, discharge disabled")
    }

    private func applyHardwareCeiling() {
        guard let hardware, hardware.capabilities.hasHardwareCeiling else { return }
        try? hardware.setHardwareCeiling(configuration.hardwareCeilingEnabled)
    }

    // MARK: - XPC surface

    func currentState() -> HelperState {
        queue.sync { [self] in
            var state = HelperState()
            state.helperVersion = VoltaicaVersion.full
            state.configuration = configuration
            state.snapshot = lastSnapshot
            state.decision = lastDecision
            state.hardware = hardware?.readState() ?? HardwarePowerState(chargingAllowed: true, adapterEnabled: true)
            state.capabilities = hardware?.capabilities ?? .unknown
            state.calibrationHistory = history
            state.lastError = lastError
            state.startedAt = startedAt
            state.license = license
            state.firstRun = licenseFirstRun
            state.adapterCut = adapterCutVerdict
            state.chargeInhibit = chargeInhibitVerdict
            return state
        }
    }

    func update(configuration incoming: ChargeConfiguration) -> HelperState {
        queue.sync { [self] in
            let previousCeiling = configuration.hardwareCeilingEnabled
            let previousMagSafe = configuration.magSafeFeedbackEnabled
            configuration = incoming.validated()
            License.clamp(&configuration, to: entitlement)
            store.save(configuration)
            if configuration.hardwareCeilingEnabled != previousCeiling { applyHardwareCeiling() }
            if previousMagSafe, !configuration.magSafeFeedbackEnabled {
                try? hardware?.setMagSafeLED(.system)
            }
            lastAppliedState = nil
            tick()
        }
        return currentState()
    }

    /// Returns nil when the key is not one of ours, so the caller can tell a typo from a refusal.
    func activate(licenseKey: String) -> HelperState? {
        guard let info = License.verify(licenseKey) else { return nil }
        queue.sync { [self] in
            license = info
            store.save(licenseKey: licenseKey)
            log.notice("license activated for order \(info.order, privacy: .public)")
        }
        return currentState()
    }

    func deactivateLicense() -> HelperState {
        queue.sync { [self] in
            license = nil
            store.save(licenseKey: nil)
            License.clamp(&configuration, to: entitlement)
            store.save(configuration)
            lastAppliedState = nil
        }
        return currentState()
    }

    func readSMC(keys: [String]) -> [String: String] {
        queue.sync { hardware?.readRaw(keys: keys) ?? [:] }
    }

    func dumpSMC(prefix: String) -> [String: String] {
        queue.sync { hardware?.dumpRaw(prefix: prefix) ?? [:] }
    }

    func relinquish() {
        queue.sync { [self] in
            configuration.enabled = false
            configuration.topUp = nil
            configuration.discharge = nil
            configuration.calibration = nil
            configuration.pauseUntil = nil
            configuration.hardwareCeilingEnabled = false
            store.save(configuration)
            if let hardware {
                try? hardware.setHardwareCeiling(false)
                hardware.releaseControl()
            }
            lastAppliedState = nil
        }
    }

    /// The system is about to sleep: hand the charger back if we were cutting the adapter, so a
    /// sleeping Mac never drains itself on a desk.
    func prepareForSleep() {
        queue.sync { [self] in
            guard let hardware, hardware.capabilities.canCutAdapter else { return }
            if lastDecision.adapterEnabled == false {
                try? hardware.setAdapterEnabled(true)
                lastAppliedState = nil
            }
        }
    }

    func didWake() {
        queue.async { [self] in
            lastAppliedState = nil
            if smc == nil { openHardware() }
            tick()
        }
    }
}
