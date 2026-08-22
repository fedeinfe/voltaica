import Foundation
import VoltaicaCore
import os

/// Keeps the last few policy transitions so the app can turn them into notifications, and
/// appends the charge history the graphs are drawn from.
///
/// A root daemon has no user session to post notifications into, so it records instead and lets
/// the app catch up whenever it next connects.
final class EventBridge {
    static let shared = EventBridge()

    private let log = Logger(subsystem: VoltaicaIdentifiers.helper, category: "events")
    private let queue = DispatchQueue(label: "\(VoltaicaIdentifiers.helper).events")
    private var events: [TimestampedEvent] = []
    private var lastSampleAt = Date.distantPast

    private let maxEvents = 40
    private let sampleInterval: TimeInterval = 60
    private let retention: TimeInterval = 30 * 86_400

    private init() {}

    func publish(_ list: [PolicyEvent], snapshot: BatterySnapshot, decision: PolicyDecision) {
        queue.async { [self] in
            for event in list {
                events.append(TimestampedEvent(event: event, detail: decision.detail))
            }
            if events.count > maxEvents { events.removeFirst(events.count - maxEvents) }
        }
    }

    func recent() -> [TimestampedEvent] {
        queue.sync { events }
    }

    /// Appends one line per minute. JSON Lines keeps it appendable, greppable and cheap to trim.
    func record(snapshot: BatterySnapshot, decision: PolicyDecision) {
        queue.async { [self] in
            let now = Date()
            guard now.timeIntervalSince(lastSampleAt) >= sampleInterval else { return }
            lastSampleAt = now

            let sample = HistorySample(t: now,
                                       p: snapshot.rawPercentage,
                                       c: snapshot.temperature,
                                       w: snapshot.watts,
                                       m: decision.mode.rawValue,
                                       a: snapshot.isPluggedIn)
            guard var line = try? JSONEncoder().encode(sample) else { return }
            line.append(0x0a)

            let url = HistoryPaths.samplesURL
            let manager = FileManager.default
            if !manager.fileExists(atPath: url.path) {
                try? line.write(to: url, options: .atomic)
                try? manager.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
                return
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            }
        }
    }

    /// Drops samples older than the retention window. Cheap enough to run once an hour.
    func trimHistory() {
        queue.async { [self] in
            let url = HistoryPaths.samplesURL
            guard let data = try? Data(contentsOf: url), data.count > 512_000 else { return }
            let cutoff = Date().addingTimeInterval(-retention)
            let decoder = JSONDecoder()
            var kept = Data()
            for line in data.split(separator: 0x0a) where !line.isEmpty {
                guard let sample = try? decoder.decode(HistorySample.self, from: Data(line)) else { continue }
                guard sample.t >= cutoff else { continue }
                kept.append(contentsOf: line)
                kept.append(0x0a)
            }
            try? kept.write(to: url, options: .atomic)
            log.notice("history trimmed to \(kept.count, privacy: .public) bytes")
        }
    }
}
