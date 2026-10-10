// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Baron",
    platforms: [.macOS(.v14)],
    products: [
        // Libraries for the Xcode app target in Xcode/Baron.xcodeproj.
        .library(name: "BaronCore", targets: ["BaronCore"]),
        .library(name: "BaronPlatform", targets: ["BaronPlatform"]),
        .library(name: "BaronRuntime", targets: ["BaronRuntime"]),
        .executable(name: "Baron", targets: ["Baron"]),
        .executable(name: "baron-probe", targets: ["baron-probe"]),
        .executable(name: "baron-uitest", targets: ["baron-uitest"]),
    ],
    dependencies: [
        .package(url: "https://github.com/tisfeng/SelectedTextKit.git", from: "2.6.7"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "3.1.0"),
    ],
    targets: [
        // Pure logic: no AppKit, no Accessibility. Everything here is unit tested.
        .target(name: "BaronCore"),
        // Runs plugin code: JavaScriptCore contexts, the prelude, the host router and its services.
        .target(
            name: "BaronRuntime",
            dependencies: ["BaronCore"],
            resources: [.copy("Resources/prelude.js")]
        ),
        // macOS glue: Accessibility, event monitors, pasteboard, windows.
        .target(
            name: "BaronPlatform",
            dependencies: ["BaronCore", "SelectedTextKit", "KeyboardShortcuts"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Baron",
            dependencies: ["BaronCore", "BaronPlatform", "KeyboardShortcuts"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "baron-probe",
            dependencies: ["BaronCore", "BaronPlatform"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Test-only: drives other apps with synthetic input. Never linked into Baron.app.
        .target(
            name: "BaronAutomation",
            dependencies: ["BaronCore", "BaronPlatform"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "baron-uitest",
            dependencies: ["BaronCore", "BaronPlatform", "BaronAutomation"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "BaronCoreTests", dependencies: ["BaronCore"]),
        .testTarget(name: "BaronRuntimeTests", dependencies: ["BaronRuntime", "BaronCore"]),
    ]
)
