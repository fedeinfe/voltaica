import SwiftUI
import VoltaicaCore

/// First run: explain what needs approving and why, then watch for it to happen.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(Preferences.self) private var preferences
    var onFinish: () -> Void

    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            footer
        }
        .frame(width: 520, height: 460)
        .background { AuroraBackdrop(colors: model.accentColors, intense: true) }
        .preferredColorScheme(.dark)
        .task(id: model.installState) {
            if model.installState == .enabled, model.isConnected, step == 1 { step = 2 }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: approval
        default: ready
        }
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            AppMark(colors: model.accentColors)
                .frame(width: 84, height: 84)
            Text("Keep the battery off 100%")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("""
                 A lithium pack ages fastest when it sits full and warm. Voltaica stops charging \
                 at a limit you pick, lets the charge drift down instead of topping up constantly, \
                 and pauses when the battery gets hot.
                 """)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            HStack(spacing: 22) {
                bullet("bolt.horizontal", "Charge limit")
                bullet("water.waves", "Sailing")
                bullet("thermometer.medium", "Heat guard")
                bullet("chart.xyaxis.line", "History")
            }
            .padding(.top, 4)
        }
        .padding(30)
    }

    private var approval: some View {
        VStack(spacing: 16) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(LinearGradient(colors: model.accentColors, startPoint: .top, endPoint: .bottom))
            Text("One approval needed")
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("""
                 The charger is controlled by the system management controller, and only a \
                 privileged service can write to it. Voltaica ships a small background service \
                 for exactly that, and macOS asks you to allow it once.

                 Click Install, then switch Voltaica on under Login Items & Extensions.
                 """)
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(.white.opacity(0.72))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            HStack(spacing: 10) {
                Button("Install service") { model.installHelper() }
                    .buttonStyle(.borderedProminent)
                Button("Open Login Items") { model.openLoginItems() }
                    .buttonStyle(.bordered)
            }

            HStack(spacing: 7) {
                if model.installState == .enabled && model.isConnected {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: 0x7BF0C0))
                    Text("Service running").foregroundStyle(.white.opacity(0.8))
                } else {
                    ProgressView().controlSize(.mini)
                    Text("Waiting for approval — state: \(model.installState.rawValue)")
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .font(.system(size: 11, weight: .medium, design: .rounded))
        }
        .padding(30)
    }

    private var ready: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 46))
                .foregroundStyle(LinearGradient(colors: model.accentColors, startPoint: .top, endPoint: .bottom))
            Text("Ready")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("The limit is set to \(model.configuration.clampedLimit)%. Voltaica lives in the menu bar; the limit is held by the background service even when the app is closed.")
                .font(.system(size: 12.5, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(30)
    }

    private func bullet(_ icon: String, _ title: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(LinearGradient(colors: model.accentColors, startPoint: .top, endPoint: .bottom))
            Text(title)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
            }
            Spacer()
            Button(step >= 2 ? "Done" : "Continue") {
                if step >= 2 {
                    preferences.hasSeenOnboarding = true
                    onFinish()
                } else {
                    step += 1
                }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(18)
        .background(Color.black.opacity(0.22))
        .hairlineTop()
    }
}
