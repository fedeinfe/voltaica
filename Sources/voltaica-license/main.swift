import CryptoKit
import Foundation
import VoltaicaCore

// Seller-side tool: mints and checks license keys. Never shipped inside the app, and it needs the
// private signing key that lives outside the repository.

let signingKeyPath = ("~/.voltaica/license-signing-key.b64" as NSString).expandingTildeInPath

func loadSigningKey() -> Curve25519.Signing.PrivateKey? {
    guard let text = try? String(contentsOfFile: signingKeyPath, encoding: .utf8),
          let raw = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else { return nil }
    return key
}

func value(_ flag: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

let arguments = Array(CommandLine.arguments.dropFirst())

switch arguments.first {
case "mint":
    guard let email = value("--email", in: arguments) else {
        FileHandle.standardError.write(Data("usage: voltaica-license mint --email <buyer> [--order <id>] [--seats 3]\n".utf8))
        exit(64)
    }
    guard let key = loadSigningKey() else {
        FileHandle.standardError.write(Data("no signing key at \(signingKeyPath)\n".utf8))
        exit(66)
    }
    let order = value("--order", in: arguments) ?? "manual-\(Int(Date().timeIntervalSince1970))"
    let seats = Int(value("--seats", in: arguments) ?? "3") ?? 3
    let info = LicenseInfo(email: email, order: order, issued: Date(), seats: seats)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .secondsSince1970
    encoder.outputFormatting = .sortedKeys
    let payload = try encoder.encode(info)
    let signature = try key.signature(for: payload)
    let licenseKey = "\(License.encodeBase64URL(payload)).\(License.encodeBase64URL(signature))"

    guard License.verify(licenseKey) != nil else {
        FileHandle.standardError.write(Data("minted key failed verification: public key mismatch\n".utf8))
        exit(70)
    }
    print(licenseKey)

case "check":
    guard let candidate = arguments.dropFirst().first else { exit(64) }
    if let info = License.verify(candidate) {
        print("valid  \(info.email)  order \(info.order)  seats \(info.seats)  issued \(info.issued)")
    } else {
        print("invalid")
        exit(1)
    }

case "public-key":
    print(License.publicKeyBase64)

default:
    print("""
    voltaica-license — seller side key tool

      mint --email <buyer> [--order <id>] [--seats 3]   sign a new license key
      check <key>                                        verify a key offline
      public-key                                         print the embedded public key

    Signing key: \(signingKeyPath)
    """)
}
