import Foundation
import IOKit

/// Charger control through `AppleSmartBatteryManagerUserClient`.
///
/// This is the interface Apple publishes in the AppleSmartBatteryManager sources: two scalar
/// methods, one that stops the charger and one that makes the Mac ignore wall power and run off
/// the battery. It is the only mechanism that works on Apple Silicon running macOS 26 — the SMC
/// charger keys the community documented (`CH0B`, `CH0C`, `CH0I`, `CHWA`) are simply not in the
/// key table any more, so this replaces them rather than supplementing them.
///
/// The kernel clears both flags when the connection closes, so a daemon that crashes or is
/// stopped can never leave a Mac that refuses to charge.
public final class SmartBatteryControl {
    public enum Failure: LocalizedError {
        case serviceNotFound
        case notPrivileged
        case openFailed(kern_return_t)
        case callFailed(String, kern_return_t)

        public var errorDescription: String? {
            switch self {
            case .serviceNotFound: return "AppleSmartBatteryManager is not present on this Mac"
            case .notPrivileged: return "Charger control needs root"
            case .openFailed(let kr): return "IOServiceOpen failed (0x\(String(format: "%08x", kr)))"
            case .callFailed(let name, let kr): return "\(name) failed (0x\(String(format: "%08x", kr)))"
            }
        }
    }

    private enum Method: UInt32 {
        case inflowDisable = 0
        case chargeInhibit = 1
    }

    private var connection: io_connect_t = 0

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault,
                                                 IOServiceMatching("AppleSmartBatteryManager"))
        guard service != 0 else { throw Failure.serviceNotFound }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard result == kIOReturnSuccess else {
            throw result == kIOReturnNotPrivileged ? Failure.notPrivileged : Failure.openFailed(result)
        }
        connection = conn
    }

    deinit {
        guard connection != 0 else { return }
        // Belt and braces: the kext already restores both flags on close.
        try? call(.chargeInhibit, false)
        try? call(.inflowDisable, false)
        IOServiceClose(connection)
    }

    /// Stops the charger while leaving the Mac powered from the adapter.
    public func setChargeInhibited(_ inhibited: Bool) throws {
        try call(.chargeInhibit, inhibited)
    }

    /// Makes the Mac ignore wall power, so it runs the battery down while still plugged in.
    public func setInflowDisabled(_ disabled: Bool) throws {
        try call(.inflowDisable, disabled)
    }

    public func releaseAll() {
        try? call(.chargeInhibit, false)
        try? call(.inflowDisable, false)
    }

    private func call(_ method: Method, _ value: Bool) throws {
        var input: UInt64 = value ? 1 : 0
        var result = IOConnectCallScalarMethod(connection, method.rawValue, &input, 1, nil, nil)
        if result == kIOReturnBadArgument {
            // Some releases declare one scalar output on these methods.
            var output: UInt64 = 0
            var count: UInt32 = 1
            result = IOConnectCallScalarMethod(connection, method.rawValue, &input, 1, &output, &count)
        }
        guard result == kIOReturnSuccess else {
            throw Failure.callFailed(String(describing: method), result)
        }
    }
}
