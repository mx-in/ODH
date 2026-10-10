import AppKit
import BaronAutomation
import BaronCore
import Foundation

// `baron-uitest --context` (scripts/uitest-context.sh installs the two fixture plugins): in Safari, Chrome, Mail,
// Notes, Pages and TextEdit, double-clicks the fixture's target word and runs a plugin granted every context
// permission, then one granted none, reading back which fields each received.

@MainActor
func runContextChecks() async -> [PluginCheck] {
    var checks: [PluginCheck] = []
    func record(_ name: String, _ passed: Bool, _ detail: String) {
        checks.append(PluginCheck(name: name, passed: passed, detail: detail))
        log("  \(passed ? "✓" : "✗") \(name): \(detail)")
    }
    let fixtures = Fixtures(directory: FileManager.default.temporaryDirectory.appendingPathComponent("baron-uitest-context"))
    do { try fixtures.write() } catch {
        record("write the fixtures", false, "\(error)")
        return checks
    }
    let fixture = fixtures.fixture
    let apps = ["Safari", "Chrome", "Mail", "Notes", "Pages", "TextEdit"]
    for test in AppCase.all() where apps.contains(test.name) {
        log("\(test.name)")
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: test.bundleIdentifier) != nil else {
            record("\(test.name): context arrives", false, "not installed")
            continue
        }
        let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: test.bundleIdentifier).isEmpty
        guard (try? test.open(fixtures)) != nil, let app = waitForApp(test.bundleIdentifier) else {
            record("\(test.name): context arrives", false, "couldn't open the fixture")
            continue
        }
        if !test.windowTitle.isEmpty, let window = FixtureWindows.waitForWindow(titled: test.windowTitle, inApp: app.processIdentifier, timeout: 20) {
            FixtureWindows.raise(window)
        }
        app.activate()
        SyntheticInput.pause(1.0)

        for granted in [true, false] {
            let action = granted ? "plugin:org.baron.uitest.context-probe/read" : "plugin:org.baron.uitest.context-blind/read"
            let name = "\(test.name): \(granted ? "context arrives with the permissions" : "no context without them")"
            SyntheticInput.press(keyCode: 53)
            app.activate()
            SyntheticInput.pause(0.4)
            BaronBarDetector.waitUntilHidden()
            guard let hit = WordLocator.locate(fixture.target, inApp: app.processIdentifier) else {
                record(name, false, "\"\(fixture.target)\" isn't in the Accessibility tree")
                continue
            }
            SyntheticInput.doubleClick(at: hit.point)
            guard BaronBarDetector.waitForBar(timeout: 2.5), BaronBarDetector.pressAction(action) else {
                record(name, false, "the bar or its button didn't show")
                continue
            }
            guard let toast = waitForToast(timeout: 5) else {
                record(name, false, "no answer from the plugin")
                continue
            }
            let parts = toast.split(separator: "|", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            let fields = Set((parts.first ?? "").replacingOccurrences(of: "context: ", with: "").split(separator: ",").map(String.init))
            let sentence = parts.count > 1 ? parts[1] : ""
            if granted {
                var wanted: Set<String> = ["window", "sentence", "paragraph"]
                if test.expectsPage { wanted.insert("page") }
                record(name, wanted.isSubset(of: fields) && sentence == fixture.sentence, toast)
            } else {
                record(name, fields == ["none"], toast)
            }
            SyntheticInput.pause(2.5) // let the toast go
        }
        cleanUp(test, app: app, wasRunning: wasRunning)
    }
    return checks
}
