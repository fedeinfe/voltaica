import Foundation
import Observation
import ServiceManagement
import SwiftUI
import UserNotifications
import VoltaicaCore
import os

/// Single source of truth for the UI.
///
/// The battery is read locally so every screen works even before the background service is
/// approved; the service is only needed to *change* anything.
@Observable
@MainActor
final class AppModel {
    /// One instance for the whole process: a menu bar app has exactly one state, and the
    /// AppKit delegate needs to reach it too.
    static let shared = AppModel()

    // Live values
    var snapshot = BatterySnapshot()
    var configuration = ChargeConfiguration()
    var decision = PolicyDecision()
    var hardware = HardwarePowerState(chargingAllowed: true, adapterEnabled: true)
    var capabilities = HardwareCapabilities.unknown
    /// What the daemon has watched the two charger controls actually do on this Mac.
    var chargeInhibitVerdict: ControlVerdict = .untested
    var adapterCutVerdict: ControlVerdict = .untested
    var calibrationHistory = CalibrationHistory()
    var helperVersion = ""
    var helperError: String?

    // Connection
    var installState: HelperClient.InstallState = .notRegistered
    var isConnected = false
    var lastConnectionError: String?

    // History
    var history: [HistorySample] = []
    var historyRange: HistoryRange = .day

    // UI
    var isDraggingLimit = false
    var showOnboarding = false
    var showPaywall = false

    var license: LicenseInfo?
    var firstRun = Date()
    var activationError: String?
    var isActivating = false

    @ObservationIgnored private let client = HelperClient()
    @ObservationIgnored private let reader = BatteryReader()
    @ObservationIgnored private let log = Logger(subsystem: VoltaicaIdentifiers.app, category: "model")
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var pushTask: Task<Void, Never>?
    @ObservationIgnored private var lastLocalEdit = Date.distantPast
    @ObservationIgnored private var seenEventIDs = Set<UUID>()
    @ObservationIgnored private var notificationsAuthorised = false

    enum HistoryRange: String, CaseIterable, Identifiable {
        case sixHours = "6h"
        case day = "24h"
        case week = "7d"
        case month = "30d"

        var id: String { rawValue }
        var seconds: TimeInterval {
            switch self {
            case .sixHours: return 6 * 3600
            case .day: return 24 * 3600
            case .week: return 7 * 86_400
            case .month: return 30 * 86_400
            }
        }
    }

    init() {
        snapshot = reader.read()
        installState = HelperClient.installState
        showOnboarding = installState != .enabled
    }

