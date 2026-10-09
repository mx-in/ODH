import AppKit
import BaronAutomation
import BaronCore
import BaronPlatform
import Foundation

// baron-uitest: drives real apps to measure Accessibility coverage and check Baron's bar.
//
//   baron-uitest [--only TextEdit,Safari] [--no-copy] [--out dir]
//
// For each app: open a fixture, find the word "quokka" through Accessibility,
// double-click it with real mouse events, check that Baron's bar appears and its
// Copy button works, run the probe, grade it, and close what the test opened.
// It takes over the mouse and keyboard while it runs.

struct Options {
    var only: Set<String>?
    var copy = true
    var out = URL(fileURLWithPath: "UITests/results")

    init(_ arguments: [String]) {
        var rest = arguments.dropFirst()
        while let argument = rest.popFirst() {
            switch argument {
            case "--only": only = Set((rest.popFirst() ?? "").split(separator: ",").map { $0.lowercased() })
            case "--no-copy": copy = false
            case "--out": out = URL(fileURLWithPath: rest.popFirst() ?? out.path)
            default:
                print("usage: baron-uitest [--only App1,App2] [--no-copy] [--out dir]")
                exit(2)
            }
        }
    }
}

struct CaseResult: Codable {
    var row: CoverageRow
    var report: ProbeReport?
}

@MainActor
func runCase(_ test: AppCase, fixtures: Fixtures, options: Options) async -> CaseResult {
    let fixture = fixtures.fixture
    var row = CoverageGrader.grade(ProbeReport(appName: test.name, bundleIdentifier: test.bundleIdentifier), app: test.name,
                                   expectsPage: test.expectsPage, expectsDocument: test.expectsDocument, barShown: nil)
    func fail(_ note: String) -> CaseResult {
        row.notes.append(note)
        log("  ✗ \(note)")
        return CaseResult(row: row, report: nil)
    }

    if let reason = test.skipReason { return fail("skipped: \(reason)") }
    guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: test.bundleIdentifier) != nil else { return fail("skipped: not installed") }

    let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: test.bundleIdentifier).isEmpty
    do {
        try test.open(fixtures)
    } catch {
        return fail("could not open the fixture: \(error)")
    }

    guard let app = waitForApp(test.bundleIdentifier) else { return fail("app did not start") }
    defer { cleanUp(test, app: app, wasRunning: wasRunning) }

    var window: AXElement?
    if !test.windowTitle.isEmpty {
        window = FixtureWindows.waitForWindow(titled: test.windowTitle, inApp: app.processIdentifier, timeout: 20)
        guard let window else { return fail("fixture window \"\(test.windowTitle)\" never appeared") }
        FixtureWindows.raise(window)
    }
    app.activate()
    SyntheticInput.pause(1.0)

    guard let hit = WordLocator.locate(fixture.target, inApp: app.processIdentifier) else {
        return fail("could not find \"\(fixture.target)\" in the Accessibility tree")
    }
    row.notes.append("word found by \(hit.method)")

    SyntheticInput.doubleClick(at: hit.point)
    let barShown = BaronBarDetector.waitForBar(timeout: 2.5)
    var barCopy: String?
    if barShown {
        let backup = PasteboardBackup()
        NSPasteboard.general.clearContents()
        if BaronBarDetector.pressAction("builtin.copy") {
            SyntheticInput.pause(0.3)
            barCopy = NSPasteboard.general.string(forType: .string)
        }
        backup.restore()
        // Pressing a bar button hides the bar, but the app keeps its selection.
    }

    let report = await SelectionProbe.run(on: app, includeCopy: options.copy)
    row = CoverageGrader.grade(report, app: test.name, fixture: fixture, expectsPage: test.expectsPage,
                               expectsDocument: test.expectsDocument, barShown: barShown)
    row.notes.append("word found by \(hit.method)")
    if barShown {
        row.notes.append("bar Copy button: \(CoverageGrader.gradeText(barCopy, expected: fixture.target).rawValue)")
    }
    log("  \(row.markdown)")
    return CaseResult(row: row, report: report)
}

