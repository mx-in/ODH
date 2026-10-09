import Foundation

/// The text every UI-test fixture contains, and what a correct reading looks like.
public struct CoverageFixture: Sendable {
    public var target: String
    public var sentence: String
    public var paragraph: String

    public static let standard = CoverageFixture(
        target: "quokka",
        sentence: "The quick brown quokka jumps over the lazy dog.",
        paragraph: "The quick brown quokka jumps over the lazy dog. Then it runs into the forest."
    )

    /// Three paragraphs; the middle one holds the target word.
    public var text: String {
        "Baron fixture first paragraph.\n\(paragraph)\nLast paragraph with a link https://example.com here.\n"
    }

    /// The first and last words of `sentence`, where a sentence drag starts and ends.
    public var sentenceStartWord: String { String(sentence.split(separator: " ").first ?? "") }
    public var sentenceEndWord: String { String(sentence.split(separator: " ").last ?? "") }

    /// How much of the fixture a UI test selects.
    public enum Mode: String, CaseIterable, Codable, Sendable {
        /// Double-click the target word.
        case word
        /// Drag from the sentence's first word to its last.
        case sentence
        /// Triple-click the target word.
        case paragraph
    }

    public struct Expectation: Sendable {
        public var selection: String
        public var sentence: String
        public var paragraph: String
    }

    /// Selecting the whole paragraph spans both its sentences, so the sentence span is the paragraph.
    public func expectation(for mode: Mode) -> Expectation {
        switch mode {
        case .word: Expectation(selection: target, sentence: sentence, paragraph: paragraph)
        case .sentence: Expectation(selection: sentence, sentence: sentence, paragraph: paragraph)
        case .paragraph: Expectation(selection: paragraph, sentence: paragraph, paragraph: paragraph)
        }
    }
}

public enum Grade: String, Codable, Sendable {
    case pass = "✓"
    case partial = "~"
    case fail = "✗"
    case notApplicable = "–"
    case notRun = "not run"
}

/// One app's row in the coverage table.
public struct CoverageRow: Codable, Equatable, Sendable {
    public var app: String
    public var selectedText: Grade
    /// Which API family gave the context: "web", "native" or "none".
    public var contextSource: String
    public var sentence: Grade
    public var paragraph: Grade
    public var pageURL: Grade
    public var pageTitle: Grade
    public var windowTitle: Grade
    public var document: Grade
    public var bounds: Grade
    public var menuCopy: Grade
    public var keyCopy: Grade
    public var bar: Grade
    /// The slowest Accessibility read, in milliseconds (copy steps excluded).
    public var slowestReadMilliseconds: Double
    public var copyMilliseconds: [String: Double]
    public var notes: [String]
    /// The app Baron itself reported for the selection, graded against the app under test.
    public var appDetected: Grade = .notRun
    /// From the gesture's last mouse-up to Baron's bar on screen.
    public var timeToBarMilliseconds: Double?

    static let headers = ["App", "Selected text", "Context from", "Sentence", "Paragraph", "Page URL", "Page title", "Window title", "Document", "Bounds", "Menu copy", "⌘C", "Bar shown", "Time to bar", "App detected", "Slowest AX read"]

    public static var markdownHeader: String {
        "| " + headers.joined(separator: " | ") + " |\n|" + String(repeating: " --- |", count: headers.count)
    }

    public var markdown: String {
        let cells = [
            app, selectedText.rawValue, contextSource, sentence.rawValue, paragraph.rawValue,
            pageURL.rawValue, pageTitle.rawValue, windowTitle.rawValue, document.rawValue, bounds.rawValue,
            withTime(menuCopy, ProbeField.menuCopy), withTime(keyCopy, ProbeField.keyCopy), bar.rawValue,
            timeToBarMilliseconds.map { String(format: "%@ %.0f ms", CoverageGrader.gradeTimeToBar($0).rawValue, $0) } ?? "–",
            appDetected.rawValue,
            String(format: "%.1f ms", slowestReadMilliseconds),
        ]
        return "| " + cells.joined(separator: " | ") + " |"
    }

    private func withTime(_ grade: Grade, _ field: String) -> String {
        guard let ms = copyMilliseconds[field], grade != .notRun else { return grade.rawValue }
        return String(format: "%@ %.0f ms", grade.rawValue, ms)
    }
}

