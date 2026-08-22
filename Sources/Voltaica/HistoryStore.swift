import Foundation
import VoltaicaCore

/// Reads the sample log the daemon appends to. Parsing is line by line so a partially written
/// last line never breaks the graphs.
enum HistoryStore {
    static func load(since cutoff: Date, limit: Int = 20_000) -> [HistorySample] {
        guard let data = try? Data(contentsOf: HistoryPaths.samplesURL) else { return [] }
        let decoder = JSONDecoder()
        var samples: [HistorySample] = []
        samples.reserveCapacity(2_000)

        for line in data.split(separator: 0x0a) where line.count > 8 {
            guard let sample = try? decoder.decode(HistorySample.self, from: Data(line)) else { continue }
            guard sample.t >= cutoff else { continue }
            samples.append(sample)
        }
        if samples.count > limit {
            // Thin evenly rather than dropping the tail, so the shape of the curve survives.
            let stride = samples.count / limit + 1
            samples = samples.enumerated().compactMap { $0.offset % stride == 0 ? $0.element : nil }
        }
        return samples
    }

    static func summary(_ samples: [HistorySample]) -> (min: Double, max: Double, avgTemp: Double, cycles: Double) {
        guard !samples.isEmpty else { return (0, 0, 0, 0) }
        let charges = samples.map(\.p)
        let temps = samples.map(\.c).filter { $0 > 0 }
        // Charge actually put back into the pack, in whole-battery equivalents.
        var accumulated: Double = 0
        for index in 1..<max(samples.count, 1) {
            let delta = samples[index].p - samples[index - 1].p
            if delta > 0 { accumulated += delta }
        }
        return (charges.min() ?? 0,
                charges.max() ?? 0,
                temps.isEmpty ? 0 : temps.reduce(0, +) / Double(temps.count),
                accumulated / 100)
    }
}
