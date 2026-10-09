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

    static let headers = ["App", "Selected text", "Context from", "Sentence", "Paragraph", "Page URL", "Page title", "Window title", "Document", "Bounds", "Menu copy", "⌘C", "Bar shown", "Slowest AX read"]

    public static var markdownHeader: String {
        "| " + headers.joined(separator: " | ") + " |\n|" + String(repeating: " --- |", count: headers.count)
    }

    public var markdown: String {
        let cells = [
            app, selectedText.rawValue, contextSource, sentence.rawValue, paragraph.rawValue,
            pageURL.rawValue, pageTitle.rawValue, windowTitle.rawValue, document.rawValue, bounds.rawValue,
            withTime(menuCopy, ProbeField.menuCopy), withTime(keyCopy, ProbeField.keyCopy), bar.rawValue,
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
        expectsPage: Bool,
        expectsDocument: Bool,
        barShown: Bool?
    ) -> CoverageRow {
        let value: (String) -> String? = { field in report.readings.first { $0.field == field }?.value.flatMap { $0.isEmpty ? nil : $0 } }
        let ran: (String) -> Bool = { field in report.readings.contains { $0.field == field } }

        let selected = best([value(ProbeField.selectedText), value(ProbeField.webSelection)].map { gradeText($0, expected: fixture.target) })

        let web = (value(ProbeField.webSentence), value(ProbeField.webParagraph))
        let native = (value(ProbeField.nativeSentence), value(ProbeField.nativeParagraph))
        let webGrades = (gradeSpan(web.0, expected: fixture.sentence, target: fixture.target), gradeSpan(web.1, expected: fixture.paragraph, target: fixture.target))
        let nativeGrades = (gradeSpan(native.0, expected: fixture.sentence, target: fixture.target), gradeSpan(native.1, expected: fixture.paragraph, target: fixture.target))
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
            menuCopy: ran(ProbeField.menuCopy) ? gradeText(value(ProbeField.menuCopy), expected: fixture.target) : .notRun,
            keyCopy: ran(ProbeField.keyCopy) ? gradeText(value(ProbeField.keyCopy), expected: fixture.target) : .notRun,
            bar: barShown.map { $0 ? .pass : .fail } ?? .notRun,
            slowestReadMilliseconds: slowest,
            copyMilliseconds: copyTimes,
            notes: []
        )
    }

    /// Exactly the expected word passes; text that merely contains it is partial.
    public static func gradeText(_ value: String?, expected: String) -> Grade {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return .fail }
        if value == expected { return .pass }
        return value.contains(expected) ? .partial : .fail
    }

    /// `value` is the probe's bracketed form, e.g. "The quick [quokka] jumps." with an optional " (truncated)".
    public static func gradeSpan(_ value: String?, expected: String, target: String) -> Grade {
        guard var text = value else { return .fail }
        if text.hasSuffix(" (truncated)") { text.removeLast(" (truncated)".count) }
        let plain = text.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if plain == expected, text.contains("[\(target)]") { return .pass }
        return plain.contains(target) ? .partial : .fail
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
