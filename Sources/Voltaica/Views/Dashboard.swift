import Charts
import SwiftUI
import VoltaicaCore

struct DashboardView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .overview

    enum Tab: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case history = "History"
        case health = "Health"
        case diagnostics = "Diagnostics"

        var id: String { rawValue }
        var symbol: String {
            switch self {
            case .overview: return "gauge.with.dots.needle.67percent"
            case .history: return "chart.xyaxis.line"
            case .health: return "heart.text.square"
            case .diagnostics: return "stethoscope"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            GlassTabBar(tab: $tab, colors: model.accentColors)
                .padding(.top, 26)
                .padding(.horizontal, 22)
                .padding(.bottom, 14)

            ScrollView {
                Group {
                    switch tab {
                    case .overview: OverviewTab()
                    case .history: HistoryTab()
                    case .health: HealthTab()
                    case .diagnostics: DiagnosticsTab()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
        }
        .frame(minWidth: 820, minHeight: 600)
        .background { AuroraBackdrop(colors: model.accentColors, intense: true) }
        .preferredColorScheme(.dark)
        .animation(.smooth(duration: 0.3), value: tab)
    }
}

private struct GlassTabBar: View {
    @Binding var tab: DashboardView.Tab
    var colors: [Color]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DashboardView.Tab.allCases) { candidate in
                Button {
                    tab = candidate
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: candidate.symbol)
                            .font(.system(size: 11, weight: .semibold))
                        Text(candidate.rawValue)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .foregroundStyle(tab == candidate ? AnyShapeStyle(Color.black) : AnyShapeStyle(Color.white.opacity(0.62)))
                    .background {
                        if tab == candidate {
                            Capsule().fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                                .shadow(color: colors[1].opacity(0.45), radius: 8, y: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(5)
        .glassCard(cornerRadius: 22, sheen: 0.18)
    }
}

// MARK: - Overview

private struct OverviewTab: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                heroCard
                policyCard
            }
            liveGrid
            todayCard
            Spacer(minLength: 0)
        }
    }

    /// The last day at a glance. The full charts live under History; this is the one line that
    /// answers "did the limit actually hold while I was working?".
    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(title: "Last 24 hours", systemImage: "clock.arrow.circlepath")
                Spacer()
                if let low = recent.map(\.p).min(), let high = recent.map(\.p).max() {
                    Text("\(Int(low.rounded()))–\(Int(high.rounded()))%")
                        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            if recent.count < 4 {
                Text("Collecting data. The service samples once a minute.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(height: 74, alignment: .center)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(recent) { sample in
                    AreaMark(x: .value("Time", sample.t), y: .value("Charge", sample.p))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [model.accentColors[0].opacity(0.42),
                                                                 .clear],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Time", sample.t), y: .value("Charge", sample.p))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                        .foregroundStyle(LinearGradient(colors: model.accentColors,
                                                        startPoint: .leading, endPoint: .trailing))
                }
                .chartYScale(domain: chartDomain)
                .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 6)) { value in
                    AxisValueLabel(format: .dateTime.hour())
                        .foregroundStyle(.white.opacity(0.35))
                } }
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel().foregroundStyle(.white.opacity(0.35))
                } }
                .frame(height: 74)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 20)
    }

    private var recent: [HistorySample] {
        let cutoff = Date().addingTimeInterval(-86_400)
        return model.history.filter { $0.t >= cutoff }
    }

    private var chartDomain: ClosedRange<Double> {
        let values = recent.map(\.p)
        guard let low = values.min(), let high = values.max() else { return 0...100 }
        return max(0, low - 6)...min(100, high + 6)
    }

    private var heroCard: some View {
        VStack(spacing: 14) {
            ChargeRing(charge: model.snapshot.rawPercentage,
                       limit: model.configuration.clampedLimit,
                       limitActive: model.configuration.isLimitActive,
                       colors: model.accentColors,
                       mode: model.decision.mode,
                       size: 186)

            Text(model.decision.detail)
                .font(.system(size: 12.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.66))
                .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                stat("macOS reads", "\(model.snapshot.percentage)%")
                stat("hardware", String(format: "%.1f%%", model.snapshot.rawPercentage))
                stat("in the pack", "\(model.snapshot.rawCurrentCapacity) mAh")
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 24, tint: model.accentColors[1], elevated: true)
    }

    private func stat(_ caption: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(caption)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
        }
    }

    private var policyCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Policy", systemImage: "slider.horizontal.3")

            HStack {
                Text("Charge limit")
                    .font(.system(size: 12.5, weight: .medium, design: .rounded))
                Spacer()
                MetricText(value: model.configuration.enabled ? "\(model.configuration.clampedLimit)%" : "off", size: 14)
                    .foregroundStyle(LinearGradient(colors: model.accentColors,
                                                    startPoint: .leading, endPoint: .trailing))
            }

            LimitSlider(value: Binding(get: { model.configuration.clampedLimit },
                                       set: { model.setLimit($0) }),
                        colors: model.accentColors,
                        onEditingChanged: { editing in
                            model.isDraggingLimit = editing
                            if !editing { model.pushNow() }
                        })
                .disabled(!model.configuration.enabled)
                .opacity(model.configuration.enabled ? 1 : 0.4)

            Divider().overlay(Palette.hairline)

            row("Sailing", model.configuration.sailingEnabled
                ? "resume below \(max(20, model.configuration.clampedLimit - model.configuration.sailingDepth))%"
                : "off")
            row("Heat protection", model.configuration.heatProtectionEnabled
                ? String(format: "pause above %.0f°C", model.configuration.heatThreshold)
                : "off")
            row("Firmware ceiling", model.configuration.hardwareCeilingEnabled ? "on (about 80%)" : "off")
            row("Scheduled top-up", model.configuration.scheduledTopUp.enabled
                ? "full by \(model.configuration.scheduledTopUp.timeLabel)"
                : "off")
            row("Charger", "\(model.hardware.chargingAllowed ? "allowed" : "inhibited"), adapter \(model.hardware.adapterEnabled ? "on" : "cut")")

            if let error = model.helperError {
                Text(error)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Color(hex: 0xFF8A80))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 330, alignment: .leading)
        .glassCard(cornerRadius: 24, elevated: true)
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        }
    }

    private var liveGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
            LiveTile(icon: "thermometer.medium",
                     title: "Temperature",
                     value: String(format: "%.1f", model.snapshot.temperature),
                     unit: "°C",
                     tint: model.snapshot.temperatureIsElevated ? Color(hex: 0xFF9F6B) : Color(hex: 0x7BF0C0))
            LiveTile(icon: "bolt.circle",
                     title: model.snapshot.watts >= 0 ? "Charging at" : "Drawing",
                     value: String(format: "%.1f", abs(model.snapshot.watts)),
                     unit: "W",
                     tint: Color(hex: 0xFFD98A))
            LiveTile(icon: "waveform.path.ecg",
                     title: "Pack voltage",
                     value: String(format: "%.2f", model.snapshot.voltage),
                     unit: "V",
                     tint: Color(hex: 0xA7ECFF))
            LiveTile(icon: "powerplug",
                     title: "System draw",
                     value: String(format: "%.1f", model.snapshot.systemPowerIn),
                     unit: "W",
                     tint: Color(hex: 0xC9A6FF))
        }
    }
}

