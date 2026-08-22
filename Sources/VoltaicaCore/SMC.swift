import Foundation
import IOKit

/// Errors surfaced by the SMC layer.
public enum SMCError: Error, CustomStringConvertible, Sendable {
    case driverNotFound
    case openFailed(kern_return_t)
    case notConnected
    case keyNotFound(String)
    case callFailed(kern_return_t)
    case deviceError(UInt8)
    case unexpectedSize(String, Int, Int)

    public var description: String {
        switch self {
        case .driverNotFound: return "AppleSMC service not present"
        case .openFailed(let kr): return "IOServiceOpen failed (0x\(String(kr, radix: 16))) — root required"
        case .notConnected: return "SMC connection is closed"
        case .keyNotFound(let k): return "SMC key \(k) not available on this Mac"
        case .callFailed(let kr): return "SMC call failed (0x\(String(kr, radix: 16)))"
        case .deviceError(let r): return "SMC returned status \(r)"
        case .unexpectedSize(let k, let want, let got):
            return "SMC key \(k) is \(got) bytes, expected \(want)"
        }
    }
}

/// A four character SMC key such as `CH0B`.
public struct SMCKey: Hashable, Sendable, CustomStringConvertible, ExpressibleByStringLiteral {
    public let name: String
    public let code: UInt32

    public init(stringLiteral value: StringLiteralType) { self.init(value) }

    public init(_ name: String) {
        precondition(name.utf8.count == 4, "SMC keys are exactly four characters")
        self.name = name
        var code: UInt32 = 0
        for byte in name.utf8 { code = (code << 8) | UInt32(byte) }
        self.code = code
    }

    public var description: String { name }
}

/// Metadata the SMC reports for a key.
public struct SMCKeyInfo: Sendable {
    public let size: Int
    public let type: String
}

/// Direct, root-only access to the System Management Controller.
///
/// Reads are harmless; writes to the charger keys are what actually gates charging, and the
/// kernel only accepts them from a process running as root. Instances are *not* thread safe:
/// the daemon confines one connection to its own serial queue.
public final class SMCConnection {
    private var connection: io_connect_t = 0

    private enum Selector: UInt8 {
        case read = 5
        case write = 6
        case keyFromIndex = 8
        case keyInfo = 9
    }

    private static let handleYPCEvent: UInt32 = 2
    private static let keyNotFoundStatus: UInt8 = 132

