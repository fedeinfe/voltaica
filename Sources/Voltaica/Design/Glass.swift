import SwiftUI

/// Layered glass: a blurred base, a specular sheen across the top edge, a refracted hairline
/// and an optional colour bleed from whatever state the view is in.
///
/// macOS 26 draws the base with the system's own glass material; earlier releases fall back to
/// `ultraThinMaterial`, which is the same idea with less depth.
struct GlassSurface<S: InsettableShape>: View {
    var shape: S
    var tint: Color?
    var sheen: Double = 0.22
    var elevated: Bool = false

    var body: some View {
        ZStack {
            base
            shape
                .fill(
                    LinearGradient(stops: [
                        .init(color: .white.opacity(sheen), location: 0),
                        .init(color: .white.opacity(sheen * 0.25), location: 0.35),
                        .init(color: .clear, location: 0.62),
                        .init(color: .white.opacity(sheen * 0.10), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                )
                .blendMode(.plusLighter)
            if let tint {
                shape.fill(
                    RadialGradient(colors: [tint.opacity(0.30), .clear],
                                   center: .topLeading,
                                   startRadius: 0,
                                   endRadius: 220)
                )
                .blendMode(.plusLighter)
            }
            shape
                .strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.42), .white.opacity(0.06), .white.opacity(0.18)],
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing),
                    lineWidth: 0.8
                )
        }
        .compositingGroup()
        .shadow(color: .black.opacity(elevated ? 0.34 : 0.18),
                radius: elevated ? 22 : 10,
                x: 0,
                y: elevated ? 12 : 5)
    }

    // The compiler guard is not redundant with the availability check: `glassEffect` does not
    // exist in the macOS 15 SDK at all, so an older toolchain has to not see the call.
    @ViewBuilder private var base: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            shape.fill(.clear).glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
        #else
        shape.fill(.ultraThinMaterial)
        #endif
    }
}

extension View {
    /// A card: rounded glass with a state tint.
    func glassCard(cornerRadius: CGFloat = 20,
                   tint: Color? = nil,
                   sheen: Double = 0.22,
                   elevated: Bool = false) -> some View {
        background(
            GlassSurface(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous),
                         tint: tint,
                         sheen: sheen,
                         elevated: elevated)
        )
    }

    func glassCapsule(tint: Color? = nil, sheen: Double = 0.26) -> some View {
        background(GlassSurface(shape: Capsule(style: .continuous), tint: tint, sheen: sheen))
    }

    /// A hairline separator that reads as an edge rather than a line.
    func hairlineTop() -> some View {
        overlay(alignment: .top) {
            LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 0.8)
        }
    }
}

/// Backdrop for panels and windows: a deep graphite wash with two coloured pools of light that
/// drift with the current state.
struct AuroraBackdrop: View {
    var colors: [Color]
    var intense: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x14171C), Color(hex: 0x0A0C10)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [colors[0].opacity(intense ? 0.34 : 0.22), .clear],
                           center: .init(x: 0.14, y: 0.04),
                           startRadius: 0,
                           endRadius: 320)
            RadialGradient(colors: [colors[1].opacity(intense ? 0.30 : 0.18), .clear],
                           center: .init(x: 0.92, y: 0.96),
                           startRadius: 0,
                           endRadius: 340)
        }
        .ignoresSafeArea()
    }
}

/// Numbers that animate between values instead of snapping.
struct MetricText: View {
    var value: String
    var size: CGFloat
    var weight: Font.Weight = .semibold

    var body: some View {
        Text(value)
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .contentTransition(.numericText())
    }
}
