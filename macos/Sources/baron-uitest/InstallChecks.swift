import AppKit
import BaronAutomation
import BaronCore
import BaronPlatform
import BaronRuntime
import Foundation

// `baron-uitest --install` (scripts/uitest-install.sh packs the plugins first): installs from Baron's bundle, a file
// and an update needing consent, refuses a junk archive, disables, uninstalls, and checks the bar settings.

/// Baron's settings as Baron reads them; written with `defaults` so Baron's next launch sees them.
func readBaronSettings() -> BaronSettings {
    CFPreferencesAppSynchronize(Baron.bundleIdentifier as CFString)
    let data = CFPreferencesCopyAppValue("settings" as CFString, Baron.bundleIdentifier as CFString) as? Data
    return data.flatMap { try? JSONDecoder().decode(BaronSettings.self, from: $0) } ?? BaronSettings()
}

func writeBaronSettings(_ settings: BaronSettings) {
    guard let data = try? JSONEncoder().encode(settings) else { return }
    _ = try? Shell.run("/usr/bin/defaults", ["write", Baron.bundleIdentifier, "settings", "-data", data.map { String(format: "%02x", $0) }.joined()])
}

/// Polls until `condition` holds or `timeout` passes.
func waitUntil(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        SyntheticInput.pause(0.25)
    }
    return condition()
}

/// Quits Baron and waits until it has exited.
func quitBaron() {
    for running in NSRunningApplication.runningApplications(withBundleIdentifier: Baron.bundleIdentifier) { running.terminate() }
    let deadline = Date().addingTimeInterval(8)
    while Date() < deadline, !NSRunningApplication.runningApplications(withBundleIdentifier: Baron.bundleIdentifier).isEmpty {
        SyntheticInput.pause(0.2)
    }
    SyntheticInput.pause(0.5)
}

/// Restarts Baron with changed settings.
func relaunchBaron(_ change: (inout BaronSettings) -> Void) {
    quitBaron()
    var settings = readBaronSettings()
    change(&settings)
    writeBaronSettings(settings)
    try? Shell.open(["build/Baron.app"])
    SyntheticInput.pause(3)
}

