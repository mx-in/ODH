import Testing
@testable import BaronCore

struct ProbeReportTests {
    @Test func emptyValueCountsAsMissing() {
        #expect(ProbeReading(field: "a", value: "", milliseconds: 0).status == .missing)
        #expect(ProbeReading(field: "a", value: nil, milliseconds: 0).status == .missing)
        #expect(ProbeReading(field: "a", value: "x", milliseconds: 0).status == .ok)
    }

    @Test func recordTimesTheRead() {
        var report = ProbeReport(appName: "TextEdit", bundleIdentifier: "com.apple.TextEdit")
        report.record("selectedText") { "hello" }
        #expect(report.readings.count == 1)
        #expect(report.readings[0].value == "hello")
        #expect(report.readings[0].milliseconds >= 0)
    }

    @Test func tableFlattensAndCutsValues() {
        var report = ProbeReport(appName: "Notes", bundleIdentifier: "com.apple.Notes")
        report.record("paragraph", value: "line one\nline two", milliseconds: 1.25)
        let table = report.table(valueWidth: 10)
        #expect(table.contains("line one⏎…"))
        #expect(table.contains("ok"))
        #expect(table.contains("  1.2") || table.contains("  1.3"))
    }
}
