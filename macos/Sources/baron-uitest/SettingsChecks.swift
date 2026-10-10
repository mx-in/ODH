import AppKit
import BaronAutomation
import BaronCore
import BaronPlatform
import BaronRuntime
import Foundation

// `baron-uitest --settings` (scripts/uitest-settings.sh installs the probe first): drives a plugin's settings page
// against a mock AnkiConnect, checking every control, options from the plugin, buttons, saving, secrets and grants.

@MainActor
func runSettingsChecks() async -> [PluginCheck] {
    var checks: [PluginCheck] = []
    func record(_ name: String, _ passed: Bool, _ detail: String) {
        checks.append(PluginCheck(name: name, passed: passed, detail: detail))
        log("  \(passed ? "✓" : "✗") \(name): \(detail)")
    }
    let id = "org.baron.uitest.settings-probe"
    let location = PluginDataLocation.standard
    let data = location.dataRoot.appendingPathComponent(id)
    try? FileManager.default.removeItem(at: data)
    try? SecretStore().removeAll(pluginID: id)
    // A run-time grant to remove later.
    try? FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
    try? #"[{"permission": "network:dict.cn", "answer": "alwaysAllow", "decidedAt": "2026-10-11T00:00:00Z"}]"#.write(to: data.appendingPathComponent("grants.json"), atomically: true, encoding: .utf8)

    let anki: MockAnkiConnect
    do { anki = try MockAnkiConnect() } catch {
        record("mock AnkiConnect starts", false, "\(error)")
        return checks
    }
    defer { anki.stop() }

    for running in NSRunningApplication.runningApplications(withBundleIdentifier: Baron.bundleIdentifier) { running.terminate() }
    SyntheticInput.pause(1.5)
    try? Shell.open(["build/Baron.app", "--args", "--open-plugin-settings", id])
    SyntheticInput.pause(4)

    guard let window = waitForWindow(titled: "Settings", timeout: 6) else {
        record("the settings page opens", false, "no Settings window")
        return checks
    }
    record("the settings page opens", true, window.title ?? "")

    // Every control is there.
    let controls = ["ankiUrl", "testAnki", "deck", "noteType", "fieldExpression", "maxExamples", "duplicate", "dictionaries.collins",
                    "scripts.new", "apiKey", "wordList", "exportFolder", "browser"]
    SyntheticInput.pause(1.5)
    let missing = controls.filter { findElement(in: window, identifier: "pref.\($0)") == nil }
    record("every preference type has its control", missing.isEmpty, missing.isEmpty ? "\(controls.count) controls" : "missing: \(missing.joined(separator: ", "))")

    // Options from the plugin, through the mock AnkiConnect.
    let asked = anki.requests
    record("dropdowns fill from AnkiConnect", asked.contains("deckNames") && asked.contains("modelNames") && asked.contains("modelFieldNames(Basic)"),
           "asked: \(asked.joined(separator: ", "))")
    if let deck = findElement(in: window, identifier: "pref.deck") {
        record("the deck dropdown lists the decks", menuTitles(deck).contains("Vocabulary"), "options: \(menuTitles(deck).joined(separator: ", "))")
        choose("Vocabulary", in: deck)
    }

    // Changing the note type reloads the field dropdown.
    if let noteType = findElement(in: window, identifier: "pref.noteType") {
        choose("Cloze", in: noteType)
        SyntheticInput.pause(1.5)
        record("changing the note type refreshes the field options", anki.requests.contains("modelFieldNames(Cloze)"),
               "asked: \(anki.requests.suffix(3).joined(separator: ", "))")
        if let field = findElement(in: window, identifier: "pref.fieldExpression") {
            record("the field dropdown shows the new fields", menuTitles(field).contains("Back Extra"), "options: \(menuTitles(field).joined(separator: ", "))")
        }
    }

    // A button and its result line.
    if let button = findElement(in: window, identifier: "pref.testAnki") {
        AXUIElementPerformAction(button.raw, kAXPressAction as CFString)
        SyntheticInput.pause(1.5)
        let result = findElement(in: window, identifier: "pref.testAnki.result")?.string(kAXValueAttribute)
        record("the button shows its result", result == "Connected to AnkiConnect 6", result ?? "no result line")
    }

    // A checklist and a list, saved to preferences.json.
    if let cambridge = findElement(in: window, identifier: "pref.dictionaries.cambridge") {
        AXUIElementPerformAction(cambridge.raw, kAXPressAction as CFString)
    }
    if let field = findElement(in: window, identifier: "pref.scripts.new") {
        focus(field)
        SyntheticInput.type("https://example.com/dict.js")
        SyntheticInput.pause(0.3)
        if let add = findElement(in: window, identifier: "pref.scripts.add") { AXUIElementPerformAction(add.raw, kAXPressAction as CFString) }
    }
    SyntheticInput.pause(1.5)
    let saved = (try? String(contentsOf: data.appendingPathComponent("preferences.json"), encoding: .utf8)) ?? ""
    record("list and checklist edits are saved", saved.contains("https:\\/\\/example.com\\/dict.js") || saved.contains("https://example.com/dict.js"),
           saved.isEmpty ? "nothing saved" : saved)
    record("choices are saved", saved.contains("\"cambridge\"") && saved.contains("\"Vocabulary\"") && saved.contains("\"Cloze\""), saved)

    // A secret goes to the Keychain, never to preferences.json.
    if let secret = findElement(in: window, identifier: "pref.apiKey") {
        focus(secret)
        SyntheticInput.type("sk-test")
        if let save = findElement(in: window, identifier: "pref.apiKey.save") { AXUIElementPerformAction(save.raw, kAXPressAction as CFString) }
        SyntheticInput.pause(1)
    }
    let keychain = (try? SecretStore().get("apiKey", pluginID: id)) ?? nil
    record("a secret is saved in the Keychain", keychain == "sk-test" && !saved.contains("sk-test"), keychain == nil ? "not in the Keychain" : "in the Keychain only")

    // Removing a run-time grant; the Permissions section is further down the page.
    scrollToEnd(window)
    if let remove = findElement(in: window, identifier: "grant.network:dict.cn.remove") {
        AXUIElementPerformAction(remove.raw, kAXPressAction as CFString)
        SyntheticInput.pause(1)
        let grants = (try? String(contentsOf: data.appendingPathComponent("grants.json"), encoding: .utf8)) ?? ""
        record("a grant can be removed", !grants.contains("dict.cn"), grants)
    } else {
        let texts = staticTexts(in: window).filter { $0.contains("dict") || $0.contains("Allowed") || $0.contains("Permissions") || $0.contains("Connect") }
        record("a grant can be removed", false, "no Remove button for network:dict.cn; page shows: \(texts.joined(separator: " | "))")
    }

    // With the required deck empty, running the action opens its settings instead.
    try? FileManager.default.removeItem(at: data.appendingPathComponent("preferences.json"))
    window.element(kAXCloseButtonAttribute).map { AXUIElementPerformAction($0.raw, kAXPressAction as CFString) }
    SyntheticInput.pause(1)
    let page = FileManager.default.temporaryDirectory.appendingPathComponent("baron-settings.html")
    try? "<!doctype html><meta charset=\"utf-8\"><title>baron-settings</title><p>The quick brown fox jumps.</p>".write(to: page, atomically: true, encoding: .utf8)
    try? Shell.open(["-a", "Safari", page.path])
    if let safari = waitForApp("com.apple.Safari"),
       let tab = FixtureWindows.waitForWindow(titled: "baron-settings", inApp: safari.processIdentifier, timeout: 20) {
        FixtureWindows.raise(tab)
        safari.activate()
        SyntheticInput.pause(1.2)
        if let word = WordLocator.locate("quick", inApp: safari.processIdentifier) {
            SyntheticInput.doubleClick(at: word.point)
            let pressed = BaronBarDetector.waitForBar(timeout: 2.5) && BaronBarDetector.pressAction("plugin:\(id)/probe")
            let reopened = pressed ? waitForWindow(titled: "Settings", timeout: 4) : nil
            let deckShown = reopened.flatMap { findElement(in: $0, identifier: "pref.deck") } != nil
            record("an empty required field opens the settings first", reopened != nil && deckShown,
                   pressed ? (reopened == nil ? "no Settings window" : "settings opened on the plugin") : "no probe button")
            reopened?.element(kAXCloseButtonAttribute).map { AXUIElementPerformAction($0.raw, kAXPressAction as CFString) }
        }
        closeTab(safari, titled: "baron-settings")
    }

    try? SecretStore().removeAll(pluginID: id)
    try? FileManager.default.removeItem(at: data)
    for running in NSRunningApplication.runningApplications(withBundleIdentifier: Baron.bundleIdentifier) { running.terminate() }
    SyntheticInput.pause(1)
    try? Shell.open(["build/Baron.app"])
    return checks
}

