import AppKit
import BaronCore
import BaronPlatform
import Foundation

// baron-probe: prints what the Accessibility API returns for the current selection.
//
//   baron-probe [--delay seconds] [--app bundle-id] [--copy] [--json]
//
// Run it, switch to the app under test within the delay, and select some text.
// --app reads that running app instead of the frontmost one (it need not be in front).
// --copy also tries Edit › Copy and ⌘C (the clipboard is restored afterwards).

struct Options {
    var delay = 3
    var copy = false
    var json = false
    var bundleIdentifier: String?

    init(_ arguments: [String]) {
        var rest = arguments.dropFirst()
        while let argument = rest.popFirst() {
            switch argument {
            case "--delay": delay = rest.popFirst().flatMap(Int.init) ?? delay
            case "--copy": copy = true
            case "--app": bundleIdentifier = rest.popFirst()
            case "--json": json = true
            case "-h", "--help":
                print("usage: baron-probe [--delay seconds] [--app bundle-id] [--copy] [--json]")
                exit(0)
            default:
                FileHandle.standardError.write(Data("unknown option: \(argument)\n".utf8))
                exit(2)
            }
        }
    }
}

func describe(_ span: TextSpan?) -> String? {
    guard let span else { return nil }
    let units = Array(span.text.utf16)
    let before = String(decoding: units[..<span.selectionStart], as: UTF16.self)
    let selected = String(decoding: units[span.selectionStart..<span.selectionEnd], as: UTF16.self)
    let after = String(decoding: units[span.selectionEnd...], as: UTF16.self)
    return before + "[" + selected + "]" + after + (span.truncated ? " (truncated)" : "")
}

func describe(_ rect: CGRect?) -> String? {
    rect.map { String(format: "x %.0f y %.0f w %.0f h %.0f", $0.origin.x, $0.origin.y, $0.width, $0.height) }
}

@MainActor
func probe(_ options: Options) async -> ProbeReport? {
    let running: NSRunningApplication?
    if let bundleIdentifier = options.bundleIdentifier {
        running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    } else {
        running = FocusedElementReader.frontmostApplication
    }
    guard let running else { return nil }
    var report = ProbeReport(appName: running.localizedName ?? "?", bundleIdentifier: running.bundleIdentifier ?? "?")
    let app = AXElement.application(pid: running.processIdentifier)

    report.record("wake.manualAccessibility") {
        AccessibilityWaker.wake(app).manualAccessibilitySet ? "accepted (Electron)" : nil
    }

    var focused: AXElement?
    report.record("focused.role") {
        focused = FocusedElementReader.focusedElement(in: app)
        return focused.map { [$0.role, $0.subrole].compactMap { $0 }.joined(separator: " / ") }
    }

    let window = WindowReader.focusedWindow(of: app)
    report.record("window.title") { window.flatMap(WindowReader.title) }
    report.record("window.document") { window.flatMap(WindowReader.documentURL)?.absoluteString }

    guard let element = focused else { return report }

    report.record("ax.selectedText") { SelectedTextReader.selectedText(of: element) }

    var web: (range: AXTextMarkerRange, owner: AXElement)?
    report.record("web.selection") {
        web = WebSelectionReader.selectedRange(near: element)
        return web.flatMap { WebSelectionReader.string(for: $0.range, in: $0.owner) }
    }
    report.record("web.sentence") { web.flatMap { describe(WebContextReader.span(.sentence, around: $0.range, in: $0.owner)) } }
    report.record("web.paragraph") { web.flatMap { describe(WebContextReader.span(.paragraph, around: $0.range, in: $0.owner)) } }
    report.record("web.bounds") { web.flatMap { describe(SelectionBoundsReader.bounds(of: $0.range, in: $0.owner)) } }

    let area = WebAreaReader.webArea(containing: element)
    report.record("page.url") { area.flatMap(WebAreaReader.url)?.absoluteString }
    report.record("page.title") { area.flatMap(WebAreaReader.title) }

    var native: NativeTextWindowReader.Window?
    report.record("native.window") {
        native = NativeTextWindowReader.window(around: element)
        return native.map { "\($0.text.utf16.count) units, selection \($0.selection)" }
    }
    var paragraph: TextSpan?
    report.record("native.paragraph") {
        paragraph = native.flatMap {
            NativeTextContext.paragraph(in: $0.text, selection: $0.selection, windowStartsAtDocumentStart: $0.startsAtDocumentStart, windowEndsAtDocumentEnd: $0.endsAtDocumentEnd)
        }
        return describe(paragraph)
    }
    report.record("native.sentence") { describe(paragraph.flatMap(NativeTextContext.sentence)) }
    report.record("native.bounds") { describe(SelectionBoundsReader.bounds(ofNativeSelectionIn: element)) }

    if options.copy {
        for method in CopyReader.Method.allCases {
            let clock = ContinuousClock()
            var text: String?
            let started = clock.now
            text = await CopyReader.copySelection(using: method)
            report.record("copy.\(method.rawValue)", value: text, milliseconds: (clock.now - started).milliseconds)
        }
    }
    return report
}

let options = Options(CommandLine.arguments)

guard AccessibilityPermission.isGranted else {
    print("""
    baron-probe needs Accessibility access.
    Add your terminal app in System Settings › Privacy & Security › Accessibility, then run again.
    """)
    AccessibilityPermission.openSystemSettings()
    exit(1)
}

if options.delay > 0 {
    FileHandle.standardError.write(Data("Switch to the app and select text. Reading in \(options.delay) s…\n".utf8))
    Thread.sleep(forTimeInterval: TimeInterval(options.delay))
}

Task { @MainActor in
    guard let report = await probe(options) else {
        print("No such app running.")
        exit(1)
    }
    if options.json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try! encoder.encode(report), as: UTF8.self))
    } else {
        print(report.table())
    }
    exit(0)
}
RunLoop.main.run()
