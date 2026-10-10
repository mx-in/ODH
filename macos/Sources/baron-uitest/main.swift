import AppKit
import BaronAutomation
import BaronCore
import BaronPlatform
import Foundation

// baron-uitest: drives real apps to measure Accessibility coverage and check Baron's bar.
//
//   baron-uitest [--only TextEdit,Safari] [--modes word,sentence,paragraph] [--no-copy] [--out dir]
//   baron-uitest --plugins | --permissions | --settings | --context | --webviews | --helper <probe> | --install <packages> | --bar-shows <action>   (scripts/uitest-*.sh)
//
// For each app: open a fixture, then for each mode select a word (double-click),
// the first sentence (drag) and the paragraph (triple-click) with real mouse events,
// check that Baron's bar appears and its Copy button works, run the probe, grade it,
// and close what the test opened.
// It takes over the mouse and keyboard while it runs.

struct Options {
    var plugins = false
    var permissions = false
    var settings = false
    var install: URL?
    var barShows: String?
    var context = false
    var webviews = false
    var helper: URL?
    var only: Set<String>?
    var copy = true
    var modes = CoverageFixture.Mode.allCases
    var out = URL(fileURLWithPath: "UITests/results")

    init(_ arguments: [String]) {
        var rest = arguments.dropFirst()
        while let argument = rest.popFirst() {
            switch argument {
            case "--plugins": plugins = true
            case "--permissions": permissions = true
            case "--settings": settings = true
            case "--install": install = URL(fileURLWithPath: rest.popFirst() ?? "")
            case "--bar-shows": barShows = rest.popFirst()
            case "--context": context = true
            case "--webviews": webviews = true
            case "--helper": helper = URL(fileURLWithPath: rest.popFirst() ?? "")
            case "--only": only = Set((rest.popFirst() ?? "").split(separator: ",").map { $0.lowercased() })
            case "--no-copy": copy = false
            case "--modes": modes = (rest.popFirst() ?? "").split(separator: ",").compactMap { CoverageFixture.Mode(rawValue: String($0)) }
            case "--out": out = URL(fileURLWithPath: rest.popFirst() ?? out.path)
            default:
                print("usage: baron-uitest [--only App1,App2] [--modes word,sentence,paragraph] [--no-copy] [--out dir]")
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
func runCase(_ test: AppCase, fixtures: Fixtures, options: Options) async -> [CaseResult] {
    let fixture = fixtures.fixture
    func failAll(_ note: String) -> [CaseResult] {
        log("  ✗ \(note)")
        return options.modes.map { mode in
            var row = CoverageGrader.grade(ProbeReport(appName: test.name, bundleIdentifier: test.bundleIdentifier),
                                           app: "\(test.name) · \(mode.rawValue)", expectsPage: test.expectsPage,
                                           expectsDocument: test.expectsDocument, barShown: nil)
            row.notes.append(note)
            return CaseResult(row: row, report: nil)
        }
    }

    if let reason = test.skipReason { return failAll("skipped: \(reason)") }
    guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: test.bundleIdentifier) != nil else { return failAll("skipped: not installed") }

    let wasRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: test.bundleIdentifier).isEmpty
    do {
        try test.open(fixtures)
    } catch {
        return failAll("could not open the fixture: \(error)")
    }

    guard let app = waitForApp(test.bundleIdentifier) else { return failAll("app did not start") }
    defer { cleanUp(test, app: app, wasRunning: wasRunning) }

    if !test.windowTitle.isEmpty {
        guard let window = FixtureWindows.waitForWindow(titled: test.windowTitle, inApp: app.processIdentifier, timeout: 20) else {
            return failAll("fixture window \"\(test.windowTitle)\" never appeared")
        }
        FixtureWindows.raise(window)
    }
    app.activate()
    SyntheticInput.pause(1.0)

    var results: [CaseResult] = []
    for mode in options.modes {
        results.append(await runMode(mode, test: test, app: app, fixture: fixture, options: options))
        SyntheticInput.pause(0.6)
    }
    return results
}

/// Makes one selection of `mode` in the open fixture, then checks the bar and grades the probe.
@MainActor
func runMode(_ mode: CoverageFixture.Mode, test: AppCase, app: NSRunningApplication, fixture: CoverageFixture, options: Options) async -> CaseResult {
    let label = "\(test.name) · \(mode.rawValue)"
    let expected = fixture.expectation(for: mode)
    var row = CoverageGrader.grade(ProbeReport(appName: test.name, bundleIdentifier: test.bundleIdentifier), app: label, mode: mode,
                                   expectsPage: test.expectsPage, expectsDocument: test.expectsDocument, barShown: nil)
    func fail(_ note: String) -> CaseResult {
        row.notes.append(note)
        log("  ✗ \(label): \(note)")
        return CaseResult(row: row, report: nil)
    }

    // Clear the previous selection and bar so this mode starts clean.
    SyntheticInput.press(keyCode: 53)
    app.activate()
    SyntheticInput.pause(0.4)

    BaronBarDetector.waitUntilHidden()
    let pid = app.processIdentifier
    var method = ""
    switch mode {
    case .word, .paragraph:
        guard let hit = WordLocator.locate(fixture.target, inApp: pid) else { return fail("could not find \"\(fixture.target)\" in the Accessibility tree") }
        method = hit.method
        if mode == .word { SyntheticInput.doubleClick(at: hit.point) } else { SyntheticInput.tripleClick(at: hit.point) }
    case .sentence:
        guard
            let start = WordLocator.locate(fixture.sentenceStartWord, inApp: pid),
            let end = WordLocator.locate(fixture.sentenceEndWord, inApp: pid)
        else { return fail("could not find the sentence's first and last words") }
        method = "\(start.method) → \(end.method)"
        SyntheticInput.drag(from: start.leadingPoint, to: end.trailingPoint)
    }
    row.notes.append("found by \(method)")

    let timeToBar = BaronBarDetector.timeUntilBar(since: SyntheticInput.lastMouseUp)
    let barShown = timeToBar != nil
    // Read before the Copy button runs, while Baron's latest "shown" line is this selection's.
    let logLine = barShown ? BaronBarDetector.lastShownLogLine() : nil
    var barCopy: String?
    if barShown {
        let backup = PasteboardBackup()
        NSPasteboard.general.clearContents()
        if BaronBarDetector.pressAction("builtin.copy") {
            SyntheticInput.pause(0.3)
            barCopy = NSPasteboard.general.string(forType: .string)
        }
        backup.restore()
    }

    let report = await SelectionProbe.run(on: app, includeCopy: options.copy)
    let notes = row.notes
    row = CoverageGrader.grade(report, app: label, fixture: fixture, mode: mode, expectsPage: test.expectsPage,
                               expectsDocument: test.expectsDocument, barShown: barShown)
    row.notes = notes
    row.timeToBarMilliseconds = timeToBar
    row.appDetected = barShown ? CoverageGrader.gradeDetectedApp(logLine: logLine, expected: test.bundleIdentifier) : .notRun
    if barShown {
        row.notes.append("bar Copy button: \(CoverageGrader.gradeText(barCopy, expected: expected.selection).rawValue)")
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

    if options.plugins || options.permissions || options.settings || options.install != nil || options.barShows != nil || options.context || options.webviews || options.helper != nil {
        let previousApp = NSWorkspace.shared.frontmostApplication
        let clipboard = PasteboardBackup()
        let checks = options.helper != nil ? await runHelperChecks(probe: options.helper!) : options.webviews ? await runWebViewChecks() : options.context ? await runContextChecks() : options.barShows != nil ? await runBarShowsChecks(action: options.barShows!) : options.install != nil ? await runInstallChecks(packages: options.install!) : options.settings ? await runSettingsChecks() : options.permissions ? await runPermissionChecks() : await runPluginChecks()
        clipboard.restore()
        previousApp?.activate()
        var markdown = "# baron-uitest \(options.helper != nil ? "helper" : options.webviews ? "web view" : options.context ? "context" : options.barShows != nil ? "author" : options.install != nil ? "install" : options.settings ? "settings" : options.permissions ? "permission" : "plugin") checks\n\n| Check | Result | Detail |\n| --- | --- | --- |\n"
        markdown += checks.map { "| \($0.name) | \($0.passed ? "pass" : "FAIL") | \($0.detail.replacingOccurrences(of: "|", with: "\\|")) |" }.joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(at: options.out, withIntermediateDirectories: true)
        try? markdown.write(to: options.out.appendingPathComponent(options.helper != nil ? "helper.md" : options.webviews ? "webviews.md" : options.context ? "context.md" : options.barShows != nil ? "author.md" : options.install != nil ? "install.md" : options.settings ? "settings.md" : options.permissions ? "permissions.md" : "plugins.md"), atomically: true, encoding: .utf8)
        print(markdown)
        exit(checks.allSatisfy(\.passed) && !checks.isEmpty ? 0 : 1)
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
        results += await runCase(test, fixtures: fixtures, options: options)
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