@MainActor
func waitForApp(_ bundleIdentifier: String, timeout: TimeInterval = 20) -> NSRunningApplication? {
    let deadline = Date().addingTimeInterval(timeout)
    repeat {
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first, app.isFinishedLaunching {
            return app
        }
        SyntheticInput.pause(0.3)
    } while Date() < deadline
    return nil
}

@MainActor
func cleanUp(_ test: AppCase, app: NSRunningApplication, wasRunning: Bool) {
    SyntheticInput.press(keyCode: 53) // Escape: drop the selection and any bar.
    switch test.cleanup {
    case .closeWindow:
        if !test.windowTitle.isEmpty, let window = FixtureWindows.window(titled: test.windowTitle, inApp: app.processIdentifier) {
            FixtureWindows.close(window)
        }
    case .closeTab:
        app.activate()
        SyntheticInput.pause(0.4)
        let front = AXElement.application(pid: app.processIdentifier).element(kAXFocusedWindowAttribute)
        if front?.title?.localizedCaseInsensitiveContains(test.windowTitle) == true {
            SyntheticInput.press(keyCode: 13, flags: .maskCommand) // ⌘W
        } else {
            log("  ! left the fixture tab open: the front window wasn't the fixture")
        }
    case .script(let source):
        _ = try? Shell.appleScript(source)
    }
    if !wasRunning {
        SyntheticInput.pause(0.5)
        app.terminate()
    }
    SyntheticInput.pause(1.0)
}

func log(_ line: String) {
    FileHandle.standardError.write(Data((line + "\n").utf8))
}

@MainActor
func ensureBaronRunning() -> Bool {
    if !NSRunningApplication.runningApplications(withBundleIdentifier: Baron.bundleIdentifier).isEmpty { return false }
    let app = URL(fileURLWithPath: "build/Baron.app")
    guard FileManager.default.fileExists(atPath: app.path) else {
        log("! build/Baron.app is missing; run scripts/build-app.sh first. Bar checks will fail.")
        return false
    }
    try? Shell.open([app.path])
    SyntheticInput.pause(2)
    return true
}

@MainActor
func main() async {
    let options = Options(CommandLine.arguments)
    guard AccessibilityPermission.isGranted else {
        log("baron-uitest needs Accessibility access for the terminal it runs in.")
        exit(1)
    }

    let fixtures = Fixtures(directory: FileManager.default.temporaryDirectory.appendingPathComponent("baron-uitest"))
    do { try fixtures.write() } catch {
        log("could not write fixtures: \(error)")
        exit(1)
    }

    let launchedBaron = ensureBaronRunning()
    let previousApp = NSWorkspace.shared.frontmostApplication
    let clipboard = PasteboardBackup()

    var results: [CaseResult] = []
    for test in AppCase.all() where options.only.map({ $0.contains(test.name.lowercased()) }) ?? true {
        log("▶ \(test.name)")
        results.append(await runCase(test, fixtures: fixtures, options: options))
    }

    clipboard.restore()
    previousApp?.activate()
    if launchedBaron {
        NSRunningApplication.runningApplications(withBundleIdentifier: Baron.bundleIdentifier).first?.terminate()
    }

    let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
    var markdown = "# baron-uitest results \(stamp)\n\n" + CoverageRow.markdownHeader + "\n"
    markdown += results.map(\.row.markdown).joined(separator: "\n") + "\n\n## Notes\n\n"
    markdown += results.map { "- **\($0.row.app):** " + $0.row.notes.joined(separator: "; ") }.joined(separator: "\n") + "\n"

    try? FileManager.default.createDirectory(at: options.out, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try? encoder.encode(results).write(to: options.out.appendingPathComponent("latest.json"))
    try? markdown.write(to: options.out.appendingPathComponent("latest.md"), atomically: true, encoding: .utf8)
    print(markdown)
    exit(0)
}

Task { @MainActor in await main() }
RunLoop.main.run()
