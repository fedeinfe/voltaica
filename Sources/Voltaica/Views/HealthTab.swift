import SwiftUI
import VoltaicaCore

/// Everything the gas gauge knows about how the pack is ageing, plus the calibration control.
struct HealthTab: View {
    @Environment(AppModel.self) private var model
    @State private var showCalibrationSheet = false

    private var snapshot: BatterySnapshot { model.snapshot }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 16) {
                healthCard
                capacityCard
            }
            HStack(alignment: .top, spacing: 16) {
                cellsCard
                calibrationCard
            }
            lifetimeCard
        }
        .sheet(isPresented: $showCalibrationSheet) {
            CalibrationSheet(isPresented: $showCalibrationSheet)
                .environment(model)
        }
    }

    private var healthCard: some View {
        VStack(spacing: 12) {
            SectionLabel(title: "Battery health", systemImage: "heart.text.square")
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                MetricText(value: String(format: "%.1f", snapshot.healthPercent), size: 42, weight: .bold)
                Text("%")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .foregroundStyle(.white)

            HealthBar(value: snapshot.healthPercent, colors: model.accentColors)

            VStack(spacing: 5) {
                detail("Measured health", String(format: "%.1f%%", snapshot.measuredHealthPercent))
                detail("Cycles", "\(snapshot.cycleCount) of \(snapshot.designCycleCount > 0 ? "\(snapshot.designCycleCount)" : "1000")")
                detail("Cell disconnects", "\(snapshot.cellDisconnectCount)")
                if let failure = snapshot.permanentFailure {
                    detail("Permanent failure", failure)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 22, tint: model.accentColors[1], elevated: true)
    }

    private var capacityCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Capacity", systemImage: "battery.100")
            CapacityBars(design: snapshot.designCapacity,
                         nominal: snapshot.nominalCapacity,
                         measured: snapshot.rawMaxCapacity,
                         current: snapshot.rawCurrentCapacity,
                         colors: model.accentColors)
            detail("Design", "\(snapshot.designCapacity) mAh")
            detail("Nominal today", "\(snapshot.nominalCapacity) mAh")
            detail("Measured full charge", "\(snapshot.rawMaxCapacity) mAh")
            detail("Charge right now", "\(snapshot.rawCurrentCapacity) mAh")
            detail("Gas gauge", snapshot.gasGauge.isEmpty ? "unknown" : snapshot.gasGauge)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22, elevated: true)
    }

    private var cellsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Cells", systemImage: "square.stack.3d.up")
            if snapshot.cellVoltages.isEmpty {
                Text("No per-cell readings on this Mac.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            } else {
                ForEach(Array(snapshot.cellVoltages.enumerated()), id: \.offset) { index, voltage in
                    HStack(spacing: 10) {
                        Text("Cell \(index + 1)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.55))
                            .frame(width: 46, alignment: .leading)
                        CellBar(voltage: voltage, colors: model.accentColors)
                        Text(String(format: "%.3f V", voltage))
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(.white)
                    }
                }
                let spread = (snapshot.cellVoltages.max() ?? 0) - (snapshot.cellVoltages.min() ?? 0)
                detail("Imbalance", String(format: "%.0f mV", spread * 1000))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
    }

    private var calibrationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Calibration", systemImage: "gauge.with.needle")

            if let session = model.configuration.calibration, session.isActive {
                Text(session.phase.label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(LinearGradient(colors: model.accentColors,
                                                    startPoint: .leading, endPoint: .trailing))
                Text("Started \(session.startedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                CalibrationProgress(phase: session.phase, colors: model.accentColors)
                Button("Stop calibration") { model.stopCalibration() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else {
                Text("A full charge, a soak at 100%, a run down and a recharge. It resyncs the gas gauge so the percentage you see matches the charge that is really there.")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)

                if let last = model.calibrationHistory.lastCompleted {
                    detail("Last completed", last.formatted(date: .abbreviated, time: .omitted))
                } else {
                    detail("Last completed", "never")
                }

                Button {
                    showCalibrationSheet = true
                } label: {
                    Label("Start calibration", systemImage: "play.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!model.isConnected)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 320, alignment: .leading)
        .glassCard(cornerRadius: 22)
    }

    private var lifetimeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Lifetime", systemImage: "clock.arrow.circlepath")
            HStack(spacing: 0) {
                lifetimeStat("Highest temperature", String(format: "%.0f°C", snapshot.lifetimeMaxTemperature))
                lifetimeStat("Average temperature", String(format: "%.1f°C", snapshot.lifetimeAvgTemperature))
                lifetimeStat("Hours in service", "\(snapshot.totalOperatingHours)")
                lifetimeStat("Today's range", "\(snapshot.dailyMinSoc)–\(snapshot.dailyMaxSoc)%")
                lifetimeStat("Serial", snapshot.serial.isEmpty ? "—" : String(snapshot.serial.suffix(6)))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(cornerRadius: 22)
    }

    private func lifetimeStat(_ caption: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(caption)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.42))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private func detail(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.55))
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.92))
        }
    }
}