@MainActor
func runInstallChecks(packages: URL) async -> [PluginCheck] {
    var checks: [PluginCheck] = []
    func record(_ name: String, _ passed: Bool, _ detail: String) {
        checks.append(PluginCheck(name: name, passed: passed, detail: detail))
        log("  \(passed ? "✓" : "✗") \(name): \(detail)")
    }
    let plugins = PluginInstaller.standardRoot
    let location = PluginDataLocation.standard
    let settings = readBaronSettings
    let appPath = URL(fileURLWithPath: "build/Baron.app").path // `open -a` needs it absolute
    func press(_ identifier: String, in window: AXElement?) -> Bool {
        guard let window, let element = findElement(in: window, identifier: identifier) else { return false }
        AXUIElementPerformAction(element.raw, kAXPressAction as CFString)
        SyntheticInput.pause(0.8)
        return true
    }

    // A clean slate: no installed plugins, nothing offered yet, the default bar.
    quitBaron()
    for id in ["org.baron.example.lookup", "org.baron.example.uppercase"] {
        try? FileManager.default.removeItem(at: plugins.appendingPathComponent(id))
        try? FileManager.default.removeItem(at: location.dataRoot.appendingPathComponent(id))
        try? SecretStore().removeAll(pluginID: id)
    }
    var reset = settings()
    reset.offeredBundledPlugins = []
    reset.bar = BarArrangement()
    reset.disabledPlugins = []
    writeBaronSettings(reset)
    var registry = (try? JSONSerialization.jsonObject(with: Data(contentsOf: plugins.appendingPathComponent("installed.json")))) as? [String: Any] ?? [:]
    registry["org.baron.example.lookup"] = nil
    registry["org.baron.example.uppercase"] = nil
    try? JSONSerialization.data(withJSONObject: registry).write(to: plugins.appendingPathComponent("installed.json"))

    // 1. First launch offers the bundled plugin with the install sheet.
    try? Shell.open(["build/Baron.app"])
    let offered = waitForWindow(titled: "Install Plugin", timeout: 8)
    let offeredText = offered.map { staticTexts(in: $0).first ?? "" } ?? ""
    record("a bundled plugin is offered at first launch", offered != nil, offeredText.isEmpty ? "no sheet" : offeredText)
    _ = press("installSheet.install", in: offered)
    record("installing it copies the package", waitUntil(8) { FileManager.default.fileExists(atPath: plugins.appendingPathComponent("org.baron.example.lookup/1.0.0/manifest.json").path) },
           "Plugins/org.baron.example.lookup/1.0.0")

    // 2. Opening a .baronplugin file.
    try? Shell.open(["-a", appPath, packages.appendingPathComponent("uppercase-1.0.0.baronplugin").path])
    let sheet = waitForWindow(titled: "Install Plugin", timeout: 8)
    _ = press("installSheet.install", in: sheet)
    record("a .baronplugin file installs", waitUntil(8) { FileManager.default.fileExists(atPath: plugins.appendingPathComponent("org.baron.example.uppercase/1.0.0/manifest.json").path) },
           sheet == nil ? "no sheet" : "Plugins/org.baron.example.uppercase/1.0.0")

    // 3. A junk archive is refused with the reason.
    try? Shell.open(["-a", appPath, packages.appendingPathComponent("junk.baronplugin").path])
    SyntheticInput.pause(2)
    let alertText = NSRunningApplication.runningApplications(withBundleIdentifier: Baron.bundleIdentifier).first
        .map { staticTexts(in: AXElement.application(pid: $0.processIdentifier)) } ?? []
    let refused = alertText.contains { $0.contains("can't be installed") } && alertText.contains { $0.contains("isn't a valid") }
    record("a junk archive is refused with the reason", refused, alertText.filter { $0.contains("install") || $0.contains("valid") }.joined(separator: " | "))
    SyntheticInput.press(keyCode: 36) // OK
    SyntheticInput.pause(0.8)

    // 4. An update adding a permission waits for consent while the old version stays.
    try? Shell.open(["-a", appPath, packages.appendingPathComponent("uppercase-1.1.0.baronplugin").path])
    func uppercaseRecord() -> InstalledRecord? {
        (try? JSONDecoder().decode([String: InstalledRecord].self, from: Data(contentsOf: plugins.appendingPathComponent("installed.json"))))?["org.baron.example.uppercase"]
    }
    let pendingWindow = waitForWindow(titled: "Settings", timeout: 8)
    _ = waitUntil(5) { uppercaseRecord()?.pending != nil }
    let installedRecord = uppercaseRecord()
    record("an update adding a permission waits for consent", installedRecord?.version == "1.0.0" && installedRecord?.pending?.newPermissions == ["clipboard.read"],
           "installed \(installedRecord?.version ?? "?"), pending \(installedRecord?.pending?.version ?? "none")")
    if press("page.reviewUpdate", in: pendingWindow), let review = waitForWindow(titled: "Install Plugin", timeout: 4) {
        let mentions = staticTexts(in: review).contains { $0.contains("Read your clipboard") }
        _ = press("installSheet.install", in: review)
        _ = waitUntil(8) { uppercaseRecord()?.version == "1.1.0" }
        let after = uppercaseRecord()
        record("accepting installs the update", mentions && after?.version == "1.1.0" && after?.pending == nil, "now \(after?.version ?? "?"); sheet listed the new permission: \(mentions)")
    } else {
        record("accepting installs the update", false, "no Review Update button")
    }

    // 5. Disable and enable.
    let window = waitForWindow(titled: "Settings", timeout: 3)
    _ = press("page.enabled", in: window)
    SyntheticInput.pause(0.8)
    let disabled = settings().disabledPlugins.contains("org.baron.example.uppercase")
    _ = press("page.enabled", in: window)
    SyntheticInput.pause(0.8)
    record("disable and enable", disabled && !settings().disabledPlugins.contains("org.baron.example.uppercase"), "disabled: \(disabled)")

    // 6. Uninstall leaves nothing behind.
    // A secret Baron may delete, as one it saved itself would be.
    _ = try? Shell.run("/usr/bin/security", ["add-generic-password", "-U", "-s", "org.odh.baron.plugin.org.baron.example.uppercase", "-a", "token", "-w", "t", "-T", appPath])
    _ = try? PluginDataLocation.standard.dataFolder(for: "org.baron.example.uppercase")
    if let window {
        scrollToEnd(window)
        if press("page.uninstall", in: window) {
            let confirm = NSRunningApplication.runningApplications(withBundleIdentifier: Baron.bundleIdentifier).first
                .flatMap { findElement(in: AXElement.application(pid: $0.processIdentifier), identifier: "page.uninstall.confirm") }
            if let confirm { AXUIElementPerformAction(confirm.raw, kAXPressAction as CFString) } else { SyntheticInput.press(keyCode: 36) }
            _ = waitUntil(8) { uppercaseRecord() == nil }
        }
    }
    let leftovers = [plugins.appendingPathComponent("org.baron.example.uppercase"), location.dataRoot.appendingPathComponent("org.baron.example.uppercase"),
                     location.cacheRoot.appendingPathComponent("org.baron.example.uppercase")].filter { FileManager.default.fileExists(atPath: $0.path) }
    let keychain = SecretStore().keys(pluginID: "org.baron.example.uppercase")
    record("uninstall leaves nothing on disk or in the Keychain", leftovers.isEmpty && keychain.isEmpty,
           leftovers.isEmpty && keychain.isEmpty ? "nothing left" : "left: \(leftovers.map(\.lastPathComponent)) keychain: \(keychain)")
    window?.element(kAXCloseButtonAttribute).map { AXUIElementPerformAction($0.raw, kAXPressAction as CFString) }

    // 7. Bar settings: hide, reorder, a hotkey, Run on selection.
    await checkBarSettings(record: record)

    relaunchBaron { $0.bar = BarArrangement() }
    return checks
}

