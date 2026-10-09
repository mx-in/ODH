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

@MainActor
func probe(_ options: Options) async -> ProbeReport? {
    let running: NSRunningApplication?
    if let bundleIdentifier = options.bundleIdentifier {
        running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
    } else {
        running = FocusedElementReader.frontmostApplication
    }
    guard let running else { return nil }
    return await SelectionProbe.run(on: running, includeCopy: options.copy)
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
