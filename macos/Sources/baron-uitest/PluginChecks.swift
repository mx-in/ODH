import AppKit
import BaronAutomation
import BaronCore
import BaronPlatform
import Foundation

// `baron-uitest --plugins`: with the example plugins in Baron's development folder (scripts/uitest-plugins.sh puts
// them there), select words in an editable text area in Safari and run both examples from the bar.

struct PluginCheck: Codable {
    var name: String
    var passed: Bool
    var detail: String
}

@MainActor
func runPluginChecks() async -> [PluginCheck] {
    var checks: [PluginCheck] = []
    func record(_ name: String, _ passed: Bool, _ detail: String) {
        checks.append(PluginCheck(name: name, passed: passed, detail: detail))
        log("  \(passed ? "✓" : "✗") \(name): \(detail)")
    }

    // Plugins load when Baron starts, so start a fresh Baron.
    for running in NSRunningApplication.runningApplications(withBundleIdentifier: Baron.bundleIdentifier) { running.terminate() }
    SyntheticInput.pause(1.5)
    guard FileManager.default.fileExists(atPath: "build/Baron.app") else {
        record("Baron starts", false, "build/Baron.app is missing; run scripts/build-app.sh")
        return checks
    }
    try? Shell.open(["build/Baron.app"])
    SyntheticInput.pause(3)

    let page = FileManager.default.temporaryDirectory.appendingPathComponent("baron-plugins.html")
    try? """
    <!doctype html><meta charset="utf-8"><title>baron-plugins</title>
    <textarea id="text" rows="4" cols="60" autofocus>The quick brown fox jumps over the lazy dog.</textarea>
    """.write(to: page, atomically: true, encoding: .utf8)
    try? Shell.open(["-a", "Safari", page.path])
    guard let safari = waitForApp("com.apple.Safari"),
          let window = FixtureWindows.waitForWindow(titled: "baron-plugins", inApp: safari.processIdentifier, timeout: 20) else {
        record("Safari opens the page", false, "no window")
        return checks
    }
    FixtureWindows.raise(window)
    safari.activate()
    SyntheticInput.pause(1.5)
    defer { closeDocument(safari) }

    // Uppercase: double-click a word, press the plugin's button, read the document back.
    guard let quick = WordLocator.locate("quick", inApp: safari.processIdentifier) else {
        record("find a word", false, "\"quick\" isn't in the Accessibility tree")
        return checks
    }
    SyntheticInput.doubleClick(at: quick.point)
    let uppercaseID = "plugin:org.baron.example.uppercase/uppercase"
    let defineID = "plugin:org.baron.example.lookup/define"
    let shown = BaronBarDetector.waitForBar(timeout: 2.5)
    record("the bar shows plugin actions", shown && BaronBarDetector.hasAction(uppercaseID) && BaronBarDetector.hasAction(defineID),
           shown ? "UPPERCASE \(BaronBarDetector.hasAction(uppercaseID) ? "shown" : "missing"), Define \(BaronBarDetector.hasAction(defineID) ? "shown" : "missing")" : "no bar")
    if BaronBarDetector.pressAction(uppercaseID) {
        SyntheticInput.pause(1)
        let text = documentText(safari) ?? ""
        record("UPPERCASE replaces the selection", text.hasPrefix("The QUICK brown fox"), "document reads \"\(text.trimmingCharacters(in: .whitespacesAndNewlines))\"")
    } else {
        record("UPPERCASE replaces the selection", false, "couldn't press the button")
    }

    // Define: double-click another word and wait for the plugin's toast (a real request to Youdao's dictionary).
    SyntheticInput.press(keyCode: 53)
    SyntheticInput.pause(0.5)
    guard let fox = WordLocator.locate("fox", inApp: safari.processIdentifier) else {
        record("find a word", false, "\"fox\" isn't in the Accessibility tree")
        return checks
    }
    SyntheticInput.doubleClick(at: fox.point)
    if BaronBarDetector.waitForBar(timeout: 2.5), BaronBarDetector.pressAction(defineID) {
        let toast = waitForToast(timeout: 8)
        record("Define shows a definition", toast?.lowercased().hasPrefix("fox:") == true, toast.map { "toast: \($0)" } ?? "no toast within 8 s")
    } else {
        record("Define shows a definition", false, "no bar or no Define button")
    }
    return checks
}

extension BaronBarDetector {
    /// Whether the bar showing now has a button for the action.
    @MainActor
    static func hasAction(_ id: String) -> Bool {
        guard let baron = NSRunningApplication.runningApplications(withBundleIdentifier: Baron.bundleIdentifier).first else { return false }
        return findElement(in: AXElement.application(pid: baron.processIdentifier), identifier: "baron.action.\(id)") != nil
    }
}

@MainActor
func findElement(in root: AXElement, identifier: String, depth: Int = 0) -> AXElement? {
    if root.string("AXIdentifier") == identifier { return root }
    guard depth < 12 else { return nil }
    let windows = depth == 0 ? ((root.value(kAXWindowsAttribute) as? [AXUIElement]) ?? []).map(AXElement.init) : []
    for child in windows + root.children {
        if let found = findElement(in: child, identifier: identifier, depth: depth + 1) { return found }
    }
    return nil
}

@MainActor
func waitForToast(timeout: TimeInterval) -> String? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let baron = NSRunningApplication.runningApplications(withBundleIdentifier: Baron.bundleIdentifier).first,
           let message = findElement(in: AXElement.application(pid: baron.processIdentifier), identifier: "baron.toast.message"),
           let text = message.string(kAXValueAttribute), !text.isEmpty {
            return text
        }
        SyntheticInput.pause(0.2)
    }
    return nil
}

@MainActor
func documentText(_ app: NSRunningApplication) -> String? {
    let focused = AXElement.application(pid: app.processIdentifier).element(kAXFocusedUIElementAttribute)
    return focused?.string(kAXValueAttribute)
}

/// Closes the test's tab when it is in front.
@MainActor
func closeDocument(_ app: NSRunningApplication) {
    app.activate()
    SyntheticInput.press(keyCode: 53)
    SyntheticInput.pause(0.4)
    let front = AXElement.application(pid: app.processIdentifier).element(kAXFocusedWindowAttribute)
    if front?.title?.contains("baron-plugins") == true {
        SyntheticInput.press(keyCode: 13, flags: .maskCommand) // ⌘W
    }
    SyntheticInput.pause(0.5)
}
