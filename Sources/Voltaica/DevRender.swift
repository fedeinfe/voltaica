import AppKit
import SwiftUI
import VoltaicaCore

/// Renders each screen straight to PNG when `VOLTAICA_RENDER` points at a directory. This exists
/// because a headless build machine cannot screenshot a menu bar popover, and reviewing the design
/// by reading SwiftUI source does not work.
@MainActor
enum DevRender {
    static var requestedDirectory: String? { ProcessInfo.processInfo.environment["VOLTAICA_RENDER"] }

    static func run(into directory: String) {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let model = AppModel.shared
        let preferences = Preferences.shared
        populate(model)

        write(MenuPanel().environment(model).environment(preferences), "menu-panel", to: root)
        write(UnlockView().environment(model), "unlock", to: root)
        write(SettingsWindow().environment(model).environment(preferences)
                .frame(width: 560, height: 780), "settings", to: root)
        write(DashboardView().environment(model).environment(preferences)
                .frame(width: 880, height: 760), "dashboard", to: root)
        write(AboutView().environment(model).frame(width: 420, height: 470), "about", to: root)
        write(OnboardingView {}.environment(model).environment(preferences)
                .frame(width: 520, height: 460), "onboarding", to: root)

        // The trial banner reads differently once the trial is gone, and that is the state most
        // users will actually look at.
        model.firstRun = Date().addingTimeInterval(-30 * 86_400)
        write(MenuPanel().environment(model).environment(preferences), "menu-panel-free", to: root)
        write(UnlockView().environment(model), "unlock-expired", to: root)
    }

    private static func populate(_ model: AppModel) {
        var snapshot = BatterySnapshot()
        snapshot.isPresent = true
        snapshot.isPluggedIn = true
        snapshot.percentage = 80
        snapshot.rawPercentage = 79.6
        snapshot.cycleCount = 435
        snapshot.temperature = 34.9
        snapshot.rawCurrentCapacity = 4694
        snapshot.rawMaxCapacity = 4853
        snapshot.designCapacity = 6075
        snapshot.nominalCapacity = 5003
        snapshot.designCycleCount = 1000
        snapshot.voltage = 12.645
        snapshot.amperage = 0
        snapshot.chargingVoltage = 4265
        snapshot.serial = "F5N2049AZXV"
        snapshot.gasGauge = "1.0"
        snapshot.dailyMinSoc = 62
        snapshot.dailyMaxSoc = 80
        snapshot.lifetimeMaxTemperature = 41.2
        snapshot.lifetimeAvgTemperature = 30.4
        snapshot.totalOperatingHours = 8_912
        snapshot.cellVoltages = [4.214, 4.211, 4.216]
        var adapter = AdapterInfo()
        adapter.watts = 96
        adapter.voltage = 20.2
        adapter.current = 4.7
        adapter.name = "96W USB-C Power Adapter"
        snapshot.adapter = adapter
        snapshot.isCharging = false
        model.snapshot = snapshot

        var configuration = ChargeConfiguration()
        configuration.limit = 80
        model.configuration = configuration

        var decision = PolicyDecision()
        decision.mode = .holding
        decision.chargingAllowed = false
        decision.detail = "Holding at 80%, charger idle"
        model.decision = decision

        model.capabilities = HardwareCapabilities(platform: .appleSilicon,
                                                  canInhibitCharging: true,
                                                  canCutAdapter: true,
                                                  hasHardwareCeiling: true,
                                                  hasMagSafeLED: false,
                                                  hasIntelCeiling: false)
        model.isConnected = true
        model.installState = .enabled
        model.helperVersion = VoltaicaVersion.full
        // A believable day: a slow drift down while sailing, then a charge back to the limit.
        let now = Date()
        model.history = (0..<288).map { step in
            let minutes = Double(288 - step) * 5
            let phase = sin(Double(step) / 34)
            return HistorySample(t: now.addingTimeInterval(-minutes * 60),
                                 p: 74 + phase * 5.5,
                                 c: 31 + phase * 3.4,
                                 w: phase > 0.6 ? 42 : 0,
                                 m: phase > 0.6 ? "charging" : "holding",
                                 a: true)
        }
    }

    /// Hosted in a real (never shown) window rather than through `ImageRenderer`, because
    /// `ImageRenderer` skips anything inside a `ScrollView` and draws AppKit-backed controls as
    /// placeholder boxes. `cacheDisplay` runs the actual AppKit draw path instead.
    private static func write<V: View>(_ view: V, _ name: String, to directory: URL) {
        let hosting = NSHostingView(rootView: view)
        var size = hosting.fittingSize
        if size.width < 2 || size.height < 2 { size = CGSize(width: 560, height: 720) }
        hosting.frame = CGRect(origin: .zero, size: size)

        let window = NSWindow(contentRect: hosting.frame,
                              styleMask: [.borderless],
                              backing: .buffered,
                              defer: false)
        window.contentView = hosting
        window.appearance = NSAppearance(named: .darkAqua)
        window.layoutIfNeeded()
        hosting.layoutSubtreeIfNeeded()
        // One turn of the run loop so materials and gradients have a chance to draw.
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let url = directory.appendingPathComponent("\(name).png")
        try? data.write(to: url)
        print("rendered \(url.path) \(Int(size.width))×\(Int(size.height))")
    }
}
