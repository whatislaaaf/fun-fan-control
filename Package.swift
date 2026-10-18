// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FunFanControl",
    platforms: [.macOS(.v14)],
    targets: [
        // Thin C layer that talks to the AppleSMC IOKit service.
        .target(
            name: "CSMC",
            path: "Sources/CSMC",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        // Shared Swift library: SMC wrapper, sensors, fans, curves, helper client.
        .target(name: "FanKit", dependencies: ["CSMC"]),
        // The menu bar app.
        .executableTarget(name: "FunFanControl", dependencies: ["FanKit"]),
        // Small setuid-root helper that performs the actual fan writes.
        .executableTarget(name: "ffc-helper", dependencies: ["FanKit"]),
        // Developer tool: dumps every fan and temperature key the SMC exposes.
        .executableTarget(name: "ffc-probe", dependencies: ["FanKit"]),
    ],
    swiftLanguageVersions: [.v5]
)
