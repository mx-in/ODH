import AppKit
import BaronAutomation
import BaronPlatform
import Foundation

// `baron-uitest --webviews` (scripts/uitest-webviews.sh installs examples/panel in the development folder): opens
// the definition panel from the bar in Safari and checks its placement, content, size, a message from the page to
// the plugin and back, and the close rules (Escape, pin, close button, app switch).

@MainActor
func runWebViewChecks() async -> [PluginCheck] {
    var checks: [PluginCheck] = []
    func record(_ name: String, _ passed: Bool, _ detail: String) {
        checks.append(PluginCheck(name: name, passed: passed, detail: detail))
        log("  \(passed ? "✓" : "✗") \(name): \(detail)")
    }
    let action = "plugin:org.baron.example.panel/define"
    let page = FileManager.default.temporaryDirectory.appendingPathComponent("baron-webviews.html")
    try? "<!doctype html><meta charset=\"utf-8\"><title>baron-webviews</title><p style=\"margin:200px 80px;font:18px sans-serif\">The quick brown fox jumps.</p>"
        .write(to: page, atomically: true, encoding: .utf8)
    try? Shell.open(["-a", "Safari", page.path])
    guard let safari = waitForApp("com.apple.Safari"),
          let tab = FixtureWindows.waitForWindow(titled: "baron-webviews", inApp: safari.processIdentifier, timeout: 20) else {
        record("Safari opens the page", false, "no window")
        return checks
    }
    FixtureWindows.raise(tab)
    safari.activate()
    SyntheticInput.pause(1.2)
    defer { closeTab(safari, titled: "baron-webviews") }

    /// Double-clicks "fox", runs the panel action, and returns the panel's window once its page shows the word.
    func openPanel() -> (window: AXElement, word: CGPoint)? {
        SyntheticInput.press(keyCode: 53)
        safari.activate()
        SyntheticInput.pause(0.5)
        guard let word = WordLocator.locate("fox", inApp: safari.processIdentifier) else { return nil }
        SyntheticInput.doubleClick(at: word.point)
        guard BaronBarDetector.waitForBar(timeout: 2.5), BaronBarDetector.pressAction(action) else { return nil }
        guard let panel = waitForWindow(titled: "Define in Panel", timeout: 10) else { return nil }
        _ = waitUntil(8) { staticTexts(in: panel).contains("fox") }
        return (panel, word.point)
    }
    func panelOpen() -> Bool { waitForWindow(titled: "Define in Panel", timeout: 0.3) != nil }

    // 1. The panel opens next to the selection with Baron's header, sized to its content.
    guard let (panel, word) = openPanel() else {
        record("the panel opens from the bar", false, "no panel (is the dictionary reachable?)")
        return checks
    }
    let frame = panel.frame ?? .zero
    let texts = staticTexts(in: panel)
    record("the panel opens next to the selection", abs(frame.midY - word.y) < 400 && abs(frame.midX - word.x) < 400,
           "panel \(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))×\(Int(frame.height)); word at \(Int(word.x)),\(Int(word.y))")
    record("the header names the plugin and the page shows the word", texts.contains("Define in Panel") && texts.contains("fox"),
           texts.prefix(6).joined(separator: " | "))
    record("the page sizes the panel to its content", frame.height != 348 && frame.height <= 668, "height \(Int(frame.height)) (default 348)")

    // 2. A click in the page sends a message to the plugin, which copies and answers.
    NSPasteboard.general.clearContents()
    if let copy = firstElement(in: panel, role: "AXButton", titled: "Copy") ?? findElement(in: panel, title: "Copy") {
        if let f = copy.frame { SyntheticInput.click(at: CGPoint(x: f.midX, y: f.midY)) }
        let copied = waitUntil(4) { NSPasteboard.general.string(forType: .string)?.hasPrefix("fox") == true }
        let answered = waitUntil(3) { staticTexts(in: panel).contains("Copied.") }
        record("messages flow from the page to the plugin and back", copied && answered,
               "clipboard: \(NSPasteboard.general.string(forType: .string) ?? "empty"); page shows Copied.: \(answered)")
    } else {
        record("messages flow from the page to the plugin and back", false, "no Copy button in the page")
    }

    // 3. Escape closes it.
    SyntheticInput.press(keyCode: 53)
    record("Escape closes the panel", waitUntil(2) { !panelOpen() }, "")

    // 4. Pinned, a click outside leaves it open; the close button closes it.
    if let (pinned, _) = openPanel(), let pin = findElement(in: pinned, identifier: "resultPanel.pin") {
        AXUIElementPerformAction(pin.raw, kAXPressAction as CFString)
        SyntheticInput.pause(0.4)
        if let f = tab.frame { SyntheticInput.click(at: CGPoint(x: f.minX + 40, y: f.maxY - 40)) }
        SyntheticInput.pause(0.8)
        let stayed = panelOpen()
        if let close = waitForWindow(titled: "Define in Panel", timeout: 1).flatMap({ findElement(in: $0, identifier: "resultPanel.close") }) {
            AXUIElementPerformAction(close.raw, kAXPressAction as CFString)
        }
        record("a pinned panel stays open; the close button closes it", stayed && waitUntil(2) { !panelOpen() }, "stayed after a click outside: \(stayed)")
    } else {
        record("a pinned panel stays open; the close button closes it", false, "couldn't open or pin the panel")
    }

    // 5. Switching apps closes it.
    if openPanel() != nil {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app"))
        record("switching apps closes the panel", waitUntil(3) { !panelOpen() }, "")
        safari.activate()
    } else {
        record("switching apps closes the panel", false, "couldn't open the panel")
    }
    return checks
}
