import Testing
@testable import BaronCore

struct CoverageGraderTests {
    private let fixture = CoverageFixture.standard

    private func report(_ values: [String: String?]) -> ProbeReport {
        var report = ProbeReport(appName: "App", bundleIdentifier: "com.example")
        for (field, value) in values.sorted(by: { $0.key < $1.key }) {
            report.record(field, value: value, milliseconds: field.hasPrefix("copy") ? 120 : 2)
        }
        return report
    }

    @Test func nativeAppWithEverythingPasses() {
        let row = CoverageGrader.grade(report([
            ProbeField.selectedText: "quokka",
            ProbeField.nativeSentence: "The quick brown [quokka] jumps over the lazy dog.",
            ProbeField.nativeParagraph: "The quick brown [quokka] jumps over the lazy dog. Then it runs into the forest.",
            ProbeField.windowTitle: "fixture.txt",
            ProbeField.windowDocument: "file:///tmp/fixture.txt",
            ProbeField.nativeBounds: "x 1 y 2 w 3 h 4",
        ]), app: "TextEdit", expectsPage: false, expectsDocument: true, barShown: true)
        #expect(row.selectedText == .pass)
        #expect(row.contextSource == "native")
        #expect(row.sentence == .pass)
        #expect(row.paragraph == .pass)
        #expect(row.pageURL == .notApplicable)
        #expect(row.document == .pass)
        #expect(row.bounds == .pass)
        #expect(row.bar == .pass)
        #expect(row.menuCopy == .notRun)
    }

    @Test func browserUsesTheWebContext() {
        let row = CoverageGrader.grade(report([
            ProbeField.webSelection: "quokka",
            ProbeField.webSentence: "The quick brown [quokka] jumps over the lazy dog.",
            ProbeField.webParagraph: "The quick brown [quokka] jumps over the lazy dog. Then it runs into the forest.",
            ProbeField.pageURL: "file:///tmp/fixture.html",
            ProbeField.pageTitle: nil,
            ProbeField.menuCopy: "quokka",
            ProbeField.keyCopy: nil,
        ]), app: "Safari", expectsPage: true, expectsDocument: false, barShown: false)
        #expect(row.contextSource == "web")
        #expect(row.pageURL == .pass)
        #expect(row.pageTitle == .fail)
        #expect(row.menuCopy == .pass)
        #expect(row.keyCopy == .fail)
        #expect(row.bar == .fail)
        #expect(row.markdown.contains("✓ 120 ms"))
    }

    @Test func wrongSpanIsPartial() {
        #expect(CoverageGrader.gradeSpan("whole [quokka] document text", expected: fixture.sentence, target: "quokka") == .partial)
        #expect(CoverageGrader.gradeSpan("The quick brown [quokka] jumps over the lazy dog. (truncated)", expected: fixture.sentence, target: "quokka") == .pass)
        #expect(CoverageGrader.gradeSpan(nil, expected: fixture.sentence, target: "quokka") == .fail)
    }

    @Test func extraTextAroundTheWordIsPartial() {
        #expect(CoverageGrader.gradeText(" quokka ", expected: "quokka") == .pass)
        #expect(CoverageGrader.gradeText("brown quokka", expected: "quokka") == .partial)
        #expect(CoverageGrader.gradeText("fox", expected: "quokka") == .fail)
    }

    @Test func nothingReadMeansNoContext() {
        let row = CoverageGrader.grade(report([:]), app: "Game", expectsPage: false, expectsDocument: false, barShown: nil)
        #expect(row.contextSource == "none")
        #expect(row.selectedText == .fail)
        #expect(row.bar == .notRun)
    }

    @Test func fixtureTextHoldsTheParagraph() {
        #expect(fixture.text.contains("\n\(fixture.paragraph)\n"))
        #expect(fixture.paragraph.hasPrefix(fixture.sentence))
    }
}

struct CoverageModeTests {
    private let fixture = CoverageFixture.standard

    @Test func sentenceAndParagraphModesExpectLongerSelections() {
        #expect(fixture.expectation(for: .sentence).selection == fixture.sentence)
        #expect(fixture.expectation(for: .paragraph).selection == fixture.paragraph)
        #expect(fixture.expectation(for: .paragraph).sentence == fixture.paragraph)
        #expect(fixture.sentenceStartWord == "The")
        #expect(fixture.sentenceEndWord == "dog.")
    }

    @Test func sentenceSelectionIsGradedAgainstTheSentence() {
        var report = ProbeReport(appName: "App", bundleIdentifier: "x")
        report.record(ProbeField.selectedText, value: fixture.sentence, milliseconds: 1)
        report.record(ProbeField.nativeSentence, value: "[\(fixture.sentence)]", milliseconds: 1)
        report.record(ProbeField.nativeParagraph, value: "[\(fixture.sentence)] Then it runs into the forest.", milliseconds: 1)
        let row = CoverageGrader.grade(report, app: "App", mode: .sentence, expectsPage: false, expectsDocument: false, barShown: true)
        #expect(row.selectedText == .pass)
        #expect(row.sentence == .pass)
        #expect(row.paragraph == .pass)
    }

    @Test func paragraphSelectionMayIncludeTheLineBreak() {
        let value = "[\(fixture.paragraph)\n]"
        #expect(CoverageGrader.gradeSpan(value, expected: fixture.paragraph, target: fixture.paragraph) == .pass)
        #expect(CoverageGrader.gradeText(fixture.paragraph + "\n", expected: fixture.paragraph) == .pass)
    }

    @Test func wordModeStillNeedsTheBracketOnTheWord() {
        let value = "[The quick brown quokka jumps over the lazy dog.]"
        #expect(CoverageGrader.gradeSpan(value, expected: fixture.sentence, target: "quokka") == .partial)
    }
}

struct TimingAndAppTests {
    @Test func timeToBarIsGradedAgainstTheGoal() {
        #expect(CoverageGrader.gradeTimeToBar(90) == .pass)
        #expect(CoverageGrader.gradeTimeToBar(150) == .pass)
        #expect(CoverageGrader.gradeTimeToBar(220) == .partial)
        #expect(CoverageGrader.gradeTimeToBar(400) == .fail)
    }

    @Test func detectedAppComesFromBaronsLogLine() {
        let line = "2026-10-10 Baron: trigger=doubleClick app=com.apple.TextEdit result=shown step=ax-text length=6"
        #expect(CoverageGrader.gradeDetectedApp(logLine: line, expected: "com.apple.TextEdit") == .pass)
        #expect(CoverageGrader.gradeDetectedApp(logLine: line, expected: "com.apple.Safari") == .fail)
        #expect(CoverageGrader.gradeDetectedApp(logLine: nil, expected: "com.apple.Safari") == .fail)
    }

    @Test func rowShowsTheNewColumns() {
        var row = CoverageGrader.grade(ProbeReport(appName: "A", bundleIdentifier: "a"), app: "A", expectsPage: false, expectsDocument: false, barShown: true)
        row.timeToBarMilliseconds = 87
        row.appDetected = .pass
        #expect(row.markdown.contains("| ✓ 87 ms | ✓ |"))
        #expect(CoverageRow.markdownHeader.contains("Time to bar | App detected"))
    }
}
