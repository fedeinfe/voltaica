import Foundation
import VoltaicaCore
import os

/// Persists the policy where only root can write it, so the limit survives reboots and works
/// with nobody logged in.
struct PolicyStore {
    private let log = Logger(subsystem: VoltaicaIdentifiers.helper, category: "store")
    private let directory = URL(fileURLWithPath: VoltaicaIdentifiers.supportDirectory, isDirectory: true)

    private var configurationURL: URL { directory.appendingPathComponent("policy.json") }
    private var historyURL: URL { directory.appendingPathComponent("calibration.json") }
    private var licenseURL: URL { directory.appendingPathComponent("license.json") }
    private var firstRunURL: URL { directory.appendingPathComponent("first-run") }

    func prepare() {
        guard !FileManager.default.fileExists(atPath: directory.path) else { return }
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o755])
    }

    func loadConfiguration() -> ChargeConfiguration {
        guard let data = try? Data(contentsOf: configurationURL),
              let config = try? JSONDecoder().decode(ChargeConfiguration.self, from: data) else {
            return ChargeConfiguration()
        }
        return config.validated()
    }

    func save(_ configuration: ChargeConfiguration) {
        prepare()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(configuration).write(to: configurationURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                                   ofItemAtPath: configurationURL.path)
        } catch {
            log.error("could not persist policy: \(error.localizedDescription, privacy: .public)")
        }
    }

    func loadLicenseKey() -> String? {
        guard let data = try? Data(contentsOf: licenseURL),
              let stored = try? JSONDecoder().decode([String: String].self, from: data) else { return nil }
        return stored["key"]
    }

    func save(licenseKey: String?) {
        prepare()
        guard let licenseKey else {
            try? FileManager.default.removeItem(at: licenseURL)
            return
        }
        try? JSONEncoder().encode(["key": licenseKey]).write(to: licenseURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o644],
                                               ofItemAtPath: licenseURL.path)
    }

    /// Trial start, stamped once. Kept in a file the daemon owns rather than user defaults, so it
    /// is per machine and not per account.
    func firstRun() -> Date {
        prepare()
        if let attributes = try? FileManager.default.attributesOfItem(atPath: firstRunURL.path),
           let created = attributes[.creationDate] as? Date {
            return created
        }
        let now = Date()
        try? Data().write(to: firstRunURL, options: .atomic)
        return now
    }

    func loadHistory() -> CalibrationHistory {
        guard let data = try? Data(contentsOf: historyURL),
              let history = try? JSONDecoder().decode(CalibrationHistory.self, from: data) else {
            return CalibrationHistory()
        }
        return history
    }

    func save(_ history: CalibrationHistory) {
        prepare()
        try? JSONEncoder().encode(history).write(to: historyURL, options: .atomic)
    }
}
