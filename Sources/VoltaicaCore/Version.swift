import Foundation

/// Single source of truth for the version. The packaging script reads these strings straight
/// out of this file so the app, the daemon and the DMG can never disagree.
public enum VoltaicaVersion {
    public static let marketing = "1.0.2"
    public static let build = "6"
    public static var full: String { "\(marketing) (\(build))" }
}

/// An event the daemon saw, kept around so the app can raise a notification for it even if the
/// app was not running at the time.
public struct TimestampedEvent: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var event: PolicyEvent
    public var at: Date
    public var detail: String

    public init(event: PolicyEvent, at: Date = Date(), detail: String = "") {
        self.id = UUID()
        self.event = event
        self.at = at
        self.detail = detail
    }

    public var title: String {
        switch event {
        case .limitReached: return "Charge limit reached"
        case .chargingResumed: return "Charging resumed"
        case .topUpFinished: return "Top-up complete"
        case .dischargeFinished: return "Target charge reached"
        case .heatPauseStarted: return "Charging paused, battery warm"
        case .heatPauseEnded: return "Battery cooled down"
        case .calibrationAdvanced: return "Calibration step complete"
        case .calibrationFinished: return "Calibration finished"
        }
    }
}

/// One row of the charge history the daemon keeps on disk.
public struct HistorySample: Codable, Sendable, Equatable, Identifiable {
    public var id: Date { t }
    /// Timestamp.
    public var t: Date
    /// Raw charge percentage.
    public var p: Double
    /// Battery temperature in °C.
    public var c: Double
    /// Power in watts, positive while charging.
    public var w: Double
    /// Policy mode at the time.
    public var m: String
    /// Whether the adapter was connected.
    public var a: Bool

    public init(t: Date, p: Double, c: Double, w: Double, m: String, a: Bool) {
        self.t = t
        self.p = p
        self.c = c
        self.w = w
        self.m = m
        self.a = a
    }

    public var mode: PolicyMode { PolicyMode(rawValue: m) ?? .disabled }
}

public enum HistoryPaths {
    public static var samplesURL: URL {
        URL(fileURLWithPath: VoltaicaIdentifiers.supportDirectory, isDirectory: true)
            .appendingPathComponent("samples.jsonl")
    }
}
