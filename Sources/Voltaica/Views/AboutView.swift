import SwiftUI
import VoltaicaCore

struct AboutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            AppMark(colors: model.accentColors)
                .frame(width: 96, height: 96)
                .padding(.top, 28)

            VStack(spacing: 4) {
                Text("Voltaica")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Version \(VoltaicaVersion.full)")
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }

            Text("Charge limiting and battery care for Mac laptops. Named after the voltaic pile, the first battery, built by Alessandro Volta in 1800.")
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.68))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 30)

            VStack(spacing: 6) {
                Link(destination: URL(string: VoltaicaIdentifiers.website)!) {
                    Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: VoltaicaIdentifiers.website + "/issues")!) {
                    Label("Report a problem", systemImage: "exclamationmark.bubble")
                }
            }
            .font(.system(size: 12, weight: .medium, design: .rounded))
            .tint(model.accentColors[1])

            Spacer(minLength: 0)

            licenseRow

            VStack(spacing: 3) {
                Text("Engine GPL-3.0-or-later · app © 2026 Federico Infelici")
                Text("Not affiliated with Apple or with any other battery utility.")
            }
            .font(.system(size: 9.5, design: .rounded))
            .foregroundStyle(.white.opacity(0.34))
            .padding(.bottom, 20)
        }
        .frame(width: 400, height: 450)
        .background { AuroraBackdrop(colors: model.accentColors) }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var licenseRow: some View {
        switch model.licenseState {
        case .licensed(let info):
            VStack(spacing: 2) {
                Label("Voltaica Pro", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(Palette.mint)
                Text(info.email)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.bottom, 8)
        case .trial(let days):
            Text("Trial · \(days) day\(days == 1 ? "" : "s") left")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.bottom, 8)
        case .trialExpired:
            Text("Free tier · Pro is \(License.price) once")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.bottom, 8)
        }
    }
}

/// The mark: a battery holding a mint-to-cyan charge, wrapped in a charge arc.
struct AppMark: View {
    var colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(colors: [colors[0].opacity(0.30), .clear],
                                       center: .center, startRadius: 0, endRadius: side * 0.6)
                    )
                Circle()
                    .trim(from: 0.06, to: 0.82)
                    .stroke(
                        AngularGradient(colors: colors + [colors[0]], center: .center),
                        style: StrokeStyle(lineWidth: side * 0.075, lineCap: .round)
                    )
                    .rotationEffect(.degrees(35))
                    .shadow(color: colors[1].opacity(0.6), radius: side * 0.06)

                // The same vertical battery as the app icon, so the mark reads as one thing.
                VStack(spacing: side * 0.022) {
                    RoundedRectangle(cornerRadius: side * 0.022, style: .continuous)
                        .fill(.white.opacity(0.85))
                        .frame(width: side * 0.13, height: side * 0.038)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: side * 0.062, style: .continuous)
                            .fill(.white.opacity(0.10))
                        RoundedRectangle(cornerRadius: side * 0.046, style: .continuous)
                            .fill(LinearGradient(colors: colors, startPoint: .bottom, endPoint: .top))
                            .padding(side * 0.022)
                            .mask(alignment: .bottom) {
                                Rectangle().frame(height: side * 0.30)
                            }
                            .shadow(color: colors[1].opacity(0.7), radius: side * 0.05)
                        RoundedRectangle(cornerRadius: side * 0.062, style: .continuous)
                            .strokeBorder(.white.opacity(0.88), lineWidth: side * 0.026)
                    }
                    .frame(width: side * 0.30, height: side * 0.42)
                }
                .shadow(color: .black.opacity(0.35), radius: side * 0.02, y: side * 0.01)
            }
        }
    }
}
