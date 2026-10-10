import AppKit
import BaronAutomation
import Foundation

// `baron-uitest --helper` (scripts/uitest-helper.sh): installs a probe plugin whose onInstall waits three seconds,
// checks its code runs in the sandboxed BaronPluginHost.xpc, stops the helper mid-hook (the error reaches the
// user), and installs again (the helper starts again and the hook finishes). Needs no mouse or keyboard.

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

    // 3. The next need starts the helper again and the hook finishes.
    guard install() else {
        record("the next action works", false, "no install sheet the second time")
        return checks
    }
    let toast = waitForToast(timeout: 8) ?? ""
    record("the next action works in a new helper", toast == "helper probe: installed" && helperPID() != nil && helperPID() != pid,
           "\(toast); helper pid \(helperPID().map(String.init) ?? "none")")
    return checks
}

func pgrep(_ name: String) -> pid_t? {
    guard let output = try? Shell.output("/usr/bin/pgrep", ["-x", name]) else { return nil }
    return output.split(separator: "\n").first.flatMap { pid_t($0) }
}