/// The titles a pop-up button offers.
@MainActor
func menuTitles(_ popUp: AXElement) -> [String] {
    AXUIElementPerformAction(popUp.raw, kAXPressAction as CFString)
    SyntheticInput.pause(0.4)
    let titles = popUp.children.flatMap { menu in menu.children.compactMap(\.title) }
    SyntheticInput.press(keyCode: 53)
    SyntheticInput.pause(0.3)
    return titles
}

/// Picks a menu item of a pop-up button.
@MainActor
func choose(_ title: String, in popUp: AXElement) {
    AXUIElementPerformAction(popUp.raw, kAXPressAction as CFString)
    SyntheticInput.pause(0.4)
    for menu in popUp.children {
        if let item = menu.children.first(where: { $0.title == title }) {
            AXUIElementPerformAction(item.raw, kAXPressAction as CFString)
            SyntheticInput.pause(0.8)
            return
        }
    }
    SyntheticInput.press(keyCode: 53)
}

/// Clicks a field so typing goes into it.
@MainActor
func focus(_ field: AXElement) {
    field.set(kAXFocusedAttribute, to: kCFBooleanTrue)
    if let frame = field.frame { SyntheticInput.click(at: CGPoint(x: frame.midX, y: frame.midY)) }
    SyntheticInput.pause(0.3)
}

/// Scrolls every scroll area in the window to its end, so rows built lazily appear in the tree.
@MainActor
func scrollToEnd(_ window: AXElement) {
    func visit(_ element: AXElement, _ depth: Int) {
        if element.role == "AXScrollArea", let bar = element.element(kAXVerticalScrollBarAttribute) {
            bar.set(kAXValueAttribute, to: NSNumber(value: 1.0))
        }
        if depth < 10 { element.children.forEach { visit($0, depth + 1) } }
    }
    visit(window, 0)
    SyntheticInput.pause(0.8)
}
