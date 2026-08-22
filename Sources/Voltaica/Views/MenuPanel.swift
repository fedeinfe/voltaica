import SwiftUI
import VoltaicaCore

/// The menu bar panel. Everything you need on a normal day, one click from the status item.
struct MenuPanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    private var colors: [Color] { model.accentColors }

    var body: some View {
        VStack(spacing: 12) {
            header

            if model.installState != .enabled || !model.isConnected {
                ServiceBanner()
            }

            TrialBanner()

            ChargeRing(charge: model.snapshot.rawPercentage,
                       limit: model.configuration.clampedLimit,
                       limitActive: model.configuration.isLimitActive,
                       colors: colors,
                       mode: model.decision.mode)
                .padding(.top, 2)

            detailLine
            limitCard
            actions
            telemetry
            footer
        }
        .padding(14)
        .frame(width: 336)
        .background {
            AuroraBackdrop(colors: colors)
        }
        .preferredColorScheme(.dark)
        .animation(.smooth(duration: 0.35), value: model.decision.mode)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            StatusDot(colors: colors, pulsing: model.decision.mode == .charging || model.decision.mode == .topUp)
            Text("Voltaica")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Spacer()

            Toggle("", isOn: Binding(get: { model.configuration.enabled },
                                     set: { _ in model.toggleLimit() }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .help(model.configuration.enabled ? "Charge limit on" : "Charge limit off")

            Button {
                openWindow(id: "dashboard")
            } label: {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.65))
            .help("Open the dashboard")

            Menu {
                Button("Dashboard") { openWindow(id: "dashboard") }
                Button("Settings") { openWindow(id: "settings") }
                Divider()
                Button("Charge to 100% once") { model.topUp() }
                Button(model.isPaused ? "Resume charging" : "Pause for an hour") {
                    model.isPaused ? model.resumeCharging() : model.pauseCharging(minutes: 60)
                }
                Divider()
                Button(model.licenseState.isPaid ? "License" : "Voltaica Pro…") { openWindow(id: "unlock") }
                Button("About Voltaica") { openWindow(id: "about") }
                Button("Quit Voltaica") { NSApplication.shared.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11, weight: .semibold))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 18)
            .foregroundStyle(.white.opacity(0.65))
        }
    }

    private var detailLine: some View {
        Text(model.decision.detail.isEmpty ? model.snapshot.adapterDescription : model.decision.detail)
            .font(.system(size: 11.5, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.62))
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Limit

    private var limitCard: some View {
        VStack(spacing: 8) {
            HStack {
                SectionLabel(title: "Charge limit", systemImage: "bolt.horizontal")
                ProLock(unlocked: model.features.customLimit)
                Spacer()
                MetricText(value: model.configuration.enabled ? "\(model.configuration.clampedLimit)%" : "off",
                           size: 13, weight: .semibold)
                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            }

            LimitSlider(value: Binding(get: { model.configuration.clampedLimit },
                                       set: { model.setLimit($0) }),
                        colors: colors,
                        onEditingChanged: { editing in
                            model.isDraggingLimit = editing
                            if !editing { model.pushNow() }
                        })
                .opacity(model.configuration.enabled ? 1 : 0.45)
                .disabled(!model.configuration.enabled)

            if model.configuration.sailingEnabled, model.configuration.isLimitActive {
                HStack(spacing: 4) {
                    Image(systemName: "water.waves")
                        .font(.system(size: 8.5, weight: .bold))
                    Text("Sailing: charging resumes below \(max(20, model.configuration.clampedLimit - model.configuration.sailingDepth))%")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.38))
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 16, tint: colors[1])
    }

    // MARK: - Actions

    private var actions: some View {
        HStack(spacing: 7) {
            GlassButton(title: model.isPaused ? "Resume" : "Pause",
                        systemImage: model.isPaused ? "play.fill" : "pause.fill",
                        tint: colors[1]) {
                model.isPaused ? model.resumeCharging() : model.pauseCharging(minutes: 60)
            }

            GlassButton(title: model.isTopUpActive ? "Cancel" : "Top up",
                        systemImage: "bolt.fill",
                        tint: colors[0],
                        prominent: model.isTopUpActive) {
                model.isTopUpActive ? model.cancelTopUp() : model.topUp()
            }

            GlassButton(title: model.isDischargeActive ? "Stop" : "Run down",
                        systemImage: "arrow.down.to.line",
                        tint: colors[1]) {
                if model.isDischargeActive {
                    model.cancelDischarge()
                } else {
                    model.discharge(to: model.configuration.clampedLimit)
                }
            }
            .disabled(!model.capabilities.canCutAdapter || !model.snapshot.isPluggedIn)
            .opacity(model.capabilities.canCutAdapter && model.snapshot.isPluggedIn ? 1 : 0.4)
            .help(model.capabilities.canCutAdapter
                  ? "Run the battery down to the limit while staying plugged in"
                  : "This Mac cannot cut adapter power")
        }
    }

    // MARK: - Telemetry

    private var telemetry: some View {
        HStack(spacing: 0) {
            MetricPill(icon: "thermometer.medium",
                       value: String(format: "%.1f°", model.snapshot.temperature),
                       caption: "battery",
                       tint: model.snapshot.temperatureIsElevated ? Color(hex: 0xFF9F6B) : .white)
            Divider().frame(height: 26).overlay(Palette.hairline)
            MetricPill(icon: "bolt.circle",
                       value: String(format: "%+.1fW", model.snapshot.watts),
                       caption: "flow")
            Divider().frame(height: 26).overlay(Palette.hairline)
            MetricPill(icon: "powerplug",
                       value: model.snapshot.adapter.map { "\($0.watts)W" } ?? "—",
                       caption: "adapter")
            Divider().frame(height: 26).overlay(Palette.hairline)
            MetricPill(icon: "clock",
                       value: timeEstimate,
                       caption: model.snapshot.isCharging ? "to full" : "left")
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 4)
        .glassCard(cornerRadius: 16, sheen: 0.16)
    }

    private var timeEstimate: String {
        let minutes = model.snapshot.isCharging ? model.snapshot.minutesToFull : model.snapshot.minutesToEmpty
        guard let minutes, minutes > 0 else { return "—" }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Label(String(format: "%.0f%% health", model.snapshot.healthPercent), systemImage: "heart.text.square")
            Text("·")
            Label("\(model.snapshot.cycleCount) cycles", systemImage: "arrow.triangle.2.circlepath")
            Spacer()
            if model.isCalibrating {
                Label("Calibrating", systemImage: "gauge.with.needle")
                    .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
            }
        }
        .font(.system(size: 9.5, weight: .medium, design: .rounded))
        .labelStyle(CompactLabelStyle())
        .foregroundStyle(.white.opacity(0.42))
    }
}

struct CompactLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.font(.system(size: 8.5, weight: .bold))
            configuration.title
        }
    }
}

/// Shown until the background service is approved: without it nothing can be changed.
struct ServiceBanner: View {
    @Environment(AppModel.self) private var model

    private var message: String {
        switch model.installState {
        case .enabled:
            return model.isConnected ? "" : "The background service is starting up."
        case .requiresApproval:
            return "Turn Voltaica on in Login Items to let it hold the charge limit."
        case .notRegistered:
            return "Install the background service to start limiting the charge."
        case .notFound:
            return "The background service is missing from the app bundle."
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "shield.lefthalf.filled")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(hex: 0xFFD166))

            Text(message)
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            switch model.installState {
            case .notRegistered, .notFound:
                Button("Install") { model.installHelper() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            case .requiresApproval:
                Button("Open") { model.openLoginItems() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            case .enabled:
                ProgressView().controlSize(.mini)
            }
        }
        .padding(10)
        .glassCard(cornerRadius: 14, tint: Color(hex: 0xFFD166), sheen: 0.18)
    }
}
