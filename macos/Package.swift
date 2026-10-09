// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Baron",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Baron", targets: ["Baron"]),
        .executable(name: "baron-probe", targets: ["baron-probe"]),
    ],
    targets: [
        // Pure logic: no AppKit, no Accessibility. Everything here is unit tested.
        .target(name: "BaronCore"),
        // macOS glue: Accessibility, event monitors, pasteboard, windows.
        .target(
            name: "BaronPlatform",
            dependencies: ["BaronCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Baron",
            dependencies: ["BaronCore", "BaronPlatform"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "baron-probe",
            dependencies: ["BaronCore", "BaronPlatform"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "BaronCoreTests", dependencies: ["BaronCore"]),
    ]
)