private struct HealthBar: View {
    var value: Double
    var colors: [Color]

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.09))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * min(1, value / 100))
                    .shadow(color: colors[1].opacity(0.5), radius: 6)
            }
        }
        .frame(height: 8)
    }
}

private struct CapacityBars: View {
    var design: Int
    var nominal: Int
    var measured: Int
    var current: Int
    var colors: [Color]

    var body: some View {
        VStack(spacing: 6) {
            bar(value: design, total: design, opacity: 0.16, label: "design")
            bar(value: nominal, total: design, opacity: 0.45, label: "nominal")
            bar(value: measured, total: design, opacity: 0.7, label: "measured")
            bar(value: current, total: design, opacity: 1, label: "now")
        }
    }

    private func bar(value: Int, total: Int, opacity: Double, label: String) -> some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.07))
                Capsule()
                    .fill(LinearGradient(colors: colors.map { $0.opacity(opacity) },
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: total > 0 ? geometry.size.width * min(1, Double(value) / Double(total)) : 0)
            }
        }
        .frame(height: 7)
    }
}

private struct CellBar: View {
    var voltage: Double
    var colors: [Color]

    /// Lithium cells live between roughly 3.0 V empty and 4.35 V full.
    private var fraction: Double { min(1, max(0, (voltage - 3.0) / 1.35)) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule()
                    .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 7)
    }
}

private struct CalibrationProgress: View {
    var phase: CalibrationSession.Phase
    var colors: [Color]

    private let order: [CalibrationSession.Phase] = [.chargingToFull, .soaking, .discharging, .recharging]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(order, id: \.self) { step in
                Capsule()
                    .fill(reached(step)
                          ? AnyShapeStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                          : AnyShapeStyle(Color.white.opacity(0.12)))
                    .frame(height: 5)
            }
        }
    }

    private func reached(_ step: CalibrationSession.Phase) -> Bool {
        guard let current = order.firstIndex(of: phase), let target = order.firstIndex(of: step) else {
            return phase == .finished
        }
        return target <= current
    }
}

private struct CalibrationSheet: View {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calibrate the battery")
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            Text("""
                 Voltaica will charge to 100%, hold there for an hour, run the battery down to \
                 about 15% and charge it back up. It takes a few hours and it uses one charge \
                 cycle, so it is worth doing a couple of times a year, not weekly.

                 Keep the Mac plugged in for the whole run. You can stop at any point.
                 """)
                .font(.system(size: 12, design: .rounded))
                .foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Not now") { isPresented = false }
                    .buttonStyle(.bordered)
                Button("Start") {
                    model.startCalibration()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 420)
        .background { AuroraBackdrop(colors: model.accentColors) }
        .preferredColorScheme(.dark)
    }
}
