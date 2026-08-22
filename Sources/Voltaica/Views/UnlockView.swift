import SwiftUI
import VoltaicaCore

/// The one place money is mentioned. Sold once, no subscription, and it says so, because the
/// first question anyone asks a menu bar app in 2026 is whether it will start billing monthly.
struct UnlockView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @FocusState private var keyFocused: Bool

    private let perks: [(String, String, String)] = [
        ("slider.horizontal.below.square.filled.and.square", "Any limit you like",
         "Hold the pack anywhere from 20% to 100%, not just the one ceiling the firmware offers."),
        ("sailboat", "Sailing mode",
         "Let the charge drift down before topping it back up, so the charger cycles far less often."),
        ("bolt.slash", "Discharge on demand",
         "Cut the adapter and walk a full battery back down to your limit instead of waiting."),
        ("thermometer.medium", "Heat protection",
         "Stop charging while the pack is hot, which is when charging costs the most life."),
        ("calendar.badge.clock", "Scheduled top ups",
         "Be at 100% for the mornings you travel, and only those."),
        ("wand.and.rays", "Guided calibration",
         "A full cycle run properly, so the percentage macOS reports means something again.")
    ]

    var body: some View {
        ZStack {
            AuroraBackdrop(colors: [Palette.mint, Palette.cyan], intense: true)
            ScrollView {
                VStack(spacing: 22) {
                    header
                    perkGrid
                    purchase
                    activation
                    footer
                }
                .padding(28)
            }
        }
        .frame(width: 520, height: 700)
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.badge.checkmark")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [Palette.mint, Palette.cyan],
                                                startPoint: .top, endPoint: .bottom))
            Text("Voltaica Pro")
                .font(.system(size: 26, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 6)
    }

    private var subtitle: String {
        switch model.licenseState {
        case .trial(let days):
            return "Everything is unlocked for \(days) more day\(days == 1 ? "" : "s"). Keep it forever for \(License.price)."
        case .trialExpired:
            return "The trial is over. Monitoring and the 80% ceiling stay free, forever."
        case .licensed(let info):
            return "Licensed to \(info.email). Thank you."
        }
    }

    private var perkGrid: some View {
        VStack(spacing: 12) {
            ForEach(perks, id: \.1) { icon, title, detail in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Palette.cyan)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.system(size: 12.5, weight: .semibold))
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    @ViewBuilder private var purchase: some View {
        if !model.licenseState.isPaid {
            VStack(spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(License.price)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("one time").font(.system(size: 12, weight: .semibold))
                        Text("no subscription").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Button(action: model.openPurchasePage) {
                    Text("Buy a license")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundStyle(.black)
                        .background(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .fill(LinearGradient(colors: [Palette.mint, Palette.cyan],
                                                     startPoint: .leading, endPoint: .trailing))
                        )
                }
                .buttonStyle(.plain)
                Text("Three Macs per license. Updates included.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .glassCard(cornerRadius: 20, tint: Palette.mint, elevated: true)
        }
    }

    @ViewBuilder private var activation: some View {
        if case .licensed = model.licenseState {
            HStack {
                Label("License active", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.mint)
                Spacer()
                Button("Remove", action: model.removeLicense)
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .glassCard(cornerRadius: 16)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Already bought it?")
                TextField("Paste your license key", text: $key, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .lineLimit(2...3)
                    .focused($keyFocused)
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(Color.white.opacity(keyFocused ? 0.34 : 0.14), lineWidth: 0.8))
                    )
                if let error = model.activationError {
                    Text(error)
                        .font(.system(size: 11))
                        .foregroundStyle(.red)
                }
                Button {
                    model.activate(licenseKey: key)
                } label: {
                    HStack(spacing: 6) {
                        if model.isActivating { ProgressView().controlSize(.small) }
                        Text("Activate")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isActivating)
            }
            .padding(16)
            .glassCard(cornerRadius: 20)
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            Text("Voltaica's engine is open source. Building it yourself is free and always will be; the license pays for the signed, notarised build and the work behind it.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button("Close") { dismiss() }
                .buttonStyle(.plain)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
        }
    }
}


/// Opens the unlock window whenever a locked control is touched. Applied by every scene, because
/// `AppModel` has no way to open a window on its own.
///
/// The model is passed in rather than read from the environment: a modifier applied after
/// `.environment(model)` sits above it in the hierarchy, so an `@Environment` lookup here would
/// find nothing and trap the moment the scene's body is evaluated.
struct PaywallPresenter: ViewModifier {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.onChange(of: model.showPaywall) { _, shown in
            guard shown else { return }
            openWindow(id: "unlock")
            NSApp.activate(ignoringOtherApps: true)
            model.showPaywall = false
        }
    }
}

extension View {
    func paywallPresenter(_ model: AppModel) -> some View { modifier(PaywallPresenter(model: model)) }
}

/// Trial countdown, and after it a quiet reminder. Never a modal, never a nag on launch.
struct TrialBanner: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if case .licensed = model.licenseState {
            EmptyView()
        } else {
            Button {
                openWindow(id: "unlock")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: expired ? "lock.fill" : "clock.badge.checkmark")
                        .font(.system(size: 11, weight: .semibold))
                    Text(message)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    Text(License.price)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.9))
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Palette.mint.opacity(0.22), Palette.cyan.opacity(0.16)],
                                             startPoint: .leading, endPoint: .trailing))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Palette.mint.opacity(0.32), lineWidth: 0.8))
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var expired: Bool { model.licenseState == .trialExpired }

    private var message: String {
        switch model.licenseState {
        case .trial(let days): return "Pro trial: \(days) day\(days == 1 ? "" : "s") left"
        case .trialExpired: return "Unlock custom limits and the rest"
        case .licensed: return ""
        }
    }
}

/// A small padlock that turns a locked row into a way in.
struct ProLock: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    var unlocked: Bool

    var body: some View {
        if unlocked {
            EmptyView()
        } else {
            Button {
                openWindow(id: "unlock")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "lock.fill").font(.system(size: 8, weight: .bold))
                    Text("PRO").font(.system(size: 8.5, weight: .heavy, design: .rounded))
                }
                .foregroundStyle(Palette.mint)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Palette.mint.opacity(0.16)))
            }
            .buttonStyle(.plain)
            .help("Included in Voltaica Pro, \(License.price) once")
        }
    }
}
