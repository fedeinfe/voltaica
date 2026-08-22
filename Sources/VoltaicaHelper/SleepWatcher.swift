import Foundation
import IOKit
import IOKit.pwr_mgt
import os

/// IOKit's power messages are built by a C macro Swift cannot import, so the four values we
/// care about are spelled out: `err_system(0x38) | sub_iokit_common | code`.
private enum PowerMessage {
    static let canSystemSleep: UInt32 = 0xE000_0270
    static let systemWillSleep: UInt32 = 0xE000_0280
    static let systemWillPowerOn: UInt32 = 0xE000_0320
    static let systemHasPoweredOn: UInt32 = 0xE000_0300
}

/// Watches for sleep and wake so the charger state is re-asserted the moment the Mac comes
/// back, and never left cut while it sleeps.
final class SleepWatcher {
    static let shared = SleepWatcher()

    private let log = Logger(subsystem: "com.federicoinfelici.Voltaica.Helper", category: "power")
    private var rootPort: io_connect_t = 0
    private var notifier: IONotificationPortRef?
    private var notifierObject: io_object_t = 0

    private init() {}

    func start() {
        var object: io_object_t = 0
        let port = IORegisterForSystemPower(nil, &notifier, { _, _, messageType, argument in
            SleepWatcher.shared.handle(messageType: messageType, argument: argument)
        }, &object)

        guard port != 0, let notifier else {
            log.error("could not register for system power notifications")
            return
        }
        rootPort = port
        notifierObject = object
        CFRunLoopAddSource(CFRunLoopGetMain(),
                           IONotificationPortGetRunLoopSource(notifier).takeUnretainedValue(),
                           .defaultMode)
    }

    private func handle(messageType: UInt32, argument: UnsafeMutableRawPointer?) {
        switch messageType {
        case PowerMessage.canSystemSleep:
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case PowerMessage.systemWillSleep:
            PolicyRunner.shared.prepareForSleep()
            IOAllowPowerChange(rootPort, Int(bitPattern: argument))
        case PowerMessage.systemWillPowerOn, PowerMessage.systemHasPoweredOn:
            log.notice("woke, re-asserting charger state")
            PolicyRunner.shared.didWake()
        default:
            break
        }
    }
}
