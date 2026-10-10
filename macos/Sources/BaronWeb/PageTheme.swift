import AppKit

/// Baron's colours as CSS variables for plugin pages, for light and dark appearance, with `prefers-color-scheme`
/// following the system. Pages keep full control: the defaults use `:where()`, so any rule of theirs wins.
/// Design: docs/design/plugin-platform/07-web-views.md#look-and-feel
public enum PageTheme {
    /// The variable names and the system colours they take.
    static let colours: [(String, NSColor)] = [
        ("--baron-background", .windowBackgroundColor),
        ("--baron-text", .labelColor),
        ("--baron-secondary-text", .secondaryLabelColor),
        ("--baron-tertiary-text", .tertiaryLabelColor),
        ("--baron-accent", .controlAccentColor),
        ("--baron-link", .linkColor),
        ("--baron-separator", .separatorColor),
        ("--baron-control-background", .controlBackgroundColor),
        ("--baron-selection", .selectedTextBackgroundColor),
    ]

    public static var css: String {
        func block(_ appearance: NSAppearance.Name) -> String {
            var lines: [String] = []
            NSAppearance(named: appearance)?.performAsCurrentDrawingAppearance {
                lines = colours.map { "\($0.0): \(rgba($0.1));" }
            }
            return lines.joined(separator: " ")
        }
        return """
        :root { color-scheme: light dark; \(block(.aqua)) --baron-font: -apple-system, system-ui, sans-serif; }
        @media (prefers-color-scheme: dark) { :root { \(block(.darkAqua)) } }
        :where(html) { background: var(--baron-background); color: var(--baron-text); font: 13px var(--baron-font); }
        :where(a) { color: var(--baron-link); }
        """
    }

    /// A user script adding the stylesheet before the page's own styles.
    static var script: String {
        "(() => { const style = document.createElement('style'); style.textContent = \(JSONString(css)); (document.head || document.documentElement).prepend(style); })();"
    }

    static func rgba(_ colour: NSColor) -> String {
        guard let c = colour.usingColorSpace(.sRGB) else { return "transparent" }
        func channel(_ value: CGFloat) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
        return "rgba(\(channel(c.redComponent)), \(channel(c.greenComponent)), \(channel(c.blueComponent)), \(String(format: "%.3f", c.alphaComponent)))"
    }

    private static func JSONString(_ text: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data("[\"\"]".utf8)
        return String(decoding: data.dropFirst().dropLast(), as: UTF8.self)
    }
}
