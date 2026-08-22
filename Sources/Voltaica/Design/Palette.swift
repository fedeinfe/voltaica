import SwiftUI
import VoltaicaCore

/// The colour language: one gradient per state, so the whole window reads as "charging",
/// "holding" or "cooling" before a single word is read.
enum Palette {
    static let ink = Color(red: 0.05, green: 0.06, blue: 0.08)
    static let hairline = Color.white.opacity(0.14)
    static let hairlineStrong = Color.white.opacity(0.30)
    static let mint = Color(hex: 0x7BF0C0)
    static let cyan = Color(hex: 0x35C9E8)

    static func accent(for mode: PolicyMode) -> [Color] {
        switch mode {
        case .charging, .topUp:
            return [Color(hex: 0xFFD98A), Color(hex: 0xFF9F45)]
        case .holding:
            return [Color(hex: 0x7BF0C0), Color(hex: 0x35C9E8)]
        case .discharging:
            return [Color(hex: 0xC9A6FF), Color(hex: 0x7B6CFF)]
        case .heatPaused:
            return [Color(hex: 0xFFAE7A), Color(hex: 0xFF5A5A)]
        case .paused:
            return [Color(hex: 0xD4DEE8), Color(hex: 0x8FA3B5)]
        case .onBattery:
            return [Color(hex: 0xA7ECFF), Color(hex: 0x5AA9FF)]
        case .calibrating:
            return [Color(hex: 0xFFE08A), Color(hex: 0xB78BFF)]
        case .disabled, .noBattery:
            return [Color(hex: 0xC3CBD4), Color(hex: 0x8892A0)]
        }
    }

    static func gradient(for mode: PolicyMode,
                         start: UnitPoint = .topLeading,
                         end: UnitPoint = .bottomTrailing) -> LinearGradient {
        LinearGradient(colors: accent(for: mode), startPoint: start, endPoint: end)
    }

    static func glow(for mode: PolicyMode) -> Color {
        accent(for: mode)[1].opacity(0.55)
    }

    static func symbol(for mode: PolicyMode) -> String {
        switch mode {
        case .charging, .topUp: return "bolt.fill"
        case .holding: return "pause.fill"
        case .discharging: return "arrow.down.circle.fill"
        case .heatPaused: return "thermometer.high"
        case .paused: return "hand.raised.fill"
        case .onBattery: return "battery.75"
        case .calibrating: return "gauge.with.needle"
        case .disabled: return "circle.slash"
        case .noBattery: return "questionmark.circle"
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}