@MainActor
func checkBarSettings(record: (String, Bool, String) -> Void) async {
    // Hide Search and move Copy to the end.
    relaunchBaron {
        $0.bar.hidden = ["builtin.search"]
        $0.bar.move("builtin.copy", by: 10, among: ["builtin.copy", "builtin.search", "builtin.openLink", "plugin:org.baron.example.lookup/define"])
    }

    let page = FileManager.default.temporaryDirectory.appendingPathComponent("baron-bar.html")
    try? "<!doctype html><meta charset=\"utf-8\"><title>baron-bar</title><p>The quick brown fox jumps.</p>".write(to: page, atomically: true, encoding: .utf8)
    try? Shell.open(["-a", "Safari", page.path])
    guard let safari = waitForApp("com.apple.Safari"),
          let tab = FixtureWindows.waitForWindow(titled: "baron-bar", inApp: safari.processIdentifier, timeout: 20) else {
        record("the bar follows its settings", false, "no Safari page")
        return
    }
    FixtureWindows.raise(tab)
    safari.activate()
    SyntheticInput.pause(1.2)
    defer { closeTab(safari, titled: "baron-bar") }
    guard let word = WordLocator.locate("quick", inApp: safari.processIdentifier) else { return }

    SyntheticInput.doubleClick(at: word.point)
    _ = BaronBarDetector.waitForBar(timeout: 2.5)
    let order = barActionOrder()
    record("the bar hides and orders actions as set", !order.contains("builtin.search") && order.last == "builtin.copy",
           "bar: \(order.joined(separator: ", "))")
    SyntheticInput.press(keyCode: 53)
    SyntheticInput.pause(0.5)

    // Run on selection: Define runs at once, without the bar.
    relaunchBaron { $0.bar.runOnSelection["plugin:org.baron.example.lookup/define"] = [] }
    safari.activate()
    SyntheticInput.pause(0.8)
    SyntheticInput.doubleClick(at: word.point)
    // The bar itself, not any floating Baron window: the toast is one too.
    let barShown = waitUntil(1.5) { !barActionOrder().isEmpty }
    let toast = waitForToast(timeout: 8)
    record("Run on selection runs the action without the bar", !barShown && (toast?.lowercased().hasPrefix("quick") == true || toast?.contains("can't be reached") == true),
           "bar shown: \(barShown), toast: \(toast ?? "none")")
    SyntheticInput.pause(3)

    // A hotkey for Copy, recorded in the Bar tab, copies the selection.
    let recorded = setCopyHotkey(true)
    relaunchBaron { $0.bar.runOnSelection = [:] }
    defer { _ = setCopyHotkey(false) }
    safari.activate()
    SyntheticInput.pause(0.8)
    SyntheticInput.doubleClick(at: word.point)
    SyntheticInput.pause(0.6)
    SyntheticInput.press(keyCode: 53)
    NSPasteboard.general.clearContents()
    SyntheticInput.press(keyCode: 40, flags: [.maskControl, .maskAlternate, .maskCommand]) // ⌃⌥⌘K
    SyntheticInput.pause(1.5)
    let copied = NSPasteboard.general.string(forType: .string)
    record("an action's hotkey runs it on the selection", recorded && copied == "quick", "recorded: \(recorded), clipboard: \(copied ?? "empty")")
}