struct LiveTile: View {
    var icon: String
    var title: String
    var value: String
    var unit: String
    var tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                MetricText(value: value, size: 24, weight: .bold)
                    .foregroundStyle(.white)
                Text(unit)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassCard(cornerRadius: 18, tint: tint, sheen: 0.16)
    }
}

// MARK: - History

private struct HistoryTab: View {
    @Environment(AppModel.self) private var model

    private var summary: (min: Double, max: Double, avgTemp: Double, cycles: Double) {
        HistoryStore.summary(model.history)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                SectionLabel(title: "Charge history", systemImage: "chart.xyaxis.line")
                Spacer()
                Picker("", selection: Binding(get: { model.historyRange },
                                              set: { model.historyRange = $0; model.loadHistory() })) {
                    ForEach(AppModel.HistoryRange.allCases) { range in
                        Text(range.rawValue).tag(range)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .labelsHidden()
            }

            if model.history.isEmpty {
                emptyState
            } else {
                chargeChart
                HStack(spacing: 14) {
                    temperatureChart
                    statsCard
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.white.opacity(0.25))
            Text("No samples yet")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
            Text("The background service records one sample a minute. Come back in a little while.")
                .font(.system(size: 11.5, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .glassCard(cornerRadius: 22)
    }

    private var chargeChart: some View {
        Chart(model.history) { sample in
            AreaMark(x: .value("Time", sample.t), y: .value("Charge", sample.p))
                .foregroundStyle(
                    LinearGradient(colors: [model.accentColors[1].opacity(0.55),
                                            model.accentColors[1].opacity(0.02)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .interpolationMethod(.monotone)

            LineMark(x: .value("Time", sample.t), y: .value("Charge", sample.p))
                .foregroundStyle(LinearGradient(colors: model.accentColors,
                                                startPoint: .leading, endPoint: .trailing))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(values: [0, 25, 50, 75, 100]) {
                AxisGridLine().foregroundStyle(Color.white.opacity(0.07))
                AxisValueLabel().foregroundStyle(Color.white.opacity(0.4))
            }
        }
        .chartXAxis {
            AxisMarks {
                AxisGridLine().foregroundStyle(Color.white.opacity(0.05))
                AxisValueLabel().foregroundStyle(Color.white.opacity(0.4))
            }
        }
        .frame(height: 230)
        .padding(16)
        .glassCard(cornerRadius: 22, elevated: true)
    }

    private var temperatureChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Temperature", systemImage: "thermometer.medium")
            Chart(model.history) { sample in
                LineMark(x: .value("Time", sample.t), y: .value("°C", sample.c))
                    .foregroundStyle(Color(hex: 0xFF9F6B))
                    .lineStyle(StrokeStyle(lineWidth: 1.6))
                    .interpolationMethod(.monotone)
            }
            .chartYAxis {
                AxisMarks {
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.06))
                    AxisValueLabel().foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 130)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 20)
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "In this window", systemImage: "sum")
            statRow("Lowest", String(format: "%.0f%%", summary.min))
            statRow("Highest", String(format: "%.0f%%", summary.max))
            statRow("Average temperature", String(format: "%.1f°C", summary.avgTemp))
            statRow("Charge put back", String(format: "%.2f full cycles", summary.cycles))
            statRow("Samples", "\(model.history.count)")
        }
        .padding(16)
        .frame(width: 260, alignment: .leading)
        .glassCard(cornerRadius: 20)
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}
