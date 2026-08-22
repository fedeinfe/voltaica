import Foundation
import VoltaicaCore

/// Small scripting front end. Talks to the daemon over XPC for anything that changes state, and
/// can poke the SMC directly when run as root, which is the rescue path if the daemon is gone.
struct CLI {
    static let usage = """
    voltaicactl \(VoltaicaVersion.marketing) — command line control for Voltaica

    USAGE
      voltaicactl status                  human readable summary
      voltaicactl json                    full state as JSON
      voltaicactl limit <20-100>          set the charge limit
      voltaicactl on | off                enable or disable the limit
      voltaicactl pause [minutes]         stop charging now (default 60 minutes)
      voltaicactl resume                  clear a pause
      voltaicactl topup [target]          charge to target once (default 100)
      voltaicactl discharge <target>      run down to target while plugged in
      voltaicactl calibrate start|stop    guided calibration cycle
      voltaicactl sailing on|off          hysteresis around the limit
      voltaicactl heat on|off|<°C>        heat protection
      voltaicactl smc <KEY> [KEY...]      read raw SMC keys
      voltaicactl selftest                probe the charger keys and prove writes land
      voltaicactl license [<key>]         show, activate or (with --remove) drop a license
      voltaicactl reset                   hand the charger back to macOS
      voltaicactl install | uninstall     register or remove the background service

    Anything that changes state needs the background service. `reset` also works with
    `sudo voltaicactl reset` if the service is not running.
    """

    let client = HelperClient()

    func run(_ arguments: [String]) async -> Int32 {
        guard let command = arguments.first else {
            print(Self.usage)
            return 0
        }
        let rest = Array(arguments.dropFirst())

        do {
            switch command {
            case "status": return try await status()
            case "json": return try await json()
            case "limit": return try await limit(rest)
            case "on": return try await mutate { $0.enabled = true }
            case "off": return try await mutate { $0.enabled = false }
            case "pause": return try await pause(rest)
            case "resume": return try await mutate { $0.pauseUntil = nil }
            case "topup": return try await topUp(rest)
            case "discharge": return try await discharge(rest)
            case "calibrate": return try await calibrate(rest)
            case "sailing": return try await toggle(rest) { $0.sailingEnabled = $1 }
            case "heat": return try await heat(rest)
            case "smc": return try await smc(rest)
            case "smc-dump": return try await smcDump(rest.first)
            case "selftest": return try await selftest(rest)
            case "license": return try await license(rest)
            case "reset": return try await reset()
            case "install": return install()
            case "uninstall": return await uninstall()
            case "version", "--version", "-v": print(VoltaicaVersion.full); return 0
            case "help", "--help", "-h": print(Self.usage); return 0
            default:
                fail("unknown command '\(command)'")
                return 64
            }
        } catch {
            fail(error.localizedDescription)
            if HelperClient.installState != .enabled {
                fail("background service state: \(HelperClient.installState.rawValue)")
            }
            return 70
        }
    }

    // MARK: - Commands

    private func status() async throws -> Int32 {
        let state = try await client.state()
        let snapshot = state.snapshot
        let config = state.configuration

        print("Voltaica \(state.helperVersion)")
        print(String(format: "Charge      %d%%  (gauge reads %.1f%% raw)", snapshot.percentage, snapshot.rawPercentage))
        print("Mode        \(state.decision.mode.label) — \(state.decision.detail)")
        print("Limit       \(config.enabled ? "\(config.clampedLimit)%" : "off")"
              + (config.sailingEnabled ? ", sailing \(config.sailingDepth)%" : ""))
        print("Power       \(snapshot.adapterDescription)")
        print(String(format: "Battery     %.1f°C, %.2fV, %.1fW", snapshot.temperature, snapshot.voltage, snapshot.watts))
        print(String(format: "Health      %.1f%% (%d of %d mAh), %d cycles",
                     snapshot.healthPercent, snapshot.rawMaxCapacity, snapshot.designCapacity, snapshot.cycleCount))
        print("Charger     charging \(state.hardware.chargingAllowed ? "allowed" : "inhibited"), "
              + "adapter \(state.hardware.adapterEnabled ? "on" : "cut")")
        let reasons = NotChargingReason.describe(snapshot.notChargingReason)
        if !reasons.isEmpty { print("Not charging \(reasons.joined(separator: ", "))") }
        if let error = state.lastError { print("Last error  \(error)") }
        return 0
    }

