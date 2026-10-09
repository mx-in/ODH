import AppKit
import BaronCore

/// Reads every field Baron knows how to read from an app's current selection, timing each one.
/// Used by `baron-probe` and `baron-uitest`.
@MainActor
public enum SelectionProbe {
    public static func run(on running: NSRunningApplication, includeCopy: Bool) async -> ProbeReport {
        var report = ProbeReport(appName: running.localizedName ?? "?", bundleIdentifier: running.bundleIdentifier ?? "?")
        let app = AXElement.application(pid: running.processIdentifier)

        report.record(ProbeField.wake) {
            AccessibilityWaker.wake(app).manualAccessibilitySet ? "accepted (Electron)" : nil
        }

        var focused: AXElement?
        report.record(ProbeField.focusedRole) {
            focused = FocusedElementReader.focusedElement(in: app)
            return focused.map { [$0.role, $0.subrole].compactMap { $0 }.joined(separator: " / ") }
        }

        let window = WindowReader.focusedWindow(of: app)
        report.record(ProbeField.windowTitle) { window.flatMap(WindowReader.title) }
        report.record(ProbeField.windowDocument) { window.flatMap(WindowReader.documentURL)?.absoluteString }

        if let element = focused {
            readSelection(in: element, into: &report)
        }

        if includeCopy {
            for method in CopyReader.Method.allCases {
                let clock = ContinuousClock()
                let started = clock.now
                let text = await CopyReader.copySelection(using: method)
                report.record(ProbeField.copy(method), value: text, milliseconds: (clock.now - started).milliseconds)
            }
        }
        return report
    }

    private static func readSelection(in element: AXElement, into report: inout ProbeReport) {
        report.record(ProbeField.selectedText) { SelectedTextReader.selectedText(of: element) }

        var web: (range: AXTextMarkerRange, owner: AXElement)?
        report.record(ProbeField.webSelection) {
            web = WebSelectionReader.selectedRange(near: element)
            return web.flatMap { WebSelectionReader.string(for: $0.range, in: $0.owner) }
        }
        report.record(ProbeField.webSentence) { web.flatMap { describe(WebContextReader.contextSpan(.sentence, around: $0.range, in: $0.owner)) } }
        report.record(ProbeField.webParagraph) { web.flatMap { describe(WebContextReader.contextSpan(.paragraph, around: $0.range, in: $0.owner)) } }
        report.record(ProbeField.webBounds) { web.flatMap { describe(SelectionBoundsReader.bounds(ofWebSelection: $0.range, in: $0.owner)) } }

        let area = WebAreaReader.webArea(containing: element)
        report.record(ProbeField.pageURL) { area.flatMap(WebAreaReader.url)?.absoluteString }
        report.record(ProbeField.pageTitle) { area.flatMap(WebAreaReader.title) }

        var native: NativeTextWindowReader.Window?
        report.record(ProbeField.nativeWindow) {
            native = NativeTextWindowReader.window(around: element)
            return native.map { "\($0.text.utf16.count) units, selection \($0.selection)" }
        }
        var paragraph: TextSpan?
        report.record(ProbeField.nativeParagraph) {
            paragraph = native.flatMap {
                NativeTextContext.paragraph(in: $0.text, selection: $0.selection, windowStartsAtDocumentStart: $0.startsAtDocumentStart, windowEndsAtDocumentEnd: $0.endsAtDocumentEnd)
            }
            return describe(paragraph)
        }
        report.record(ProbeField.nativeSentence) { describe(paragraph.flatMap(NativeTextContext.sentence)) }
        report.record(ProbeField.nativeBounds) { describe(SelectionBoundsReader.bounds(ofNativeSelectionIn: element)) }
    }

    /// The span's text with the selection in brackets, e.g. "The quick [fox] jumps."
    public static func describe(_ span: TextSpan?) -> String? {
        guard let span else { return nil }
        let units = Array(span.text.utf16)
        let before = String(decoding: units[..<span.selectionStart], as: UTF16.self)
        let selected = String(decoding: units[span.selectionStart..<span.selectionEnd], as: UTF16.self)
        let after = String(decoding: units[span.selectionEnd...], as: UTF16.self)
        return before + "[" + selected + "]" + after + (span.truncated ? " (truncated)" : "")
    }

    public static func describe(_ rect: CGRect?) -> String? {
        rect.map { String(format: "x %.0f y %.0f w %.0f h %.0f", $0.origin.x, $0.origin.y, $0.width, $0.height) }
    }
}
