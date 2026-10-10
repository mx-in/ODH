import AppKit
import BaronAutomation
import Foundation

// `baron-uitest --bar-shows <action>`: the last step of scripts/uitest-author.sh, which times a new author from
// `baron create` to their action on the bar. Double-clicks a word in an editable text area and runs the action.

@MainActor
func runBarShowsChecks(action: String) async -> [PluginCheck] {
    var checks: [PluginCheck] = []
    func record(_ name: String, _ passed: Bool, _ detail: String) {
        checks.append(PluginCheck(name: name, passed: passed, detail: detail))
        log("  \(passed ? "✓" : "✗") \(name): \(detail)")
    }
    let page = FileManager.default.temporaryDirectory.appendingPathComponent("baron-author.html")
    try? """
    <!doctype html><meta charset="utf-8"><title>baron-author</title>
    <textarea id="text" rows="4" cols="60" autofocus>The quick brown fox jumps over the lazy dog.</textarea>
    """.write(to: page, atomically: true, encoding: .utf8)
    try? Shell.open(["-a", "Safari", page.path])
    guard let safari = waitForApp("com.apple.Safari"),
          let window = FixtureWindows.waitForWindow(titled: "baron-author", inApp: safari.processIdentifier, timeout: 20) else {
        record("Safari opens the page", false, "no window")
        return checks
    }
    FixtureWindows.raise(window)
    safari.activate()
    SyntheticInput.pause(1.5)
    defer { closeDocument(safari) }
    guard let quick = WordLocator.locate("quick", inApp: safari.processIdentifier) else {
        record("find a word", false, "\"quick\" isn't in the Accessibility tree")
        return checks
    }
    SyntheticInput.doubleClick(at: quick.point)
    let bar = BaronBarDetector.waitForBar(timeout: 2.5)
    let shown = bar && BaronBarDetector.hasAction(action)
    record("the new action is on the bar", shown, shown ? action : bar ? "missing; the bar shows \(barActionOrder().joined(separator: ", "))" : "no bar")
    if shown, BaronBarDetector.pressAction(action) {
        SyntheticInput.pause(1)
        let text = documentText(safari) ?? ""
        record("it runs", text.hasPrefix("The QUICK brown fox"), "document reads \"\(text.trimmingCharacters(in: .whitespacesAndNewlines))\"")
    }
    return checks
}