    private func json() async throws -> Int32 {
        let state = try await client.state()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(state), as: UTF8.self))
        return 0
    }

    private func limit(_ arguments: [String]) async throws -> Int32 {
        guard let value = arguments.first.flatMap(Int.init), (20...100).contains(value) else {
            fail("limit takes a number between 20 and 100")
            return 64
        }
        return try await mutate {
            $0.limit = value
            $0.enabled = true
        }
    }

    private func pause(_ arguments: [String]) async throws -> Int32 {
        let minutes = arguments.first.flatMap(Int.init) ?? 60
        return try await mutate { $0.pauseUntil = Date().addingTimeInterval(Double(minutes) * 60) }
    }

    private func topUp(_ arguments: [String]) async throws -> Int32 {
        let target = arguments.first.flatMap(Int.init) ?? 100
        return try await mutate {
            $0.pauseUntil = nil
            $0.topUp = TopUpRequest(target: target, expiresAt: Date().addingTimeInterval(12 * 3600))
        }
    }

    private func discharge(_ arguments: [String]) async throws -> Int32 {
        guard let target = arguments.first.flatMap(Int.init) else {
            fail("discharge needs a target percentage")
            return 64
        }
        return try await mutate { $0.discharge = DischargeRequest(target: target) }
    }

    private func calibrate(_ arguments: [String]) async throws -> Int32 {
        switch arguments.first {
        case "start":
            return try await mutate { $0.calibration = CalibrationSession() }
        case "stop":
            return try await mutate { $0.calibration = nil }
        default:
            fail("calibrate takes 'start' or 'stop'")
            return 64
        }
    }

    private func heat(_ arguments: [String]) async throws -> Int32 {
        guard let argument = arguments.first else {
            fail("heat takes on, off or a temperature in °C")
            return 64
        }
        if argument == "on" { return try await mutate { $0.heatProtectionEnabled = true } }
        if argument == "off" { return try await mutate { $0.heatProtectionEnabled = false } }
        guard let value = Double(argument) else {
            fail("heat takes on, off or a temperature in °C")
            return 64
        }
        return try await mutate {
            $0.heatProtectionEnabled = true
            $0.heatThreshold = value
        }
    }

    private func toggle(_ arguments: [String], _ apply: @escaping (inout ChargeConfiguration, Bool) -> Void) async throws -> Int32 {
        guard let argument = arguments.first, argument == "on" || argument == "off" else {
            fail("expected 'on' or 'off'")
            return 64
        }
        return try await mutate { apply(&$0, argument == "on") }
    }

    private func smc(_ keys: [String]) async throws -> Int32 {
        let requested = keys.isEmpty
            ? ["CH0B", "CH0C", "CH0I", "CHWA", "ACLC", "BCLM", "TB0T", "CHBI", "CHBV"]
            : keys
        // The daemon runs as root and the SMC answers root for keys it hides from everyone else,
        // so ask it first and only read directly when it is not up.
        if getuid() != 0, let values = try? await client.readSMC(keys: requested), !values.isEmpty {
            for (key, value) in values.sorted(by: { $0.key < $1.key }) { print("\(key)  \(value)") }
            print("— via background service (root)")
            return 0
        }
        if let connection = try? SMCConnection() {
            let hardware = PowerHardware(smc: connection)
            for (key, value) in hardware.readRaw(keys: requested).sorted(by: { $0.key < $1.key }) {
                print("\(key)  \(value)")
            }
            return 0
        }
        let values = try await client.readSMC(keys: requested)
        if values.isEmpty { fail("no keys readable"); return 70 }
        for (key, value) in values.sorted(by: { $0.key < $1.key }) { print("\(key)  \(value)") }
        return 0
    }

    /// Prints every key the SMC exposes, optionally filtered by prefix.
    private func smcDump(_ filter: String?) async throws -> Int32 {
        // The daemon runs as root and sees keys this process cannot, so prefer it when it is up.
        if getuid() != 0, let values = try? await client.dumpSMC(prefix: filter ?? ""), !values.isEmpty {
            for (key, value) in values.sorted(by: { $0.key < $1.key }) { print("\(key)  \(value)") }
            print("— \(values.count) keys (via background service)")
            return 0
        }
        return smcDumpDirect(filter)
    }

    private func smcDumpDirect(_ filter: String?) -> Int32 {
        guard let connection = try? SMCConnection() else {
            fail("cannot open the SMC")
            return 70
        }
        guard let keys = try? connection.allKeys() else {
            fail("cannot enumerate SMC keys")
            return 70
        }
        var shown = 0
        for key in keys.sorted(by: { $0.name < $1.name }) {
            if let filter, !key.name.hasPrefix(filter) { continue }
            guard let meta = try? connection.info(for: key) else { continue }
            let bytes = (try? connection.readBytes(key)) ?? []
            let hex = bytes.map { String(format: "%02x", $0) }.joined()
            let big = SMCConnection.decodeNumber(bytes: bytes, type: meta.type, order: .big)
            let little = SMCConnection.decodeNumber(bytes: bytes, type: meta.type, order: .little)
            var line = "\(key.name)  \(meta.type)  \(hex)"
            if let big { line += "  = \(big)" }
            if let little, let big, little != big { line += "  | LE \(little)" }
            print(line)
            shown += 1
        }
        print("— \(shown) of \(keys.count) keys")
        return 0
    }

    private func license(_ arguments: [String]) async throws -> Int32 {
        if arguments.first == "--remove" {
            let state = try await client.deactivateLicense()
            print("license removed, free tier active (limit \(state.configuration.limit)%)")
            return 0
        }
        if let key = arguments.first {
            let state = try await client.activate(licenseKey: key)
            guard let info = state.license else {
                fail("the daemon accepted the key but reported no license")
                return 70
            }
            print("activated  \(info.email)  order \(info.order)  seats \(info.seats)")
            return 0
        }
        let state = try await client.state()
        switch state.licenseState {
        case .licensed(let info):
            print("Voltaica Pro — licensed to \(info.email) (order \(info.order))")
        case .trial(let days):
            print("Trial — \(days) day\(days == 1 ? "" : "s") left, everything unlocked")
            print("Buy a license for \(License.price): \(License.purchaseURL.absoluteString)")
        case .trialExpired:
            print("Free tier — monitoring and the \(FeatureSet.freeTierLimit)% hold")
            print("Buy a license for \(License.price): \(License.purchaseURL.absoluteString)")
        }
        return 0
    }

    /// Proves the write path end to end: what the daemon thinks it can do, then an inhibit and a
    /// restore on the real charger. This is the one command worth running after installing.
    private func selftest(_ arguments: [String] = []) async throws -> Int32 {
        let testDischarge = arguments.contains("--discharge")
        print("Voltaica self test \(VoltaicaVersion.full)")
        print("")

        let state: HelperState
        do {
            state = try await client.state()
        } catch {
            fail("the background service is not reachable: \(error.localizedDescription)")
            print("Install it from the app, then approve it in System Settings › General ›")
            print("Login Items & Extensions › Allow in the Background.")
            return 69
        }

        print("service      \(state.helperVersion), up since \(state.startedAt.formatted(date: .omitted, time: .shortened))")
        let caps = state.capabilities
        print("backend      \(caps.usesSmartBatteryUserClient ? "AppleSmartBatteryManager user client" : "SMC charger keys")")
        line("inhibit charging", caps.canInhibitCharging)
        line("cut adapter (discharge)", caps.canCutAdapter)
        line("firmware ceiling (CHWA)", caps.hasHardwareCeiling)
        line("MagSafe LED (ACLC)", caps.hasMagSafeLED)
        print("battery      \(state.snapshot.percentage)% (gauge \(String(format: "%.1f", state.snapshot.rawPercentage))% raw), \(String(format: "%.1f", state.snapshot.temperature))°C, \(state.snapshot.cycleCount) cycles")
        print("health       \(Int(state.snapshot.healthPercent.rounded()))% of design capacity")
        print("electrical   \(String(format: "%.3f", state.snapshot.voltage)) V, \(Int(state.snapshot.amperage)) mA, \(String(format: "%.1f", state.snapshot.watts)) W")

        guard state.snapshot.isPluggedIn else {
            print("")
            fail("unplugged — there is nothing to hold back. Plug in and run this again.")
            return 1
        }
        guard caps.canInhibitCharging else {
            print("")
            fail("this Mac exposes no way to stop the charger, so a limit cannot be held")
            return 1
        }

        let original = state.configuration
        var failures = 0

        print("")
        print("charge test  holding below the current level for a moment…")
        var probe = original
        probe.enabled = true
        probe.dischargeToLimitAutomatically = false
        probe.limit = max(20, min(99, state.snapshot.percentage - 2))
        _ = try await client.apply(probe)
        try await Task.sleep(for: .seconds(5))
        let holding = try await client.state()
        // Our own flag only records what was asked for; the battery's report is the evidence.
        let notCharging = !holding.snapshot.isCharging && holding.snapshot.amperage <= 0
        line("charger not pushing current", notCharging)
        if !notCharging { failures += 1 }
        if holding.snapshot.notChargingReason != 0 {
            print("             reason: \(NotChargingReason.describe(holding.snapshot.notChargingReason).joined(separator: ", "))")
        }

        if testDischarge, caps.canCutAdapter {
            print("")
            print("discharge    cutting the adapter for 20 s, the battery should start supplying…")
            var run = probe
            run.discharge = DischargeRequest(target: max(20, state.snapshot.percentage - 1))
            _ = try await client.apply(run)
            var drained = false
            for _ in 0..<10 {
                try await Task.sleep(for: .seconds(2))
                let now = try await client.state()
                if now.snapshot.isDischargingOnAdapter { drained = true; break }
            }
            line("running off the battery while plugged in", drained)
            if !drained {
                print("             this Mac accepts the adapter cut and keeps drawing from the wall;")
                print("             Voltaica hides the run-down button rather than pretend otherwise")
            }
        } else if caps.canCutAdapter {
            print("")
            print("discharge    skipped — pass --discharge to run the battery down for 20 s")
        }
        let final = try await client.state()
        print("")
        print("verdicts     charge inhibit: \(final.chargeInhibit.label)")
        print("             adapter cut:    \(final.adapterCut.label)")
        if final.chargeInhibit == .untested {
            print("             (a full battery draws nothing either way — run this again while")
            print("              the Mac is charging and the limit is below the current level)")
        }

        _ = try await client.apply(original)
        print("")
        print("             restored limit \(original.limit)%, enabled \(original.enabled)")
        print("")
        if failures == 0 {
            switch final.chargeInhibit {
            case .confirmed:
                print("The charge limit is confirmed working on this Mac.")
            case .untested:
                print("The charge limit is wired up and the charger took the request. Proving it")
                print("needs a charge in progress, so run this again while the battery is filling.")
            case .ignored:
                print("The charger took the request and kept charging anyway — the limit is not")
                print("being honoured on this Mac. Please open an issue with this output.")
            }
            if final.adapterCut == .ignored {
                print("Running the battery down while plugged in does not work here: this Mac keeps")
                print("drawing from the wall, so unplug when you want the level to drop.")
            }
            return 0
        }
        fail("\(failures) check(s) failed — the service applied the policy but the hardware did not follow")
        return 1
    }

    private func line(_ label: String, _ ok: Bool) {
        let padded = label.padding(toLength: 30, withPad: " ", startingAt: 0)
        print("  \(ok ? "✓" : "✗") \(padded)\(ok ? "" : "  not available")")
    }

    private func reset() async throws -> Int32 {
        if getuid() == 0, let connection = try? SMCConnection() {
            PowerHardware(smc: connection).releaseControl()
            print("Charger handed back to macOS.")
            return 0
        }
        try await client.relinquish()
        print("Charger handed back to macOS, limit disabled.")
        return 0
    }

    private func install() -> Int32 {
        do {
            try HelperClient.install()
            print("Background service registered. State: \(HelperClient.installState.rawValue)")
            if HelperClient.installState == .requiresApproval {
                print("Approve Voltaica in System Settings › General › Login Items & Extensions.")
            }
            return 0
        } catch {
            fail(error.localizedDescription)
            return 70
        }
    }

    private func uninstall() async -> Int32 {
        try? await client.relinquish()
        do {
            try HelperClient.uninstall()
            print("Background service removed.")
            return 0
        } catch {
            fail(error.localizedDescription)
            return 70
        }
    }

    // MARK: - Helpers

    private func mutate(_ change: (inout ChargeConfiguration) -> Void) async throws -> Int32 {
        var config = try await client.state().configuration
        change(&config)
        let state = try await client.apply(config)
        print("\(state.decision.mode.label) — \(state.decision.detail)")
        return 0
    }

    private func fail(_ message: String) {
        // Interleaving matters here: stderr is unbuffered, so stdout has to catch up first.
        fflush(stdout)
        FileHandle.standardError.write(Data("voltaicactl: \(message)\n".utf8))
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
let code = await CLI().run(arguments)
exit(code)
