import AppKit
import BaronCore

/// Fixture files written fresh for each run.
struct Fixtures {
    let directory: URL
    let fixture = CoverageFixture.standard

    var text: URL { directory.appendingPathComponent("baron-fixture.txt") }
    var html: URL { directory.appendingPathComponent("baron-fixture.html") }
    var pdf: URL { directory.appendingPathComponent("baron-fixture.pdf") }
    var command: URL { directory.appendingPathComponent("baron-fixture.command") }

    /// The page title and Mail subject, so windows can be found by title.
    static let title = "Baron fixture"

    func write() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try fixture.text.write(to: text, atomically: true, encoding: .utf8)

        // The target word and the sentence's first and last words sit in their own <span>s,
        // so browsers expose each as its own text element with an exact frame.
        let first = fixture.sentenceStartWord, last = fixture.sentenceEndWord
        var body = fixture.paragraph
        for word in [fixture.target, last] {
            body = body.replacingOccurrences(of: " \(word) ", with: " <span>\(word)</span> ")
        }
        body = "<span>\(first)</span>" + body.dropFirst(first.count)
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><title>\(Self.title)</title>
        <style>body{font:18px -apple-system;margin:40px;max-width:640px}</style></head><body>
        <p>Baron fixture first paragraph.</p>
        <p>\(body)</p>
        <p>Last paragraph with a link <a href="https://example.com">https://example.com</a> here.</p>
        </body></html>
        """
        try html.write(to: self.html, atomically: true, encoding: .utf8)

        try "#!/bin/sh\nclear\ncat '\(text.path)'\n".write(to: command, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: command.path)

        try makePDF()
    }

    private func makePDF() throws {
        let filter = Process()
        filter.executableURL = URL(fileURLWithPath: "/usr/sbin/cupsfilter")
        filter.arguments = [text.path]
        FileManager.default.createFile(atPath: pdf.path, contents: nil)
        filter.standardOutput = try FileHandle(forWritingTo: pdf)
        filter.standardError = FileHandle.nullDevice
        try filter.run()
        filter.waitUntilExit()
    }

    var mailtoURL: URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.queryItems = [URLQueryItem(name: "subject", value: Self.title), URLQueryItem(name: "body", value: fixture.text)]
        return components.url!
    }
}

/// How a test opens its fixture in one app, finds it, and cleans up after itself.
struct AppCase {
    enum Cleanup {
        /// Press the fixture window's close button (and "Don't Save" if asked).
        case closeWindow
        /// ⌘W, only after checking the front window is the fixture (browser tabs).
        case closeTab
        /// Run an AppleScript (Notes: delete the fixture note).
        case script(String)
    }

    let name: String
    let bundleIdentifier: String
    /// Part of the fixture window's title; empty means "the focused window".
    let windowTitle: String
    let expectsPage: Bool
    let expectsDocument: Bool
    let cleanup: Cleanup
    let skipReason: String?
    let open: (Fixtures) throws -> Void

    init(
        _ name: String, _ bundleIdentifier: String, windowTitle: String, expectsPage: Bool = false, expectsDocument: Bool = false,
        cleanup: Cleanup = .closeWindow, skipReason: String? = nil, open: @escaping (Fixtures) throws -> Void = { _ in }
    ) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.expectsPage = expectsPage
        self.expectsDocument = expectsDocument
        self.cleanup = cleanup
        self.skipReason = skipReason
        self.open = open
    }
}

enum Shell {
    @discardableResult
    static func run(_ path: String, _ arguments: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    static func open(_ arguments: [String]) throws {
        try run("/usr/bin/open", arguments)
    }

    /// Runs AppleScript with a timeout, so a pending Automation prompt can't hang the run.
    static func appleScript(_ source: String, timeout: Int = 20) throws -> Bool {
        try run("/usr/bin/osascript", ["-e", "with timeout of \(timeout) seconds\n\(source)\nend timeout"]) == 0
    }
}

extension AppCase {
    static func all() -> [AppCase] {
        let fixture = CoverageFixture.standard
        let noteBody = fixture.text.split(separator: "\n").map { "<div>\($0)</div>" }.joined()
        return [
            AppCase("TextEdit", "com.apple.TextEdit", windowTitle: "baron-fixture", expectsDocument: true) {
                try Shell.open(["-a", "TextEdit", $0.text.path])
            },
            AppCase("Safari", "com.apple.Safari", windowTitle: Fixtures.title, expectsPage: true, cleanup: .closeTab) {
                try Shell.open(["-a", "Safari", $0.html.path])
            },
            AppCase("Chrome", "com.google.Chrome", windowTitle: Fixtures.title, expectsPage: true) {
                try Shell.open(["-na", "Google Chrome", "--args", "--new-window", $0.html.absoluteString])
            },
            AppCase("Arc", "company.thebrowser.Browser", windowTitle: Fixtures.title, expectsPage: true, cleanup: .closeTab) {
                try Shell.open(["-a", "Arc", $0.html.path])
            },
            AppCase("Mail", "com.apple.mail", windowTitle: Fixtures.title) {
                try Shell.open(["-a", "Mail", $0.mailtoURL.absoluteString])
            },
            AppCase("Notes", "com.apple.Notes", windowTitle: "", cleanup: .script(#"tell application "Notes" to delete (every note whose name is "Baron fixture")"#)) { _ in
                let script = """
                tell application "Notes"
                    set theNote to make new note with properties {body:"<h1>Baron fixture</h1>\(noteBody)"}
                    show theNote
                    activate
                end tell
                """
                guard try Shell.appleScript(script) else { throw HarnessError.automationDenied("Notes") }
            },
            AppCase("Pages", "com.apple.iWork.Pages", windowTitle: "baron-fixture") {
                try Shell.open(["-a", "Pages", $0.text.path])
            },
            AppCase("Preview", "com.apple.Preview", windowTitle: "baron-fixture", expectsDocument: true) {
                try Shell.open(["-a", "Preview", $0.pdf.path])
            },
            AppCase("Xcode", "com.apple.dt.Xcode", windowTitle: "baron-fixture", expectsDocument: true) {
                try Shell.open(["-a", "Xcode", $0.text.path])
            },
            AppCase("VS Code", "com.microsoft.VSCode", windowTitle: "baron-fixture") {
                try Shell.open(["-a", "Visual Studio Code", $0.text.path])
            },
            AppCase("Slack", "com.tinyspeck.slackmacgap", windowTitle: "", skipReason: "needs text typed into a real Slack workspace; test by hand"),
            AppCase("Obsidian", "md.obsidian", windowTitle: "", skipReason: "not installed"),
            AppCase("Terminal", "com.apple.Terminal", windowTitle: "") {
                try Shell.open(["-a", "Terminal", $0.command.path])
            },
        ]
    }
}

enum HarnessError: Error, CustomStringConvertible {
    case automationDenied(String)

    var description: String {
        switch self {
        case .automationDenied(let app): "AppleScript to \(app) failed (Automation permission?)"
        }
    }
}
