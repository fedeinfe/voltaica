import SwiftUI
import VoltaicaCore

/// What the hardware supports, what the daemon is doing, and the raw SMC values behind it all.
/// This is the screen to screenshot into a bug report.
struct DiagnosticsTab: View {
    @Environment(AppModel.self) private var model
    @State private var keys: [String: String] = [:]
    @State private var prefix = "CH"
    @State private var isLoading = false
    @State private var copied = false

    private let chargerKeys = ["CH0B", "CH0C", "CH0I", "CHWA", "ACLC", "BCLM", "ACEN", "TB0T", "CHBI", "CHBV"]

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                serviceCard
                capabilityCard
            }
            smcCard
        }
        .task { await loadChargerKeys() }
    }

    private var serviceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Background service", systemImage: "gearshape.2")
            row("Registration", model.installState.rawValue)
            row("Connected", model.isConnected ? "yes" : "no")
            row("Helper version", model.helperVersion.isEmpty ? "—" : model.helperVersion)
            row("App version", VoltaicaVersion.full)
            row("Platform", model.capabilities.platform.rawValue)
            if let error = model.lastConnectionError, !model.isConnected {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xFF8A80))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                if model.installState != .enabled {
                    Button("Install service") { model.installHelper() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
                Button("Login Items") { model.openLoginItems() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(role: .destructive) {
                    Task { await model.uninstallHelper() }
                } label: {
                    Text("Remove service")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22, elevated: true)
    }

    private var capabilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "What this Mac can do", systemImage: "cpu")
            capability("Hold a charge limit", model.capabilities.canInhibitCharging)
            Text((model.capabilities.usesSmartBatteryUserClient
                  ? "Charger control via AppleSmartBatteryManager"
                  : "Charger control via SMC keys")
                 + " — " + model.chargeInhibitVerdict.label)
                .font(.system(size: 11.5))
                .foregroundStyle(.white.opacity(0.5))
            capability("Run down while plugged in", model.canDischarge)
            if model.adapterCutVerdict == .ignored {
                Text("This Mac accepts the request to cut adapter power and then keeps drawing from the wall, so a forced run-down is not possible. Unplug to discharge.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            capability("Firmware ceiling", model.capabilities.hasHardwareCeiling)
            capability("MagSafe light", model.capabilities.hasMagSafeLED)
            capability("Intel percentage ceiling", model.capabilities.hasIntelCeiling)

            if !model.isConnected {
                Text("Capabilities are probed by the background service. Install it to see them.")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .glassCard(cornerRadius: 22, elevated: true)
    }

    private var smcCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(title: "SMC keys", systemImage: "terminal")
                Spacer()
                TextField("prefix", text: $prefix)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                Button("Dump") { Task { await loadPrefix() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button("Charger keys") { Task { await loadChargerKeys() } }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(copied ? "Copied" : "Copy") {
                    let text = keys.sorted { $0.key < $1.key }.map { "\($0.key)  \($0.value)" }.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(keys.isEmpty)
            }

            if isLoading {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            } else if keys.isEmpty {
                Text(model.isConnected
                     ? "No keys returned. On this Mac the charger keys may be readable only as root."
                     : "The background service reads these as root. Install it to see the charger keys.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 6) {
                    ForEach(keys.sorted { $0.key < $1.key }, id: \.key) { key, value in
                        HStack(spacing: 6) {
                            Text(key)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(LinearGradient(colors: model.accentColors,
                                                                startPoint: .leading, endPoint: .trailing))
                            Text(value)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.92))
        }
    }

    private func capability(_ title: String, _ available: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: available ? "checkmark.circle.fill" : "minus.circle")
                .font(.system(size: 12))
                .foregroundStyle(available ? Color(hex: 0x7BF0C0) : Color.white.opacity(0.3))
            Text(title)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(available ? 0.9 : 0.5))
            Spacer()
        }
    }

    private func loadChargerKeys() async {
        isLoading = true
        copied = false
        keys = await model.readSMC(keys: chargerKeys)
        isLoading = false
    }

    private func loadPrefix() async {
        isLoading = true
        copied = false
        keys = await model.dumpSMC(prefix: prefix.uppercased())
        isLoading = false
    }
}