/// The ids of the buttons on the bar, left to right.
@MainActor
func barActionOrder() -> [String] {
    guard let baron = NSRunningApplication.runningApplications(withBundleIdentifier: Baron.bundleIdentifier).first,
          let bar = findElement(in: AXElement.application(pid: baron.processIdentifier), identifier: "baron.actionBar") else { return [] }
    var buttons: [(CGFloat, String)] = []
    func visit(_ element: AXElement, _ depth: Int) {
        if let id = element.string("AXIdentifier"), id.hasPrefix("baron.action."), let frame = element.frame {
            buttons.append((frame.minX, String(id.dropFirst("baron.action.".count))))
        }
        if depth < 8 { element.children.forEach { visit($0, depth + 1) } }
    }
    visit(bar, 0)
    return buttons.sorted { $0.0 < $1.0 }.map(\.1)
}

/// Gives Copy the hotkey ⌃⌥⌘K, stored the way the Bar tab's recorder stores it.
func setCopyHotkey(_ on: Bool) -> Bool {
    let key = "KeyboardShortcuts_action.builtin.copy"
    let arguments = on
        ? ["write", Baron.bundleIdentifier, key, "-string", #"{"carbonKeyCode":40,"carbonModifiers":6400}"#] // ⌘ 256 + ⌥ 2048 + ⌃ 4096
        : ["delete", Baron.bundleIdentifier, key]
    return (try? Shell.run("/usr/bin/defaults", arguments)) == 0
}

@MainActor
func findElement(in root: AXElement, title: String, depth: Int = 0) -> AXElement? {
    if root.title == title { return root }
    guard depth < 12 else { return nil }
    for child in root.children { if let found = findElement(in: child, title: title, depth: depth + 1) { return found } }
    return nil
}

@MainActor
func firstElement(in root: AXElement, role: String, titled title: String? = nil, depth: Int = 0) -> AXElement? {
    if root.role == role, title == nil || root.title == title { return root }
    guard depth < 10 else { return nil }
    for child in root.children { if let found = firstElement(in: child, role: role, titled: title, depth: depth + 1) { return found } }
    return nil
}
