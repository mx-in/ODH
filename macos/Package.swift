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
        .library(name: "BaronWeb", targets: ["BaronWeb"]),
        .executable(name: "Baron", targets: ["Baron"]),
        .executable(name: "baron-probe", targets: ["baron-probe"]),
        .executable(name: "BaronPluginHost", targets: ["BaronPluginHost"]),
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
        // Plugin pages: the baron-plugin:// server, the page bridge and web views (WebKit).
        .target(
            name: "BaronWeb",
            dependencies: ["BaronCore", "BaronRuntime"],
            resources: [.copy("Resources/page-bridge.js")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // macOS glue: Accessibility, event monitors, pasteboard, windows.
        .target(
            name: "BaronPlatform",
            dependencies: ["BaronCore", "SelectedTextKit", "KeyboardShortcuts"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Baron",
            dependencies: ["BaronCore", "BaronPlatform", "BaronRuntime", "BaronWeb", "KeyboardShortcuts"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The sandboxed XPC helper plugins run in (scripts/build-app.sh makes BaronPluginHost.xpc of it).
        .executableTarget(name: "BaronPluginHost", dependencies: ["BaronRuntime"]),
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
            dependencies: ["BaronCore", "BaronPlatform", "BaronRuntime", "BaronAutomation"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "BaronCoreTests", dependencies: ["BaronCore"]),
        .testTarget(name: "BaronRuntimeTests", dependencies: ["BaronRuntime", "BaronCore"]),
        .testTarget(name: "BaronWebTests", dependencies: ["BaronWeb", "BaronRuntime", "BaronCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
