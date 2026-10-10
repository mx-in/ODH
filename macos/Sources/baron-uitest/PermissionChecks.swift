import AppKit
import BaronAutomation
import BaronCore
import BaronPlatform
import Foundation

// `baron-uitest --permissions` (scripts/uitest-permissions.sh installs the probe plugin first): runs the probe from
// the bar and answers Baron's permission prompt with Deny, Allow Once and Always Allow, checking what is remembered.
// Then opens the install sheet for ODH and reads it.

@MainActor
func runPermissionChecks() async -> [PluginCheck] {
    var checks: [PluginCheck] = []
    func record(_ name: String, _ passed: Bool, _ detail: String) {
        checks.append(PluginCheck(name: name, passed: passed, detail: detail))
        log("  \(passed ? "✓" : "✗") \(name): \(detail)")
    }
    let probeID = "plugin:org.baron.uitest.permission-probe/probe"
    let grants = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Baron/PluginData/org.baron.uitest.permission-probe/grants.json")
    try? FileManager.default.removeItem(at: grants)

    func restartBaron(_ arguments: [String] = []) {
        for running in NSRunningApplication.runningApplications(withBundleIdentifier: Baron.bundleIdentifier) { running.terminate() }
        SyntheticInput.pause(1.5)
        try? Shell.open(["build/Baron.app"] + (arguments.isEmpty ? [] : ["--args"] + arguments))
        SyntheticInput.pause(3)
    }

    /// Selects a word in the probe page and presses the probe's button; answers the prompt if one appears.
    func probe(answer: String?) -> (prompted: Bool, toast: String?) {
        let page = FileManager.default.temporaryDirectory.appendingPathComponent("baron-permissions.html")
        try? "<!doctype html><meta charset=\"utf-8\"><title>baron-permissions</title><p>The quick brown fox jumps.</p>".write(to: page, atomically: true, encoding: .utf8)
        try? Shell.open(["-a", "Safari", page.path])
        guard let safari = waitForApp("com.apple.Safari"),
              let window = FixtureWindows.waitForWindow(titled: "baron-permissions", inApp: safari.processIdentifier, timeout: 20) else { return (false, "no page") }
        FixtureWindows.raise(window)
        safari.activate()
        SyntheticInput.pause(1.2)
        defer { closeTab(safari, titled: "baron-permissions") }
        guard let word = WordLocator.locate("quick", inApp: safari.processIdentifier) else { return (false, "no word") }
        SyntheticInput.doubleClick(at: word.point)
        guard BaronBarDetector.waitForBar(timeout: 2.5), BaronBarDetector.pressAction(probeID) else { return (false, "no Probe button") }
        var prompted = false
        if let prompt = waitForElement("baron.permissionPrompt", timeout: answer == nil ? 1.5 : 4) {
            prompted = true
            if let answer, let button = findElement(in: prompt, identifier: "baron.prompt.\(answer)") {
                AXUIElementPerformAction(button.raw, kAXPressAction as CFString)
            }
        }
        let toast = waitForToast(timeout: 4)
        SyntheticInput.pause(3) // let the toast fade before the next run
        return (prompted, toast)
    }

    restartBaron()
    let deny = probe(answer: "deny")
    record("Deny", deny.prompted && deny.toast == "probe: denied", "prompted: \(deny.prompted), toast: \(deny.toast ?? "none")")
    let denyAgain = probe(answer: nil)
    record("a denial isn't asked again", !denyAgain.prompted && denyAgain.toast == "probe: denied", "prompted: \(denyAgain.prompted), toast: \(denyAgain.toast ?? "none")")

    try? FileManager.default.removeItem(at: grants)
    let once = probe(answer: "allowOnce")
    record("Allow Once", once.prompted && once.toast == "probe: granted", "prompted: \(once.prompted), toast: \(once.toast ?? "none")")
    let onceAgain = probe(answer: nil)
    record("Allow Once holds for a while", !onceAgain.prompted && onceAgain.toast == "probe: granted", "prompted: \(onceAgain.prompted), toast: \(onceAgain.toast ?? "none")")

    restartBaron() // Allow Once lives in memory, so a new Baron asks again.
    let always = probe(answer: "alwaysAllow")
    record("Always Allow", always.prompted && always.toast == "probe: granted", "prompted: \(always.prompted), toast: \(always.toast ?? "none")")
    restartBaron()
    let alwaysAgain = probe(answer: nil)
    record("Always Allow survives a restart", !alwaysAgain.prompted && alwaysAgain.toast == "probe: granted", "prompted: \(alwaysAgain.prompted), toast: \(alwaysAgain.toast ?? "none")")
    try? FileManager.default.removeItem(at: grants)

    // The install sheet, as task-008 will show it, for ODH.
    restartBaron(["--preview-install-sheet", URL(fileURLWithPath: "../plugins/odh").standardizedFileURL.path])
    let texts = waitForWindow(titled: "Install Plugin", timeout: 4).map { staticTexts(in: $0) } ?? []
    // The name follows the system language, so only its frame is checked.
    let expected = ["Install “", "Reads", "Read the sentence around what you select", "Connects to", "dict.youdao.com",
                    "apps on this Mac (127.0.0.1:8765)", "May ask to connect to other websites", "Runs code it downloads"]
    let missing = expected.filter { want in !texts.contains { $0.contains(want) } }
    record("the install sheet lists ODH's permissions", missing.isEmpty, missing.isEmpty ? "\(texts.count) lines" : "missing: \(missing.joined(separator: ", "))")
    restartBaron()
    return checks
}

@MainActor
func waitForElement(_ identifier: String, timeout: TimeInterval) -> AXElement? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let baron = NSRunningApplication.runningApplications(withBundleIdentifier: Baron.bundleIdentifier).first,
           let found = findElement(in: AXElement.application(pid: baron.processIdentifier), identifier: identifier) {
            return found
        }
        SyntheticInput.pause(0.2)
    }
    return nil
}

@MainActor
func waitForWindow(titled title: String, timeout: TimeInterval) -> AXElement? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let baron = NSRunningApplication.runningApplications(withBundleIdentifier: Baron.bundleIdentifier).first,
           let window = FixtureWindows.window(titled: title, inApp: baron.processIdentifier) {
            return window
        }
        SyntheticInput.pause(0.2)
    }
    return nil
}

@MainActor
func staticTexts(in element: AXElement, depth: Int = 0) -> [String] {
    var texts: [String] = []
    if element.role == kAXStaticTextRole, let value = element.string(kAXValueAttribute) { texts.append(value) }
    if depth < 14 { for child in element.children { texts += staticTexts(in: child, depth: depth + 1) } }
    return texts
}

@MainActor
func closeTab(_ app: NSRunningApplication, titled title: String) {
    app.activate()
    SyntheticInput.press(keyCode: 53)
    SyntheticInput.pause(0.4)
    if AXElement.application(pid: app.processIdentifier).element(kAXFocusedWindowAttribute)?.title?.contains(title) == true {
        SyntheticInput.press(keyCode: 13, flags: .maskCommand)
    }
    SyntheticInput.pause(0.5)
}