/// Grades a probe report against the fixture.
public enum CoverageGrader {
    public static func grade(
        _ report: ProbeReport,
        app: String,
        fixture: CoverageFixture = .standard,
        mode: CoverageFixture.Mode = .word,
        expectsPage: Bool,
        expectsDocument: Bool,
        barShown: Bool?
    ) -> CoverageRow {
        let value: (String) -> String? = { field in report.readings.first { $0.field == field }?.value.flatMap { $0.isEmpty ? nil : $0 } }
        let ran: (String) -> Bool = { field in report.readings.contains { $0.field == field } }

        let expected = fixture.expectation(for: mode)
        let selected = best([value(ProbeField.selectedText), value(ProbeField.webSelection)].map { gradeText($0, expected: expected.selection) })

        let web = (value(ProbeField.webSentence), value(ProbeField.webParagraph))
        let native = (value(ProbeField.nativeSentence), value(ProbeField.nativeParagraph))
        let webGrades = (gradeSpan(web.0, expected: expected.sentence, target: expected.selection), gradeSpan(web.1, expected: expected.paragraph, target: expected.selection))
        let nativeGrades = (gradeSpan(native.0, expected: expected.sentence, target: expected.selection), gradeSpan(native.1, expected: expected.paragraph, target: expected.selection))
        let useWeb = rank(webGrades.0) + rank(webGrades.1) >= rank(nativeGrades.0) + rank(nativeGrades.1)
        let context = useWeb ? webGrades : nativeGrades
        let contextSource = context.0 == .fail && context.1 == .fail ? "none" : (useWeb ? "web" : "native")

        let slowest = report.readings
            .filter { $0.field != ProbeField.menuCopy && $0.field != ProbeField.keyCopy }
            .map(\.milliseconds).max() ?? 0
        var copyTimes: [String: Double] = [:]
        for reading in report.readings where reading.field == ProbeField.menuCopy || reading.field == ProbeField.keyCopy {
            copyTimes[reading.field] = reading.milliseconds
        }

        return CoverageRow(
            app: app,
            selectedText: selected,
            contextSource: contextSource,
            sentence: context.0,
            paragraph: context.1,
            pageURL: expectsPage ? present(value(ProbeField.pageURL)) : notApplicableUnlessPresent(value(ProbeField.pageURL)),
            pageTitle: expectsPage ? present(value(ProbeField.pageTitle)) : notApplicableUnlessPresent(value(ProbeField.pageTitle)),
            windowTitle: present(value(ProbeField.windowTitle)),
            document: expectsDocument ? present(value(ProbeField.windowDocument)) : notApplicableUnlessPresent(value(ProbeField.windowDocument)),
            bounds: present(value(ProbeField.webBounds) ?? value(ProbeField.nativeBounds)),
            menuCopy: ran(ProbeField.menuCopy) ? gradeText(value(ProbeField.menuCopy), expected: expected.selection) : .notRun,
            keyCopy: ran(ProbeField.keyCopy) ? gradeText(value(ProbeField.keyCopy), expected: expected.selection) : .notRun,
            bar: barShown.map { $0 ? .pass : .fail } ?? .notRun,
            slowestReadMilliseconds: slowest,
            copyMilliseconds: copyTimes,
            notes: []
        )
    }

    /// The design's goal is the bar within 150 ms of the selection; up to 300 ms is partial.
    public static let timeToBarGoal: Double = 150

    public static func gradeTimeToBar(_ milliseconds: Double) -> Grade {
        if milliseconds <= timeToBarGoal { return .pass }
        return milliseconds <= timeToBarGoal * 2 ? .partial : .fail
    }

    /// Grades Baron's own log line ("… app=com.example … result=shown …") against the app under test.
    public static func gradeDetectedApp(logLine: String?, expected bundleIdentifier: String) -> Grade {
        guard let line = logLine, let token = line.split(separator: " ").first(where: { $0.hasPrefix("app=") }) else { return .fail }
        return token.dropFirst("app=".count) == bundleIdentifier ? .pass : .fail
    }

    /// Exactly the expected text passes (surrounding whitespace ignored); text that merely contains it is partial.
    public static func gradeText(_ value: String?, expected: String) -> Grade {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return .fail }
        if value == expected { return .pass }
        return value.contains(expected) ? .partial : .fail
    }

    /// `value` is the probe's bracketed form, e.g. "The quick [quokka] jumps." with an optional " (truncated)".
    /// It passes when the text matches `expected` and the bracketed part is `target` (whitespace ignored at both).
    public static func gradeSpan(_ value: String?, expected: String, target: String) -> Grade {
        guard var text = value else { return .fail }
        if text.hasSuffix(" (truncated)") { text.removeLast(" (truncated)".count) }
        let plain = text.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let bracketed: String? = {
            guard let open = text.firstIndex(of: "["), let close = text.lastIndex(of: "]"), open < close else { return nil }
            return String(text[text.index(after: open)..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
        }()
        if plain == expected, bracketed == target { return .pass }
        return plain.contains(target) || target.contains(plain) && !plain.isEmpty ? .partial : .fail
    }

    private static func present(_ value: String?) -> Grade { value == nil ? .fail : .pass }
    private static func notApplicableUnlessPresent(_ value: String?) -> Grade { value == nil ? .notApplicable : .pass }

    private static func rank(_ grade: Grade) -> Int {
        switch grade {
        case .pass: 2
        case .partial: 1
        default: 0
        }
    }

    private static func best(_ grades: [Grade]) -> Grade {
        grades.max { rank($0) < rank($1) } ?? .fail
    }
}
