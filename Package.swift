// swift-tools-version: 5.9
import PackageDescription

// Language mode stays at Swift 5: the daemon and the SMC layer are deliberately
// single-threaded around a serial queue, which Swift 6 strict concurrency cannot see.
let package = Package(
    name: "Voltaica",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Voltaica", targets: ["Voltaica"]),
        .executable(name: "VoltaicaHelper", targets: ["VoltaicaHelper"]),
        .executable(name: "voltaicactl", targets: ["voltaicactl"]),
        .executable(name: "voltaica-license", targets: ["voltaica-license"]),
        .library(name: "VoltaicaCore", targets: ["VoltaicaCore"]),
    ],
    targets: [
        .target(name: "VoltaicaCore"),
        .executableTarget(name: "Voltaica", dependencies: ["VoltaicaCore"]),
        .executableTarget(name: "VoltaicaHelper", dependencies: ["VoltaicaCore"]),
        .executableTarget(name: "voltaicactl", dependencies: ["VoltaicaCore"]),
        .executableTarget(name: "voltaica-license", dependencies: ["VoltaicaCore"]),
        .testTarget(name: "VoltaicaCoreTests", dependencies: ["VoltaicaCore"]),
    ]
)
