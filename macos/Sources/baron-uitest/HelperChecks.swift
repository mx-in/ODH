import AppKit
import BaronAutomation
import Foundation

// `baron-uitest --helper` (scripts/uitest-helper.sh): installs a probe plugin whose onInstall waits three seconds,
// checks its code runs in the sandboxed BaronPluginHost.xpc, stops the helper mid-hook (the error reaches the
// user), then runs the probe's action from the bar in Safari (a new helper starts and answers).

@MainActor
func runHelperChecks(probe: URL) async -> [PluginCheck] {
    var checks: [PluginCheck] = []
    func record(_ name: String, _ passed: Bool, _ detail: String) {
        checks.append(PluginCheck(name: name, passed: passed, detail: detail))
        log("  \(passed ? "✓" : "✗") \(name): \(detail)")
    }
    func helperPID() -> pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: "org.odh.baron.plugin-host").first?.processIdentifier
            ?? pgrep("BaronPluginHost")
    }
    let appPath = URL(fileURLWithPath: "build/Baron.app").path

    /// Opens the probe package in Baron and presses Install (or Reinstall) on the sheet.
    func install() -> Bool {
        try? Shell.open(["-a", appPath, probe.path])
        guard let sheet = waitForWindow(titled: "Install Plugin", timeout: 8),
              let button = findElement(in: sheet, identifier: "installSheet.install") else { return false }
        AXUIElementPerformAction(button.raw, kAXPressAction as CFString)
        return true
    }

    // 1. The hook runs in the helper.
    guard install() else {
        record("the probe installs", false, "no install sheet")
        return checks
    }
    let started = waitUntil(3) { helperPID() != nil }
    let pid = helperPID()
    record("plugin code runs in BaronPluginHost.xpc", started, pid.map { "helper pid \($0)" } ?? "no helper process")
    if let pid {
        let sandboxed = (try? Shell.output("/usr/bin/codesign", ["-d", "--entitlements", "-", "build/Baron.app/Contents/XPCServices/BaronPluginHost.xpc"]))?.contains("app-sandbox") == true
        record("the helper is sandboxed", sandboxed, "pid \(pid)")
        // 2. Stopping the helper mid-hook fails the hook with a message for the user.
        kill(pid, SIGKILL)
        let toast = waitForToast(timeout: 6) ?? ""
        record("stopping the helper mid-action reports the plugin as unavailable", toast.contains("Helper probe") && !toast.contains("installed"), toast)
        SyntheticInput.pause(3.5)
    }

    // 3. The next action starts the helper again: run the probe's action from the bar.
    let page = FileManager.default.temporaryDirectory.appendingPathComponent("baron-helper.html")
    try? "<!doctype html><meta charset=\"utf-8\"><title>baron-helper</title><p style=\"margin:200px 80px;font:18px sans-serif\">A zebrafish swims.</p>"
        .write(to: page, atomically: true, encoding: .utf8)
    try? Shell.open(["-a", "Safari", page.path])
    guard let safari = waitForApp("com.apple.Safari"),
          let tab = FixtureWindows.waitForWindow(titled: "baron-helper", inApp: safari.processIdentifier, timeout: 20) else {
        record("the next action works in a new helper", false, "Safari didn't open the page")
        return checks
    }
    FixtureWindows.raise(tab)
    safari.activate()
    SyntheticInput.pause(1.2)
    defer { closeTab(safari, titled: "baron-helper") }
    guard let word = WordLocator.locate("zebrafish", inApp: safari.processIdentifier) else {
        record("the next action works in a new helper", false, "\"zebrafish\" isn't in the Accessibility tree")
        return checks
    }
    SyntheticInput.doubleClick(at: word.point)
    let pressed = BaronBarDetector.waitForBar(timeout: 2.5) && BaronBarDetector.pressAction("plugin:org.baron.uitest.helper-probe/probe")
    let toast = pressed ? waitForToast(timeout: 8) ?? "" : ""
    let fresh = helperPID()
    record("the next action works in a new helper", toast == "helper probe: ran" && fresh != nil && fresh != pid,
           pressed ? "\(toast); helper pid \(fresh.map(String.init) ?? "none") (was \(pid.map(String.init) ?? "none"))" : "no bar or button")
    return checks
}

func pgrep(_ name: String) -> pid_t? {
    guard let output = try? Shell.output("/usr/bin/pgrep", ["-x", name]) else { return nil }
    return output.split(separator: "\n").first.flatMap { pid_t($0) }
}