    // MARK: - Polling

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2.5))
            }
        }
        Task { await requestNotificationAuthorisation() }
        loadHistory()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        snapshot = reader.read()
        installState = HelperClient.installState

        do {
            let state = try await client.state()
            isConnected = true
            lastConnectionError = nil
            helperVersion = state.helperVersion
            helperError = state.lastError
            decision = state.decision
            hardware = state.hardware
            capabilities = state.capabilities
            chargeInhibitVerdict = state.chargeInhibit
            adapterCutVerdict = state.adapterCut
            calibrationHistory = state.calibrationHistory
            license = state.license
            firstRun = state.firstRun
            // The daemon's snapshot is authoritative for anything policy related.
            snapshot = state.snapshot
            // Do not fight the user's fingers: a slider drag wins for a moment.
            if Date().timeIntervalSince(lastLocalEdit) > 1.5, !isDraggingLimit {
                configuration = state.configuration
            }
            handle(events: state.recentEvents)
        } catch {
            isConnected = false
            lastConnectionError = error.localizedDescription
            decision = localDecisionPreview()
        }
    }

    /// With no service running there is nothing to report but the plain facts.
    private func localDecisionPreview() -> PolicyDecision {
        var preview = PolicyDecision()
        preview.mode = snapshot.isPresent ? (snapshot.isPluggedIn ? .charging : .onBattery) : .noBattery
        preview.detail = installState == .enabled
            ? "Waiting for the background service"
            : "Background service not enabled"
        return preview
    }

    // MARK: - Licensing

    var licenseState: LicenseState { License.state(license: license, firstRun: firstRun) }
    var features: FeatureSet { licenseState.features }

    /// Locked features open the paywall rather than silently doing nothing.
    func requireFeature(_ enabled: Bool) -> Bool {
        if enabled { return true }
        showPaywall = true
        return false
    }

    func activate(licenseKey: String) {
        isActivating = true
        activationError = nil
        Task {
            do {
                let state = try await client.activate(licenseKey: licenseKey)
                license = state.license
                configuration = state.configuration
                showPaywall = false
            } catch {
                activationError = error.localizedDescription
            }
            isActivating = false
        }
    }

    func removeLicense() {
        Task {
            if let state = try? await client.deactivateLicense() {
                license = state.license
                configuration = state.configuration
            }
        }
    }

    func openPurchasePage() {
        NSWorkspace.shared.open(License.purchaseURL)
    }

    // MARK: - Mutations

    func edit(_ change: (inout ChargeConfiguration) -> Void) {
        change(&configuration)
        lastLocalEdit = Date()
        schedulePush()
    }

    /// Slider drags produce dozens of values a second; the service only needs the last one.
    private func schedulePush() {
        pushTask?.cancel()
        let payload = configuration
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            await self?.push(payload)
        }
    }

    func pushNow() {
        pushTask?.cancel()
        let payload = configuration
        Task { await push(payload) }
    }

    private func push(_ payload: ChargeConfiguration) async {
        do {
            let state = try await client.apply(payload)
            isConnected = true
            decision = state.decision
            hardware = state.hardware
            helperError = state.lastError
            handle(events: state.recentEvents)
        } catch {
            isConnected = false
            lastConnectionError = error.localizedDescription
            log.error("apply failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Actions

    func setLimit(_ value: Int) {
        guard requireFeature(features.customLimit || value == FeatureSet.freeTierLimit) else { return }
        edit {
            $0.limit = value
            $0.enabled = true
        }
    }

    func toggleLimit() {
        edit { $0.enabled.toggle() }
        pushNow()
    }

    func pauseCharging(minutes: Int) {
        edit { $0.pauseUntil = Date().addingTimeInterval(Double(minutes) * 60) }
        pushNow()
    }

    func resumeCharging() {
        edit { $0.pauseUntil = nil }
        pushNow()
    }

    func topUp(to target: Int = 100) {
        edit {
            $0.pauseUntil = nil
            $0.topUp = TopUpRequest(target: target, expiresAt: Date().addingTimeInterval(12 * 3600))
        }
        pushNow()
    }

    func cancelTopUp() {
        edit { $0.topUp = nil }
        pushNow()
    }

    func discharge(to target: Int) {
        guard requireFeature(features.discharge) else { return }
        edit { $0.discharge = DischargeRequest(target: target) }
        pushNow()
    }

    func cancelDischarge() {
        edit { $0.discharge = nil }
        pushNow()
    }

    func startCalibration() {
        guard requireFeature(features.calibration) else { return }
        edit { $0.calibration = CalibrationSession() }
        pushNow()
    }

    func stopCalibration() {
        edit { $0.calibration = nil }
        pushNow()
    }

    var isPaused: Bool {
        guard let until = configuration.pauseUntil else { return false }
        return until > Date()
    }

    var isTopUpActive: Bool { configuration.topUp != nil }
    var isDischargeActive: Bool { configuration.discharge != nil || decision.mode == .discharging }

    /// Whether running the battery down on demand is worth offering at all.
    var canDischarge: Bool { capabilities.canCutAdapter && adapterCutVerdict != .ignored }
    var isCalibrating: Bool { configuration.calibration?.isActive ?? false }

    var accentColors: [Color] { Palette.accent(for: decision.mode) }

    // MARK: - Service install

    func installHelper() {
        do {
            try HelperClient.install()
        } catch {
            log.notice("register returned \(error.localizedDescription, privacy: .public)")
        }
        installState = HelperClient.installState
        if installState != .enabled {
            HelperClient.openLoginItemsSettings()
        }
        Task {
            try? await Task.sleep(for: .seconds(1))
            await refresh()
        }
    }

    func openLoginItems() {
        HelperClient.openLoginItemsSettings()
    }

    func uninstallHelper() async {
        try? await client.relinquish()
        try? HelperClient.uninstall()
        installState = HelperClient.installState
        isConnected = false
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                log.error("launch at login: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Diagnostics

    func dumpSMC(prefix: String) async -> [String: String] {
        (try? await client.dumpSMC(prefix: prefix)) ?? [:]
    }

    func readSMC(keys: [String]) async -> [String: String] {
        (try? await client.readSMC(keys: keys)) ?? [:]
    }

    // MARK: - History

    func loadHistory() {
        let cutoff = Date().addingTimeInterval(-historyRange.seconds)
        Task.detached(priority: .utility) {
            let samples = HistoryStore.load(since: cutoff)
            await MainActor.run { self.history = samples }
        }
    }

    // MARK: - Notifications

    private func requestNotificationAuthorisation() async {
        let centre = UNUserNotificationCenter.current()
        do {
            notificationsAuthorised = try await centre.requestAuthorization(options: [.alert, .sound])
        } catch {
            notificationsAuthorised = false
        }
    }

    private func handle(events: [TimestampedEvent]) {
        // First sync only records what is already there: nobody wants a burst of notifications
        // about things that happened while they were asleep.
        let isFirstSync = seenEventIDs.isEmpty
        for event in events where !seenEventIDs.contains(event.id) {
            seenEventIDs.insert(event.id)
            guard !isFirstSync, configuration.notificationsEnabled, notificationsAuthorised else { continue }
            guard Date().timeIntervalSince(event.at) < 300 else { continue }
            post(event)
        }
        if seenEventIDs.count > 500 { seenEventIDs.removeAll() }
    }

    private func post(_ event: TimestampedEvent) {
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.detail.isEmpty
            ? String(format: "Battery at %.0f%%", snapshot.controlPercentage)
            : event.detail
        content.sound = nil
        let request = UNNotificationRequest(identifier: event.id.uuidString,
                                            content: content,
                                            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