    public init() throws {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { throw SMCError.driverNotFound }
        defer { IOObjectRelease(service) }

        var conn: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &conn)
        guard result == kIOReturnSuccess else { throw SMCError.openFailed(result) }
        connection = conn
    }

    deinit { close() }

    public func close() {
        guard connection != 0 else { return }
        IOServiceClose(connection)
        connection = 0
    }

    // MARK: - Primitives

    public func info(for key: SMCKey) throws -> SMCKeyInfo {
        var input = SMCParamStruct()
        input.key = key.code
        input.data8 = Selector.keyInfo.rawValue
        let output = try call(input, key: key)
        return SMCKeyInfo(size: Int(output.keyInfo.dataSize),
                          type: Self.fourCharString(output.keyInfo.dataType))
    }

    public func readBytes(_ key: SMCKey) throws -> [UInt8] {
        let meta = try info(for: key)
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = UInt32(meta.size)
        input.data8 = Selector.read.rawValue
        let output = try call(input, key: key)
        return Self.tupleToArray(output.bytes, count: meta.size)
    }

    public func writeBytes(_ key: SMCKey, _ value: [UInt8]) throws {
        let meta = try info(for: key)
        guard meta.size == value.count else {
            throw SMCError.unexpectedSize(key.name, meta.size, value.count)
        }
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = UInt32(meta.size)
        input.data8 = Selector.write.rawValue
        Self.fillTuple(&input.bytes, with: value)
        _ = try call(input, key: key)
    }

    // MARK: - Typed helpers

    public func readUInt8(_ key: SMCKey) throws -> UInt8 {
        let bytes = try readBytes(key)
        guard let first = bytes.first else { throw SMCError.unexpectedSize(key.name, 1, 0) }
        return first
    }

    public func writeUInt8(_ key: SMCKey, _ value: UInt8) throws {
        try writeBytes(key, [value])
    }

    public func readUInt16(_ key: SMCKey) throws -> UInt16 {
        let bytes = try readBytes(key)
        guard bytes.count >= 2 else { throw SMCError.unexpectedSize(key.name, 2, bytes.count) }
        return UInt16(bytes[0]) << 8 | UInt16(bytes[1])
    }

    public func readInt16(_ key: SMCKey) throws -> Int16 {
        Int16(bitPattern: try readUInt16(key))
    }

    /// Reads a key as a Double, decoding whichever numeric encoding the SMC reports for it.
    public func readNumber(_ key: SMCKey) throws -> Double {
        let meta = try info(for: key)
        let bytes = try readBytes(key)
        return Self.decodeNumber(bytes: bytes, type: meta.type) ?? 0
    }

    public func exists(_ key: SMCKey) -> Bool {
        (try? info(for: key)) != nil
    }

    /// Walks the whole key space. Used by the diagnostics screen and to work out which charger
    /// keys a given Mac actually exposes, which varies by generation.
    public func allKeys() throws -> [SMCKey] {
        let count = Int(try readNumber("#KEY"))
        var keys: [SMCKey] = []
        keys.reserveCapacity(count)
        for index in 0..<count {
            var input = SMCParamStruct()
            input.data8 = Selector.keyFromIndex.rawValue
            input.data32 = UInt32(index)
            guard let output = try? call(input, key: "#KEY"), output.key != 0 else { continue }
            keys.append(SMCKey(Self.fourCharString(output.key)))
        }
        return keys
    }

    // MARK: - Decoding

    /// Multi-byte integer keys are not consistently ordered: on this Apple Silicon Mac B0AV
    /// only makes sense little-endian (12644 mV vs IORegistry 12645) while B0RM only makes
    /// sense big-endian (4694 mAh vs AppleRawCurrentCapacity 4694). Rather than guess per key,
    /// callers ask for one order and diagnostics show both. Nothing in the UI depends on this:
    /// telemetry comes from AppleSmartBattery, and the charger keys are all single bytes.
    public enum ByteOrder: Sendable { case big, little }

    private static func integer(_ bytes: ArraySlice<UInt8>, _ order: ByteOrder) -> UInt64 {
        let ordered = order == .big ? Array(bytes) : Array(bytes.reversed())
        return ordered.reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
    }

    public static func decodeNumber(bytes: [UInt8], type: String, order: ByteOrder = .big) -> Double? {
        switch type {
        case "ui8 ", "flag", "hex_":
            return bytes.first.map(Double.init)
        case "ui16":
            guard bytes.count >= 2 else { return nil }
            return Double(UInt16(truncatingIfNeeded: integer(bytes.prefix(2), order)))
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(truncatingIfNeeded: integer(bytes.prefix(4), order)))
        case "si8 ":
            return bytes.first.map { Double(Int8(bitPattern: $0)) }
        case "si16":
            guard bytes.count >= 2 else { return nil }
            return Double(Int16(bitPattern: UInt16(truncatingIfNeeded: integer(bytes.prefix(2), order))))
        case "sp78":
            guard bytes.count >= 2 else { return nil }
            // Fixed point is defined MSB-first in every published SMC table, on both architectures.
            let raw = Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))
            return Double(raw) / 256.0
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[3]) << 24 | UInt32(bytes[2]) << 16 | UInt32(bytes[1]) << 8 | UInt32(bytes[0])
            return Double(Float(bitPattern: raw))
        default:
            return nil
        }
    }

    // MARK: - Plumbing

    private func call(_ input: SMCParamStruct, key: SMCKey) throws -> SMCParamStruct {
        guard connection != 0 else { throw SMCError.notConnected }
        var input = input
        var output = SMCParamStruct()
        var outputSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(connection,
                                               Self.handleYPCEvent,
                                               &input,
                                               MemoryLayout<SMCParamStruct>.stride,
                                               &output,
                                               &outputSize)
        guard result == kIOReturnSuccess else { throw SMCError.callFailed(result) }
        if output.result == Self.keyNotFoundStatus { throw SMCError.keyNotFound(key.name) }
        guard output.result == 0 else { throw SMCError.deviceError(output.result) }
        return output
    }

    static func fourCharString(_ value: UInt32) -> String {
        let bytes = [UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
                     UInt8((value >> 8) & 0xff), UInt8(value & 0xff)]
        return String(decoding: bytes)
    }

    static func tupleToArray(_ tuple: SMCBytes, count: Int) -> [UInt8] {
        var copy = tuple
        return withUnsafeBytes(of: &copy) { raw in
            Array(raw.prefix(min(count, 32)).map { $0 })
        }
    }

    static func fillTuple(_ tuple: inout SMCBytes, with bytes: [UInt8]) {
        withUnsafeMutableBytes(of: &tuple) { raw in
            for (index, byte) in bytes.prefix(32).enumerated() { raw[index] = byte }
        }
    }
}

private extension String {
    init(decoding bytes: [UInt8]) {
        self = String(bytes.map { Character(UnicodeScalar($0)) })
    }
}

// MARK: - Kernel ABI

// Mirrors the 80 byte struct AppleSMC's user client expects. Field order and the explicit
// padding are load bearing: Swift packs nested structs by size, C by stride.
typealias SMCBytes = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)

struct SMCVersionStruct {
    var major: UInt8 = 0
    var minor: UInt8 = 0
    var build: UInt8 = 0
    var reserved: UInt8 = 0
    var release: UInt16 = 0
}

struct SMCPLimitStruct {
    var version: UInt16 = 0
    var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0
    var gpuPLimit: UInt32 = 0
    var memPLimit: UInt32 = 0
}

struct SMCKeyInfoStruct {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

struct SMCParamStruct {
    var key: UInt32 = 0
    var vers = SMCVersionStruct()
    var pLimitData = SMCPLimitStruct()
    var keyInfo = SMCKeyInfoStruct()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

    /// The kernel rejects anything but the exact ABI size, so the layout is asserted in tests.
    static var abiSize: Int { MemoryLayout<SMCParamStruct>.stride }
}
