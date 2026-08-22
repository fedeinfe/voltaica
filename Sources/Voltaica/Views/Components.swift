import SwiftUI
import VoltaicaCore

/// The hero: a charge dial with the limit marked on the track, so the relationship between
/// where the battery is and where it is allowed to go is visible at a glance.
struct ChargeRing: View {
    var charge: Double
    var limit: Int
    var limitActive: Bool
    var colors: [Color]
    var mode: PolicyMode
    var size: CGFloat = 158

    private var fraction: Double { min(1, max(0, charge / 100)) }
    private var lineWidth: CGFloat { size * 0.085 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.07), lineWidth: lineWidth)

            // The stretch above the limit, drawn faintly: the part we deliberately leave empty.
            if limitActive {
                Circle()
                    .trim(from: Double(limit) / 100, to: 1)
                    .stroke(Color.white.opacity(0.035), lineWidth: lineWidth)
                    .rotationEffect(.degrees(-90))
            }

            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(colors: colors + [colors[0]],
                                    center: .center,
                                    startAngle: .degrees(-90),
                                    endAngle: .degrees(270)),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .shadow(color: colors[1].opacity(0.55), radius: 12)

            if limitActive {
                LimitTick(fraction: Double(limit) / 100, ringSize: size, lineWidth: lineWidth)
            }

            centre
        }
        .frame(width: size, height: size)
        .animation(.smooth(duration: 0.7), value: fraction)
        .animation(.smooth(duration: 0.4), value: limit)
    }

    private var centre: some View {
        VStack(spacing: 1) {
            HStack(alignment: .top, spacing: 1) {
                MetricText(value: String(format: "%.0f", charge), size: size * 0.30, weight: .bold)
                Text("%")
                    .font(.system(size: size * 0.13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .padding(.top, size * 0.05)
            }
            .foregroundStyle(.white)

            Label(mode.label, systemImage: Palette.symbol(for: mode))
                .font(.system(size: size * 0.072, weight: .medium, design: .rounded))
                .foregroundStyle(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                .labelStyle(.titleAndIcon)
                .lineLimit(1)
        }
    }
}

/// A notch on the ring showing where charging stops.
private struct LimitTick: View {
    var fraction: Double
    var ringSize: CGFloat
    var lineWidth: CGFloat

    var body: some View {
        Capsule()
            .fill(Color.white.opacity(0.85))
            .frame(width: 2.2, height: lineWidth + 5)
            .offset(y: -(ringSize - lineWidth) / 2)
            .rotationEffect(.degrees(fraction * 360))
            .shadow(color: .black.opacity(0.4), radius: 2)
    }
}

/// Slider with a glass thumb, a lit track and snap points at the charge levels people use.
struct LimitSlider: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 20...100
    var colors: [Color]
    var onEditingChanged: (Bool) -> Void = { _ in }

    private let notches = [50, 60, 70, 80, 90]
    @State private var isDragging = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let fraction = Double(value - range.lowerBound) / Double(range.upperBound - range.lowerBound)
            let thumbX = max(11, min(width - 11, fraction * width))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.10))
                    .frame(height: 7)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                            .frame(width: thumbX, height: 7)
                            .shadow(color: colors[1].opacity(0.6), radius: 7, y: 1)
                    }
                    .clipShape(Capsule())

                ForEach(notches, id: \.self) { notch in
                    let x = Double(notch - range.lowerBound) / Double(range.upperBound - range.lowerBound) * width
                    Circle()
                        .fill(Color.white.opacity(value >= notch ? 0.55 : 0.20))
                        .frame(width: 3, height: 3)
                        .offset(x: x - 1.5)
                }

                Circle()
                    .fill(.white)
                    .frame(width: 21, height: 21)
                    .overlay(
                        Circle().strokeBorder(LinearGradient(colors: [.white, .white.opacity(0.35)],
                                                             startPoint: .top, endPoint: .bottom),
                                              lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.32), radius: 5, y: 2)
                    .scaleEffect(isDragging ? 1.16 : 1)
                    .offset(x: thumbX - 10.5)
            }
            .frame(height: 26)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        if !isDragging {
                            isDragging = true
                            onEditingChanged(true)
                        }
                        update(from: drag.location.x, width: width)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
            .animation(.snappy(duration: 0.18), value: isDragging)
        }
        .frame(height: 26)
    }

    private func update(from x: Double, width: Double) {
        guard width > 0 else { return }
        let fraction = min(1, max(0, x / width))
        let raw = Double(range.lowerBound) + fraction * Double(range.upperBound - range.lowerBound)
        var next = Int(raw.rounded())
        // Gentle magnetism towards the levels people actually pick.
        for notch in notches + [range.lowerBound, range.upperBound] where abs(next - notch) <= 1 {
            next = notch
        }
        if next != value { value = next }
    }
}

/// Capsule button with glass fill, used for every quick action.
struct GlassButton: View {
    var title: String
    var systemImage: String
    var tint: Color?
    var prominent: Bool = false
    var action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                Text(title)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(prominent ? AnyShapeStyle(.black) : AnyShapeStyle(.white))
            .background {
                if prominent, let tint {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.95), tint.opacity(0.75)],
                                             startPoint: .top, endPoint: .bottom))
                        .shadow(color: tint.opacity(0.5), radius: 8, y: 2)
                } else {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.white.opacity(isHovering ? 0.16 : 0.09))
                        .overlay(
                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                .strokeBorder(Color.white.opacity(isHovering ? 0.30 : 0.16), lineWidth: 0.8)
                        )
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(.easeOut(duration: 0.14), value: isHovering)
    }
}

/// One reading: a label, a value and an optional unit, sized for a dense row.
struct MetricPill: View {
    var icon: String
    var value: String
    var caption: String
    var tint: Color = .white

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint.opacity(0.9))
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(caption)
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Small coloured dot with a matching halo, used in headers to carry state.
struct StatusDot: View {
    var colors: [Color]
    var pulsing: Bool

    @State private var animate = false

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .frame(width: 8, height: 8)
            .shadow(color: colors[1].opacity(0.9), radius: animate && pulsing ? 7 : 3)
            .scaleEffect(animate && pulsing ? 1.15 : 1)
            .onAppear {
                guard pulsing else { return }
                withAnimation(.easeInOut(duration: 1.3).repeatForever(autoreverses: true)) {
                    animate = true
                }
            }
    }
}

/// Section header used across the dashboard.
struct SectionLabel: View {
    var title: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
            }
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .tracking(0.8)
        }
        .foregroundStyle(.white.opacity(0.42))
    }
}


/// Label on the left, switch pinned right, the way System Settings does it. Checkboxes are the
/// SwiftUI default on macOS and look wrong next to everything else here.
struct SwitchRow: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.label
            Spacer(minLength: 8)
            Toggle("", isOn: configuration.$isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
        }
    }
}
