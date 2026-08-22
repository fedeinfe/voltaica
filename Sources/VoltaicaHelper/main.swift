import Foundation
import VoltaicaCore
import os

let log = Logger(subsystem: VoltaicaIdentifiers.helper, category: "main")

// The charger keys are root-only; running unprivileged would silently do nothing.
guard getuid() == 0 else {
    FileHandle.standardError.write(Data("VoltaicaHelper must run as root\n".utf8))
    exit(EXIT_FAILURE)
}

log.notice("VoltaicaHelper \(VoltaicaVersion.full, privacy: .public) starting")

let service = HelperService()
PolicyRunner.shared.start()
service.run()
SleepWatcher.shared.start()

// launchd sends SIGTERM on unload, on shutdown and when the app unregisters us. Give the
// charger back to macOS before going away, so a removed daemon can never leave a Mac that
// refuses to charge.
for signalNumber in [SIGTERM, SIGINT] {
    signal(signalNumber, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
    source.setEventHandler {
        log.notice("signal \(signalNumber, privacy: .public), releasing charger")
        PolicyRunner.shared.shutdown(releaseCharger: true)
        exit(EXIT_SUCCESS)
    }
    source.resume()
    SignalSources.keep.append(source)
}

enum SignalSources {
    static var keep: [DispatchSourceSignal] = []
}

CFRunLoopRun()
